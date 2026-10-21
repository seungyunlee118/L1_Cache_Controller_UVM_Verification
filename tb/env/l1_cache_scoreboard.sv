`timescale 1ns/1ps

`uvm_analysis_imp_decl(_req)
`uvm_analysis_imp_decl(_rsp)
`uvm_analysis_imp_decl(_mem)
`uvm_analysis_imp_decl(_rst)

class l1_cache_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(l1_cache_scoreboard)

    typedef struct {
        bit [31:0] addr;
        bit [31:0] exp_data;    // what the cache model says the line holds
        bit [31:0] arch_data;   // what the last store to this address wrote
        bit        skip;        // line was poisoned by an async reset
    } pending_read_t;

    typedef struct {
        bit        rw;                          // 1 = eviction, 0 = fill
        bit [31:0] addr;                        // line aligned
        bit [31:0] beats [WORDS_PER_LINE];
        bit        skip;
    } exp_mem_t;

    uvm_analysis_imp_req #(l1_cache_item,       l1_cache_scoreboard) req_export;
    uvm_analysis_imp_rsp #(l1_cache_item,       l1_cache_scoreboard) rsp_export;
    uvm_analysis_imp_mem #(l1_cache_mem_item,   l1_cache_scoreboard) mem_export;
    uvm_analysis_imp_rst #(l1_cache_reset_item, l1_cache_scoreboard) rst_export;

    // Annotated transactions (hit/way/victim filled in) for the coverage subscriber
    uvm_analysis_port #(l1_cache_item) cov_ap;

    // ---- golden model ------------------------------------------------------
    // Geometry and address split are taken from the spec, not from the
    // l1_cache_pkg helpers the RTL calls. A bug in a shared helper sits in
    // the DUT and in the model at the same time, so no comparison between
    // them can see it - the mutation campaign (sim/xcelium/mutate.py)
    // showed a PLRU and a word-select bug in l1_cache_pkg passing every test
    // while the model reused those helpers.
    localparam int M_SETS  = 64;   // addr[9:4]
    localparam int M_WAYS  = 4;
    localparam int M_WORDS = 4;    // addr[3:2]

    bit [21:0] m_tag   [M_SETS][M_WAYS];   // addr[31:10]
    bit        m_valid [M_SETS][M_WAYS];
    bit        m_dirty [M_SETS][M_WAYS];
    bit [31:0] m_data  [M_SETS][M_WAYS][M_WORDS];

    // Tree-PLRU, one tree per set. Node 0 is the root over the pairs
    // {0,1} / {2,3}, node 1 sits over ways {0,1}, node 2 over ways {2,3}.
    // A node holding 1 points at its upper child: that side has the next
    // victim. Touching a way points every node on its path the other way.
    bit        m_plru  [M_SETS][3];

    bit [31:0] main_mem [int];   // predicted DRAM, keyed by word address
    bit        poisoned [int];   // line addresses whose DRAM content is uncertain

    // ---- architectural reference -------------------------------------------
    // A flat memory with no cache in it: every store lands here at once and
    // every load must return what is here. A cache is meant to be invisible,
    // so this has to agree with the DUT whatever ways, victims and
    // write-backs look like - it is the check that still holds if the cache
    // model and the DUT ever share a mistake.
    bit [31:0] arch_mem [int];

    pending_read_t rd_q     [$];
    exp_mem_t      exp_mem_q[$];

    // ---- statistics --------------------------------------------------------
    int match_cnt, mismatch_cnt, skipped_cnt;
    int arch_cnt, arch_mismatch_cnt;   // flat-memory check, counted on its own
    int total_reads, total_writes;
    int hit_cnt, miss_cnt, evict_cnt, reset_cnt;
    int way_use [WAYS];
    int set_coverage [int];

    function new(string name = "l1_cache_scoreboard", uvm_component parent);
        super.new(name, parent);
        req_export = new("req_export", this);
        rsp_export = new("rsp_export", this);
        mem_export = new("mem_export", this);
        rst_export = new("rst_export", this);
        cov_ap     = new("cov_ap", this);
    endfunction

    // Value DRAM hands back for a word nobody has written yet. Address
    // dependent on purpose: a constant would hide word-select bugs inside a
    // line, because every beat of a cold fill would look identical.
    // Must agree with l1_cache_mem_driver.
    function bit [31:0] mem_value(bit [31:0] word_addr);
        return main_mem.exists(word_addr) ? main_mem[word_addr] : `L1_MEM_DEFAULT(word_addr);
    endfunction

    function bit [31:0] arch_value(bit [31:0] word_addr);
        return arch_mem.exists(word_addr) ? arch_mem[word_addr] : `L1_MEM_DEFAULT(word_addr);
    endfunction

    // ---- spec address split ------------------------------------------------
    function int        ref_set (bit [31:0] a); return int'(a[9:4]);   endfunction
    function bit [21:0] ref_tag (bit [31:0] a); return a[31:10];       endfunction
    function int        ref_word(bit [31:0] a); return int'(a[3:2]);   endfunction
    function bit [31:0] ref_line(bit [31:0] a); return {a[31:4], 4'b0}; endfunction

    function bit [31:0] ref_line_addr(bit [21:0] tg, int st);
        return {tg, st[5:0], 4'b0};
    endfunction

    // ---- spec tree-PLRU ----------------------------------------------------
    function int ref_plru_victim(int st);
        int pair;
        pair = m_plru[st][0];                   // 0 -> ways {0,1}, 1 -> ways {2,3}
        return 2*pair + m_plru[st][1 + pair];
    endfunction

    function void ref_plru_touch(int st, int way);
        int pair;
        pair = way / 2;
        m_plru[st][0]        = (pair == 0);     // point at the other pair
        m_plru[st][1 + pair] = (way % 2 == 0);  // point at the other way in it
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // The model is written for the geometry in the spec. If the package
        // is ever re-parameterised, stop rather than compare against the
        // wrong shape.
        if (SETS != M_SETS || WAYS != M_WAYS || WORDS_PER_LINE != M_WORDS ||
            ADDR_WIDTH != 32 || DATA_WIDTH != 32)
            `uvm_fatal("SCB_GEOMETRY", $sformatf(
                "l1_cache_pkg geometry (%0d sets, %0d ways, %0d words) differs from the model's spec (%0d/%0d/%0d)",
                SETS, WAYS, WORDS_PER_LINE, M_SETS, M_WAYS, M_WORDS))
    endfunction

    //=========================================================================
    // Reset - flush the model exactly as the DUT flushes its flops.
    //=========================================================================
    virtual function void write_rst(l1_cache_reset_item item);
        reset_cnt++;

        // A write-back burst that was in flight may have delivered only some
        // of its beats, so DRAM for that line is now in a state the model
        // cannot reconstruct. Mark it and stop data-checking it; every
        // protocol, ordering and burst-length check stays live.
        foreach (exp_mem_q[i])
            if (exp_mem_q[i].rw == 1'b1) poisoned[exp_mem_q[i].addr] = 1'b1;

        rd_q.delete();
        exp_mem_q.delete();

        for (int s = 0; s < M_SETS; s++) begin
            for (int n = 0; n < 3; n++) m_plru[s][n] = 1'b0;
            for (int w = 0; w < M_WAYS; w++) begin
                m_valid[s][w] = 1'b0;
                m_dirty[s][w] = 1'b0;
            end
        end

        // Reset throws away every dirty line, so from here on memory is
        // whatever reached DRAM. Lines whose DRAM content is unknown are
        // poisoned above and skipped by both checks.
        arch_mem = main_mem;

        `uvm_info("SCB", $sformatf("Model flushed on reset #%0d (%0d line(s) poisoned so far)",
                                   reset_cnt, poisoned.size()), UVM_LOW)
    endfunction

    //=========================================================================
    // 1. A request was accepted at the CPU interface (read or write)
    //=========================================================================
    virtual function void write_req(l1_cache_item item);
        int            st        = ref_set(item.addr);
        bit [21:0]     tg        = ref_tag(item.addr);
        int            wd        = ref_word(item.addr);
        bit [31:0]     line_addr = ref_line(item.addr);
        bit [31:0]     word_addr = {item.addr[31:2], 2'b00};
        int            way       = -1;
        pending_read_t p;
        exp_mem_t      e;

        if (!set_coverage.exists(st)) set_coverage[st] = 1;
        else                          set_coverage[st]++;

        item.word_off = wd[1:0];

        // ---- look for a hit ------------------------------------------------
        for (int w = 0; w < M_WAYS; w++)
            if (m_valid[st][w] && m_tag[st][w] == tg) way = w;

        item.hit = (way != -1);

        if (item.hit) begin
            hit_cnt++;
            item.victim_state = l1_cache_item::VICTIM_NONE;
        end
        else begin
            miss_cnt++;

            // ---- pick the victim: an invalid way first, else the PLRU tree --
            way = -1;
            for (int w = M_WAYS-1; w >= 0; w--)
                if (!m_valid[st][w]) way = w;
            if (way == -1) way = ref_plru_victim(st);

            if (!m_valid[st][way])       item.victim_state = l1_cache_item::VICTIM_INVALID;
            else if (!m_dirty[st][way])  item.victim_state = l1_cache_item::VICTIM_CLEAN;
            else                         item.victim_state = l1_cache_item::VICTIM_DIRTY;

            // ---- dirty victim is written back first ------------------------
            if (m_valid[st][way] && m_dirty[st][way]) begin
                e.rw   = 1'b1;
                e.addr = ref_line_addr(m_tag[st][way], st);
                e.skip = poisoned.exists(e.addr);
                for (int k = 0; k < M_WORDS; k++) begin
                    e.beats[k]                  = m_data[st][way][k];
                    main_mem[e.addr + (k*4)]    = m_data[st][way][k];
                end
                exp_mem_q.push_back(e);
                item.did_evict = 1'b1;
                evict_cnt++;
            end

            // ---- then the line is fetched ----------------------------------
            e.rw   = 1'b0;
            e.addr = line_addr;
            e.skip = poisoned.exists(line_addr);
            for (int k = 0; k < M_WORDS; k++) begin
                e.beats[k]        = mem_value(line_addr + (k*4));
                m_data[st][way][k] = e.beats[k];
            end
            exp_mem_q.push_back(e);

            m_tag  [st][way] = tg;
            m_valid[st][way] = 1'b1;
            m_dirty[st][way] = 1'b0;
        end

        item.way = way[1:0];
        way_use[way]++;

        // ---- apply the access ----------------------------------------------
        if (item.rw == 1'b1) begin
            bit [31:0] merged;
            total_writes++;
            merged = arch_value(word_addr);
            for (int b = 0; b < 4; b++)
                if (item.be[b]) begin
                    m_data[st][way][wd][b*8 +: 8] = item.wdata[b*8 +: 8];
                    merged[b*8 +: 8]              = item.wdata[b*8 +: 8];
                end
            m_dirty[st][way]    = 1'b1;
            arch_mem[word_addr] = merged;
        end
        else begin
            total_reads++;
            p.addr      = item.addr;
            p.exp_data  = m_data[st][way][wd];
            p.arch_data = arch_value(word_addr);
            p.skip      = poisoned.exists(line_addr);
            rd_q.push_back(p);
        end

        // PLRU is touched on every access, hit or fill.
        ref_plru_touch(st, way);

        cov_ap.write(item);
    endfunction

    //=========================================================================
    // 2. A read response came back from the DUT
    //=========================================================================
    virtual function void write_rsp(l1_cache_item item);
        pending_read_t p;

        if (rd_q.size() == 0) begin
            `uvm_error("SCB_SYNC", $sformatf("Read response with no outstanding read! Addr=0x%08x", item.addr))
            mismatch_cnt++;
            return;
        end

        p = rd_q.pop_front();

        if (p.addr !== item.addr) begin
            `uvm_error("SCB_ORDER", $sformatf("Read responses out of order: expected Addr=0x%08x, got Addr=0x%08x",
                                              p.addr, item.addr))
            mismatch_cnt++;
            return;
        end

        if (p.skip) begin
            skipped_cnt++;
            return;
        end

        if (item.rdata === p.exp_data) begin
            match_cnt++;
        end else begin
            `uvm_error("READ_DATA_BUG", $sformatf("[FAIL] Read Addr=0x%08x: Exp=0x%08x, Act=0x%08x",
                                                  item.addr, p.exp_data, item.rdata))
            mismatch_cnt++;
        end

        // Reported on its own: a DUT that agrees with the cache model but not
        // with flat memory has a bug that the model shares.
        if (item.rdata === p.arch_data) begin
            arch_cnt++;
        end else begin
            `uvm_error("ARCH_DATA_BUG", $sformatf("[FAIL] Read Addr=0x%08x returned 0x%08x, but the last store left 0x%08x",
                                                  item.addr, item.rdata, p.arch_data))
            arch_mismatch_cnt++;
        end
    endfunction

    //=========================================================================
    // 3. A burst was observed on the main-memory interface
    //=========================================================================
    virtual function void write_mem(l1_cache_mem_item item);
        exp_mem_t e;

        if (exp_mem_q.size() == 0) begin
            `uvm_error("MEM_UNEXPECTED",
                       $sformatf("[FAIL] Unexpected memory burst: %s", item.convert2string()))
            mismatch_cnt++;
            return;
        end

        e = exp_mem_q.pop_front();

        if (item.req_rw !== e.rw) begin
            `uvm_error("MEM_DIRECTION",
                       $sformatf("[FAIL] Burst direction: Exp %s 0x%08x, Act %s 0x%08x",
                                 e.rw ? "EVICT" : "FETCH", e.addr,
                                 item.req_rw ? "EVICT" : "FETCH", item.req_addr))
            mismatch_cnt++;
            return;
        end

        if (item.req_addr !== e.addr) begin
            `uvm_error("MEM_ADDR",
                       $sformatf("[FAIL] %s address: Exp=0x%08x, Act=0x%08x",
                                 e.rw ? "Eviction" : "Fetch", e.addr, item.req_addr))
            mismatch_cnt++;
            return;
        end

        if (item.beats.size() != M_WORDS) begin
            `uvm_error("MEM_LEN",
                       $sformatf("[FAIL] Burst to 0x%08x carried %0d beats, expected %0d",
                                 item.req_addr, item.beats.size(), M_WORDS))
            mismatch_cnt++;
            return;
        end

        if (e.skip) begin
            skipped_cnt++;
            return;
        end

        for (int k = 0; k < M_WORDS; k++) begin
            if (item.beats[k] !== e.beats[k]) begin
                `uvm_error(e.rw ? "WRITE_BACK_BUG" : "FILL_DATA_BUG",
                           $sformatf("[FAIL] %s 0x%08x beat %0d: Exp=0x%08x, Act=0x%08x",
                                     e.rw ? "Evict" : "Fetch", e.addr, k, e.beats[k], item.beats[k]))
                mismatch_cnt++;
                return;
            end
        end

        match_cnt++;
    endfunction

    //=========================================================================
    // 4. End of test
    //=========================================================================
    virtual function void check_phase(uvm_phase phase);
        if (total_reads == 0 && total_writes == 0)
            `uvm_error("SCB_NO_TRAFFIC", "Scoreboard saw no CPU transactions at all")
        if (rd_q.size() != 0)
            `uvm_error("SCB_DANGLING", $sformatf("%0d read(s) never got a response", rd_q.size()))
        if (exp_mem_q.size() != 0)
            `uvm_error("SCB_MEM_MISSING", $sformatf("%0d predicted memory burst(s) never happened", exp_mem_q.size()))
        if (mismatch_cnt != 0 || arch_mismatch_cnt != 0)
            `uvm_error("SCB_FAILED", $sformatf("%0d model mismatch(es), %0d architectural mismatch(es)",
                                               mismatch_cnt, arch_mismatch_cnt))
    endfunction

    virtual function void report_phase(uvm_phase phase);
        int  covered_sets = set_coverage.size();
        real set_pct      = (real'(covered_sets) / real'(M_SETS)) * 100.0;
        int  total_req    = total_reads + total_writes;
        real hit_rate     = (total_req == 0) ? 0.0 : (real'(hit_cnt) / real'(total_req)) * 100.0;
        string way_str    = "";

        for (int w = 0; w < M_WAYS; w++) way_str = {way_str, $sformatf(" w%0d=%0d", w, way_use[w])};

        `uvm_info(get_type_name(), "========================================", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" SCOREBOARD SUMMARY: MATCH=%0d, MISMATCH=%0d", match_cnt, mismatch_cnt), UVM_NONE)
        `uvm_info(get_type_name(), "========================================", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" Architectural reads: %0d agree, %0d disagree with flat memory", arch_cnt, arch_mismatch_cnt), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" CPU reads / writes : %0d / %0d", total_reads, total_writes), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" Cache hits / misses: %0d / %0d  (hit rate %0.2f%%)", hit_cnt, miss_cnt, hit_rate), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" Dirty evictions    : %0d", evict_cnt), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" Way utilisation    :%s", way_str), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" Set reach          : %0.2f%% (%0d/%0d)", set_pct, covered_sets, M_SETS), UVM_NONE)
        if (reset_cnt > 0)
            `uvm_info(get_type_name(), $sformatf(" Resets / poisoned  : %0d / %0d line(s), %0d check(s) skipped",
                                                 reset_cnt, poisoned.size(), skipped_cnt), UVM_NONE)
        `uvm_info(get_type_name(), "========================================", UVM_NONE)
    endfunction

endclass
