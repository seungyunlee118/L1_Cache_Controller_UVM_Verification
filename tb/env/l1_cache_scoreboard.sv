`timescale 1ns/1ps

`uvm_analysis_imp_decl(_req)
`uvm_analysis_imp_decl(_rsp)
`uvm_analysis_imp_decl(_mem)
`uvm_analysis_imp_decl(_rst)

class l1_cache_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(l1_cache_scoreboard)

    typedef struct {
        bit [31:0] addr;
        bit [31:0] exp_data;
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
    tag_t      m_tag   [SETS][WAYS];
    bit        m_valid [SETS][WAYS];
    bit        m_dirty [SETS][WAYS];
    bit [31:0] m_data  [SETS][WAYS][WORDS_PER_LINE];
    plru_t     m_plru  [SETS];

    bit [31:0] main_mem [int];   // predicted DRAM, keyed by word address
    bit        poisoned [int];   // line addresses whose DRAM content is uncertain

    pending_read_t rd_q     [$];
    exp_mem_t      exp_mem_q[$];

    // ---- statistics --------------------------------------------------------
    int match_cnt, mismatch_cnt, skipped_cnt;
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

        for (int s = 0; s < SETS; s++) begin
            m_plru[s] = '0;
            for (int w = 0; w < WAYS; w++) begin
                m_valid[s][w] = 1'b0;
                m_dirty[s][w] = 1'b0;
            end
        end

        `uvm_info("SCB", $sformatf("Model flushed on reset #%0d (%0d line(s) poisoned so far)",
                                   reset_cnt, poisoned.size()), UVM_LOW)
    endfunction

    //=========================================================================
    // 1. A request was accepted at the CPU interface (read or write)
    //=========================================================================
    virtual function void write_req(l1_cache_item item);
        set_t          st        = get_set(item.addr);
        tag_t          tg        = get_tag(item.addr);
        word_t         wd        = get_word(item.addr);
        bit [31:0]     line_addr = get_line_addr(item.addr);
        int            way       = -1;
        pending_read_t p;
        exp_mem_t      e;

        if (!set_coverage.exists(st)) set_coverage[st] = 1;
        else                          set_coverage[st]++;

        item.word_off = wd;

        // ---- look for a hit ------------------------------------------------
        for (int w = 0; w < WAYS; w++)
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
            for (int w = WAYS-1; w >= 0; w--)
                if (!m_valid[st][w]) way = w;
            if (way == -1) way = int'(plru_victim(m_plru[st]));

            if (!m_valid[st][way])       item.victim_state = l1_cache_item::VICTIM_INVALID;
            else if (!m_dirty[st][way])  item.victim_state = l1_cache_item::VICTIM_CLEAN;
            else                         item.victim_state = l1_cache_item::VICTIM_DIRTY;

            // ---- dirty victim is written back first ------------------------
            if (m_valid[st][way] && m_dirty[st][way]) begin
                e.rw   = 1'b1;
                e.addr = make_line_addr(m_tag[st][way], st);
                e.skip = poisoned.exists(e.addr);
                for (int k = 0; k < WORDS_PER_LINE; k++) begin
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
            for (int k = 0; k < WORDS_PER_LINE; k++) begin
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
            total_writes++;
            for (int b = 0; b < BE_WIDTH; b++)
                if (item.be[b]) m_data[st][way][wd][b*8 +: 8] = item.wdata[b*8 +: 8];
            m_dirty[st][way] = 1'b1;
        end
        else begin
            total_reads++;
            p.addr     = item.addr;
            p.exp_data = m_data[st][way][wd];
            p.skip     = poisoned.exists(line_addr);
            rd_q.push_back(p);
        end

        // PLRU is touched on every access, hit or fill.
        m_plru[st] = plru_update(m_plru[st], way_t'(way));

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

        if (item.beats.size() != WORDS_PER_LINE) begin
            `uvm_error("MEM_LEN",
                       $sformatf("[FAIL] Burst to 0x%08x carried %0d beats, expected %0d",
                                 item.req_addr, item.beats.size(), WORDS_PER_LINE))
            mismatch_cnt++;
            return;
        end

        if (e.skip) begin
            skipped_cnt++;
            return;
        end

        for (int k = 0; k < WORDS_PER_LINE; k++) begin
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
        if (mismatch_cnt != 0)
            `uvm_error("SCB_FAILED", $sformatf("%0d mismatch(es) detected", mismatch_cnt))
    endfunction

    virtual function void report_phase(uvm_phase phase);
        int  covered_sets = set_coverage.size();
        real set_pct      = (real'(covered_sets) / real'(SETS)) * 100.0;
        int  total_req    = total_reads + total_writes;
        real hit_rate     = (total_req == 0) ? 0.0 : (real'(hit_cnt) / real'(total_req)) * 100.0;
        string way_str    = "";

        for (int w = 0; w < WAYS; w++) way_str = {way_str, $sformatf(" w%0d=%0d", w, way_use[w])};

        `uvm_info(get_type_name(), "========================================", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" SCOREBOARD SUMMARY: MATCH=%0d, MISMATCH=%0d", match_cnt, mismatch_cnt), UVM_NONE)
        `uvm_info(get_type_name(), "========================================", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" CPU reads / writes : %0d / %0d", total_reads, total_writes), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" Cache hits / misses: %0d / %0d  (hit rate %0.2f%%)", hit_cnt, miss_cnt, hit_rate), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" Dirty evictions    : %0d", evict_cnt), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" Way utilisation    :%s", way_str), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" Set reach          : %0.2f%% (%0d/%0d)", set_pct, covered_sets, SETS), UVM_NONE)
        if (reset_cnt > 0)
            `uvm_info(get_type_name(), $sformatf(" Resets / poisoned  : %0d / %0d line(s), %0d check(s) skipped",
                                                 reset_cnt, poisoned.size(), skipped_cnt), UVM_NONE)
        `uvm_info(get_type_name(), "========================================", UVM_NONE)
    endfunction

endclass
