`timescale 1ns/1ps
import l1_cache_pkg::*;

//   S1 : CPU presents a request. Its set index goes to all four tag arrays and
//        all four data arrays in parallel.

//   S2 : tags/data come back from the (registered) array read ports, the four
//        ways are compared, and hit/miss is resolved.

module l1_cache_core (
    input  logic        clk,
    input  logic        rst_n,

    // ---- CPU request (S1) --------------------------------------------------
    input  logic        cpu_req_valid,
    input  logic        cpu_req_rw,
    input  logic [31:0] cpu_req_addr,
    input  be_t         cpu_req_be,
    input  logic [31:0] cpu_req_wdata,
    output logic        pipeline_stall,

    // ---- CPU response (S2) -------------------------------------------------
    output logic        cpu_rsp_valid,
    output logic [31:0] cpu_rsp_rdata,

    // ---- Tag arrays (one per way) -----------------------------------------
    output logic [WAYS-1:0]                tag_we,
    output set_t                           tag_waddr,
    output tag_t                           tag_wdata,
    output set_t                           tag_raddr,
    input  logic [WAYS-1:0][TAG_BITS-1:0]  tag_rdata,

    // ---- Data arrays (one per way) ----------------------------------------
    output logic [WAYS-1:0]                data_we,
    output be_t                            data_wbe,
    output data_addr_t                     data_waddr,
    output logic [31:0]                    data_wdata,
    output data_addr_t                     data_raddr,
    input  logic [WAYS-1:0][31:0]          data_rdata,

    // ---- Main memory, burst -----------------------------------------------
    output logic        mem_req_valid,
    input  logic        mem_req_ready,
    output logic        mem_req_rw,          // 1 = write-back, 0 = line fetch
    output logic [31:0] mem_req_addr,        // line aligned
    output logic [7:0]  mem_req_len,         // beats - 1

    output logic        mem_wr_valid,        // write-back data channel
    input  logic        mem_wr_ready,
    output logic [31:0] mem_wr_data,
    output logic        mem_wr_last,

    input  logic        mem_rd_valid,        // fill data channel (always accepted)
    input  logic [31:0] mem_rd_data,
    input  logic        mem_rd_last
);

    // S1 -> S2 pipeline register

    logic        s2_valid;
    logic        s2_rw;
    logic [31:0] s2_addr;
    be_t         s2_be;
    logic [31:0] s2_wdata;

    set_t  s1_set,  s2_set;
    word_t s1_word, s2_word;
    tag_t  s2_tag;

    assign s1_set  = get_set(cpu_req_addr);
    assign s1_word = get_word(cpu_req_addr);
    assign s2_set  = get_set(s2_addr);
    assign s2_word = get_word(s2_addr);
    assign s2_tag  = get_tag(s2_addr);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
            s2_rw    <= 1'b0;
            s2_addr  <= 32'b0;
            s2_be    <= '0;
            s2_wdata <= 32'b0;
        end else if (!pipeline_stall) begin
            s2_valid <= cpu_req_valid;
            s2_rw    <= cpu_req_rw;
            s2_addr  <= cpu_req_addr;
            s2_be    <= cpu_req_be;
            s2_wdata <= cpu_req_wdata;
        end
    end

   
    // Line state - valid/dirty/PLRU live in flops
    logic [WAYS-1:0] valid_bits [SETS];
    logic [WAYS-1:0] dirty_bits [SETS];
    plru_t           plru_bits  [SETS];

    logic [WAYS-1:0] set_valid, set_dirty;
    assign set_valid = valid_bits[s2_set];
    assign set_dirty = dirty_bits[s2_set];

  
    // FSM state and miss bookkeeping
    cache_state_t state, next_state;

    way_t        victim_way;      // way being replaced for the current miss
    tag_t        victim_tag;      // its old tag, needed for the write-back address
    logic [2:0]  wb_cnt;          // victim read-out counter (0..4)
    word_t       wb_ptr;          // write-back streaming pointer
    logic        wb_req_sent;
    word_t       fill_beat;
    logic [31:0] fill_data;       // the word this request actually asked for
    logic [31:0] wb_buf [WORDS_PER_LINE];   // victim line staged for write-back



    // Array read addresses
    always_comb begin
        if (!pipeline_stall && cpu_req_valid) begin
            tag_raddr  = s1_set;
            data_raddr = make_data_addr(s1_set, s1_word);
        end
        else if (state == ST_WB_READ) begin
            tag_raddr  = s2_set;
            data_raddr = make_data_addr(s2_set, word_t'(wb_cnt[WORD_BITS-1:0]));
        end
        else begin
            tag_raddr  = s2_set;
            data_raddr = make_data_addr(s2_set, s2_word);
        end
    end

    // Read-during-write forwarding
    logic [WAYS-1:0] prev_tag_we;
    set_t            prev_tag_waddr, prev_tag_raddr;
    tag_t            prev_tag_wdata;

    logic [WAYS-1:0] prev_data_we;
    be_t             prev_data_wbe;
    data_addr_t      prev_data_waddr, prev_data_raddr;
    logic [31:0]     prev_data_wdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_tag_we  <= '0;
            prev_data_we <= '0;
        end else begin
            prev_tag_we     <= tag_we;
            prev_tag_waddr  <= tag_waddr;
            prev_tag_wdata  <= tag_wdata;
            prev_tag_raddr  <= tag_raddr;

            prev_data_we    <= data_we;
            prev_data_wbe   <= data_wbe;
            prev_data_waddr <= data_waddr;
            prev_data_wdata <= data_wdata;
            prev_data_raddr <= data_raddr;
        end
    end

    logic [WAYS-1:0][TAG_BITS-1:0] safe_tag_rdata;
    logic [WAYS-1:0][31:0]         safe_data_rdata;

    always_comb begin
        for (int w = 0; w < WAYS; w++) begin
            // tag
            safe_tag_rdata[w] = (prev_tag_we[w] && (prev_tag_waddr == prev_tag_raddr))
                                ? prev_tag_wdata : tag_rdata[w];

            // data, byte by byte 
            for (int b = 0; b < BE_WIDTH; b++) begin
                safe_data_rdata[w][b*8 +: 8] =
                    (prev_data_we[w] && (prev_data_waddr == prev_data_raddr) && prev_data_wbe[b])
                    ? prev_data_wdata[b*8 +: 8]
                    : data_rdata[w][b*8 +: 8];
            end
        end
    end


    // Hit detection across the four ways
    logic [WAYS-1:0] way_hit;
    logic            cache_hit;
    way_t            hit_way;

    always_comb begin
        for (int w = 0; w < WAYS; w++)
            way_hit[w] = set_valid[w] && (safe_tag_rdata[w] == s2_tag);
    end

    assign cache_hit = s2_valid && (|way_hit);

    always_comb begin
        hit_way = '0;
        for (int w = 0; w < WAYS; w++)
            if (way_hit[w]) hit_way = way_t'(w);
    end


    // Victim selection: fill an invalid way first, otherwise follow the PLRU tree
    way_t victim_sel;
    logic victim_dirty;
    way_t first_invalid;
    logic has_invalid;

    always_comb begin
        first_invalid = '0;
        has_invalid   = 1'b0;
        for (int w = WAYS-1; w >= 0; w--) begin
            if (!set_valid[w]) begin
                first_invalid = way_t'(w);
                has_invalid   = 1'b1;
            end
        end
        victim_sel = has_invalid ? first_invalid : plru_victim(plru_bits[s2_set]);
    end

    assign victim_dirty = set_valid[victim_sel] && set_dirty[victim_sel];

    // CPU response
    assign cpu_rsp_valid = ((state == ST_IDLE)     && s2_valid && cache_hit && !s2_rw)
                        || ((state == ST_COMPLETE) && s2_valid &&              !s2_rw);

    assign cpu_rsp_rdata = (state == ST_COMPLETE) ? fill_data : safe_data_rdata[hit_way];



    //----------------------------------------------------------------
    // Sequential state
    //----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            victim_way  <= '0;
            victim_tag  <= '0;
            wb_cnt      <= '0;
            wb_ptr      <= '0;
            wb_req_sent <= 1'b0;
            fill_beat   <= '0;
            fill_data   <= 32'b0;
            for (int s = 0; s < SETS; s++) begin
                valid_bits[s] <= '0;
                dirty_bits[s] <= '0;
                plru_bits [s] <= '0;
            end
        end
        else begin
            state <= next_state;

            unique case (state)

                ST_IDLE: begin
                    if (s2_valid && cache_hit) begin
                        plru_bits[s2_set] <= plru_update(plru_bits[s2_set], hit_way);
                        if (s2_rw) dirty_bits[s2_set][hit_way] <= 1'b1;
                    end
                    else if (s2_valid && !cache_hit) begin
                        // Latch the victim for the whole miss sequence.
                        victim_way  <= victim_sel;
                        victim_tag  <= safe_tag_rdata[victim_sel];
                        wb_cnt      <= '0;
                        wb_ptr      <= '0;
                        wb_req_sent <= 1'b0;
                        fill_beat   <= '0;
                    end
                end

                ST_WB_READ: begin
                    // Address for word N is presented on cycle N; its data
                    // arrives on cycle N+1, so capture one cycle behind.
                    if (wb_cnt > 0) wb_buf[wb_cnt-1] <= safe_data_rdata[victim_way];
                    wb_cnt <= wb_cnt + 3'd1;
                end

                ST_WB_SEND: begin
                    if (!wb_req_sent) begin
                        if (mem_req_ready) wb_req_sent <= 1'b1;
                    end
                    else if (mem_wr_ready) begin
                        wb_ptr <= wb_ptr + word_t'(1);
                    end
                end

                ST_FILL_RCV: begin
                    if (mem_rd_valid) begin
                        if (fill_beat == s2_word) fill_data <= mem_rd_data;
                        fill_beat <= fill_beat + word_t'(1);
                    end
                end

                ST_COMPLETE: begin
                    valid_bits[s2_set][victim_way] <= 1'b1;
                    dirty_bits[s2_set][victim_way] <= s2_rw;
                    plru_bits [s2_set]             <= plru_update(plru_bits[s2_set], victim_way);
                end

                default: ;
            endcase
        end
    end


    //----------------------------------------------------------------
    // Next state and outputs
    //----------------------------------------------------------------
    always_comb begin
        next_state     = state;
        pipeline_stall = 1'b0;

        mem_req_valid  = 1'b0;
        mem_req_rw     = 1'b0;
        mem_req_addr   = 32'b0;
        mem_req_len    = WORDS_PER_LINE - 1;

        mem_wr_valid   = 1'b0;
        mem_wr_data    = 32'b0;
        mem_wr_last    = 1'b0;

        tag_we         = '0;
        tag_waddr      = s2_set;
        tag_wdata      = s2_tag;

        data_we        = '0;
        data_wbe       = '0;
        data_waddr     = make_data_addr(s2_set, s2_word);
        data_wdata     = s2_wdata;

        unique case (state)

            // ---- steady state ----------------------------------------------
            ST_IDLE: begin
                if (s2_valid) begin
                    if (cache_hit) begin
                        if (s2_rw) begin
                            // Write hit: update the addressed bytes in place.
                            data_we[hit_way] = 1'b1;
                            data_wbe         = s2_be;
                        end
                    end
                    else begin
                        pipeline_stall = 1'b1;
                        next_state     = victim_dirty ? ST_WB_READ : ST_FILL_REQ;
                    end
                end
            end

            // ---- copy the dirty victim out of the data array ---------------
            ST_WB_READ: begin
                pipeline_stall = 1'b1;
                if (wb_cnt == 3'd4) next_state = ST_WB_SEND;
            end

            // ---- stream the victim to main memory --------------------------
            ST_WB_SEND: begin
                pipeline_stall = 1'b1;
                if (!wb_req_sent) begin
                    mem_req_valid = 1'b1;
                    mem_req_rw    = 1'b1;
                    mem_req_addr  = make_line_addr(victim_tag, s2_set);
                end
                else begin
                    mem_wr_valid = 1'b1;
                    mem_wr_data  = wb_buf[wb_ptr];
                    mem_wr_last  = (wb_ptr == word_t'(WORDS_PER_LINE-1));
                    if (mem_wr_ready && mem_wr_last) next_state = ST_FILL_REQ;
                end
            end

            // ---- request the new line --------------------------------------
            ST_FILL_REQ: begin
                pipeline_stall = 1'b1;
                mem_req_valid  = 1'b1;
                mem_req_rw     = 1'b0;
                mem_req_addr   = make_line_addr(s2_tag, s2_set);
                if (mem_req_ready) next_state = ST_FILL_RCV;
            end

            // ---- receive the burst -----------------------------------------
            ST_FILL_RCV: begin
                pipeline_stall = 1'b1;
                if (mem_rd_valid) begin
                    data_we[victim_way] = 1'b1;
                    data_wbe            = '1;
                    data_waddr          = make_data_addr(s2_set, fill_beat);
                    data_wdata          = mem_rd_data;
                    if (mem_rd_last) next_state = ST_COMPLETE;
                end
            end

            // ---- one cycle to finalise and answer --------------------------
            ST_COMPLETE: begin
                pipeline_stall  = 1'b0;
                tag_we[victim_way] = 1'b1;
                if (s2_rw) begin
                    data_we[victim_way] = 1'b1;
                    data_wbe            = s2_be;
                end
                next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    //----------------------------------------------------------------
    // Debug trace (simulation only)
    //----------------------------------------------------------------
`ifdef CACHE_DEBUG
    always_ff @(posedge clk) begin
        if (state == ST_IDLE && s2_valid && cache_hit)
            $display("[CACHE] %s hit  addr=%h way=%0d", s2_rw ? "WR" : "RD", s2_addr, hit_way);
        if (state == ST_IDLE && s2_valid && !cache_hit)
            $display("[CACHE] MISS    addr=%h victim_way=%0d dirty=%0b", s2_addr, victim_sel, victim_dirty);
        if (state == ST_WB_SEND && mem_wr_valid && mem_wr_ready)
            $display("[CACHE] EVICT   beat=%0d data=%h", wb_ptr, mem_wr_data);
        if (state == ST_FILL_RCV && mem_rd_valid)
            $display("[CACHE] FILL    beat=%0d data=%h", fill_beat, mem_rd_data);
    end
`endif

endmodule
