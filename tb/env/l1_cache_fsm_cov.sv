`timescale 1ns/1ps

module l1_cache_fsm_cov
    import l1_cache_pkg::*;
(
    input logic         clk,
    input logic         rst_n,
    input cache_state_t state,
    input logic         s2_valid,
    input logic         cache_hit,
    input logic         pipeline_stall,
    input way_t         hit_way,
    input way_t         victim_way,
    input word_t        fill_beat,
    input logic         mem_req_valid,
    input logic         mem_req_rw,
    input logic         mem_req_ready,
    input logic         mem_wr_valid,
    input logic         mem_wr_ready,
    input logic         mem_rd_valid
);

    // Length of the current stall, bucketed. Exposes whether long memory
    // latencies were actually exercised.
    int unsigned stall_len;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)              stall_len <= 0;
        else if (pipeline_stall) stall_len <= stall_len + 1;
        else                     stall_len <= 0;
    end

    wire req_backpressure = mem_req_valid && !mem_req_ready;
    wire wr_backpressure  = mem_wr_valid  && !mem_wr_ready;

    covergroup cg_fsm @(posedge clk iff rst_n);
        option.per_instance = 1;
        option.name         = "cache_fsm";

        cp_state: coverpoint state {
            bins idle     = {ST_IDLE};
            bins wb_read  = {ST_WB_READ};
            bins wb_send  = {ST_WB_SEND};
            bins fill_req = {ST_FILL_REQ};
            bins fill_rcv = {ST_FILL_RCV};
            bins complete = {ST_COMPLETE};

            // Every legal transition must be seen.
            bins t_idle_wb    = (ST_IDLE      => ST_WB_READ);
            bins t_idle_fill  = (ST_IDLE      => ST_FILL_REQ);
            bins t_wbrd_wbsnd = (ST_WB_READ   => ST_WB_SEND);
            bins t_wbsnd_fill = (ST_WB_SEND   => ST_FILL_REQ);
            bins t_freq_frcv  = (ST_FILL_REQ  => ST_FILL_RCV);
            bins t_frcv_comp  = (ST_FILL_RCV  => ST_COMPLETE);
            bins t_comp_idle  = (ST_COMPLETE  => ST_IDLE);

            // ...and these must never happen.
            illegal_bins t_bad = (ST_IDLE      => ST_WB_SEND),
                                 (ST_IDLE      => ST_FILL_RCV),
                                 (ST_IDLE      => ST_COMPLETE),
                                 (ST_WB_READ   => ST_IDLE),
                                 (ST_WB_READ   => ST_FILL_REQ),
                                 (ST_WB_SEND   => ST_IDLE),
                                 (ST_FILL_REQ  => ST_IDLE),
                                 (ST_FILL_RCV  => ST_IDLE),
                                 (ST_COMPLETE  => ST_WB_READ),
                                 (ST_COMPLETE  => ST_WB_SEND),
                                 (ST_COMPLETE  => ST_FILL_REQ),
                                 (ST_COMPLETE  => ST_FILL_RCV);
        }

        cp_stall_len: coverpoint stall_len iff (pipeline_stall) {
            bins len_short = {[1:8]};
            bins len_mid   = {[9:20]};
            bins len_long  = {[21:60]};
            bins len_huge  = {[61:$]};
        }

        cp_req_bp: coverpoint req_backpressure {
            bins accepted = {1'b0};
            bins stalled  = {1'b1};
        }

        cp_wr_bp: coverpoint wr_backpressure {
            bins accepted = {1'b0};
            bins stalled  = {1'b1};
        }

        cp_mem_rw: coverpoint mem_req_rw iff (mem_req_valid) {
            bins fetch = {1'b0};
            bins evict = {1'b1};
        }

        // Every beat position of a fill burst must be exercised.
        cp_fill_beat: coverpoint fill_beat iff (state == ST_FILL_RCV && mem_rd_valid) {
            bins beat[4] = {[0:3]};
        }

        // The replacement policy must be able to pick every way...
        cp_victim_way: coverpoint victim_way iff (state == ST_COMPLETE) {
            bins way[4] = {[0:3]};
        }

        // ...and every way must be able to hit.
        cp_hit_way: coverpoint hit_way iff (state == ST_IDLE && s2_valid && cache_hit) {
            bins way[4] = {[0:3]};
        }

        // Backpressure must be seen on both fetches and evictions.
        x_mem_bp: cross cp_mem_rw, cp_req_bp;

        cp_hit: coverpoint cache_hit iff (s2_valid && state == ST_IDLE) {
            bins miss = {1'b0};
            bins hit  = {1'b1};
        }
    endgroup

    cg_fsm cov_inst = new();

    final begin
        $display("[FSM COV] cache_fsm covergroup: %0.2f%%", cov_inst.get_coverage());
    end

endmodule
