`timescale 1ns/1ps

import uvm_pkg::*;

interface l1_cache_if
    import l1_cache_pkg::*;
(input logic clk);

    // Reset is owned by the interface (and driven by the reset agent) rather
    // than by an initial block in tb_top, so a test can re-assert it in the
    // middle of traffic.  It starts asserted so nothing sees X at time 0.
    logic rst_n = 1'b0;

    // ---- CPU request -------------------------------------------------------
    logic        cpu_req_valid;
    logic        cpu_req_rw;
    logic [31:0] cpu_req_addr;
    be_t         cpu_req_be;
    logic [31:0] cpu_req_wdata;
    logic        cpu_req_ready;

    // ---- CPU response ------------------------------------------------------
    logic        cpu_rsp_valid;
    logic [31:0] cpu_rsp_rdata;

    // ---- Memory request ----------------------------------------------------
    logic        mem_req_valid;
    logic        mem_req_ready;
    logic        mem_req_rw;
    logic [31:0] mem_req_addr;
    logic [7:0]  mem_req_len;

    // ---- Memory write-data channel (write-back) ----------------------------
    logic        mem_wr_valid;
    logic        mem_wr_ready;
    logic [31:0] mem_wr_data;
    logic        mem_wr_last;

    // ---- Memory read-data channel (line fill) ------------------------------
    logic        mem_rd_valid;
    logic [31:0] mem_rd_data;
    logic        mem_rd_last;

    // ========================================================================
    clocking cb_cpu @(posedge clk);
        default input #1step output #1ns;
        output cpu_req_valid, cpu_req_rw, cpu_req_addr, cpu_req_be, cpu_req_wdata;
        input  cpu_req_ready, cpu_rsp_valid, cpu_rsp_rdata;
    endclocking

    clocking cb_cpu_mon @(posedge clk);
        default input #1step;
        input cpu_req_valid, cpu_req_rw, cpu_req_addr, cpu_req_be, cpu_req_wdata,
              cpu_req_ready, cpu_rsp_valid, cpu_rsp_rdata;
    endclocking

    clocking cb_mem @(posedge clk);
        default input #1step output #1ns;
        output mem_req_ready, mem_wr_ready, mem_rd_valid, mem_rd_data, mem_rd_last;
        input  mem_req_valid, mem_req_rw, mem_req_addr, mem_req_len,
               mem_wr_valid, mem_wr_data, mem_wr_last;
    endclocking

    clocking cb_mem_mon @(posedge clk);
        default input #1step;
        input mem_req_valid, mem_req_ready, mem_req_rw, mem_req_addr, mem_req_len,
              mem_wr_valid, mem_wr_ready, mem_wr_data, mem_wr_last,
              mem_rd_valid, mem_rd_data, mem_rd_last;
    endclocking

    // ========================================================================
    // SystemVerilog Assertions
    // ========================================================================

    // ---- CPU side ----------------------------------------------------------

    // 1. VALID must be deasserted while reset is held.
    //    Reset is asynchronous, so the driver only sees it at the next clock
    //    edge; the requirement is checked from the second reset cycle onward.
    property p_reset_valid;
        @(posedge clk) (!rst_n)[*2] |-> (cpu_req_valid === 1'b0);
    endproperty
    assert_reset_valid: assert property(p_reset_valid)
        else uvm_report_error("SVA", "cpu_req_valid is not 0 during reset");

    // 2. VALID must be held until the request is accepted.
    property p_valid_hold;
        @(posedge clk) disable iff (!rst_n)
        (cpu_req_valid && !cpu_req_ready) |=> cpu_req_valid;
    endproperty
    assert_valid_hold: assert property(p_valid_hold)
        else uvm_report_error("SVA", "CPU dropped VALID before the request was accepted");

    // 3. Payload must be stable while the request is waiting.
    property p_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        (cpu_req_valid && !cpu_req_ready) |=>
            $stable(cpu_req_addr) && $stable(cpu_req_wdata) &&
            $stable(cpu_req_rw)   && $stable(cpu_req_be);
    endproperty
    assert_payload_stable: assert property(p_payload_stable)
        else uvm_report_error("SVA", "CPU changed ADDR/WDATA/RW/BE while the request was stalled");

    // 4. No X/Z on a valid request.
    property p_no_xz_payload;
        @(posedge clk) disable iff (!rst_n)
        cpu_req_valid |-> !$isunknown({cpu_req_addr, cpu_req_rw, cpu_req_be});
    endproperty
    assert_no_xz_payload: assert property(p_no_xz_payload)
        else uvm_report_error("SVA", "request payload contains X or Z");

    // 5. A write must have at least one byte lane enabled.
    property p_write_be_nonzero;
        @(posedge clk) disable iff (!rst_n)
        (cpu_req_valid && cpu_req_rw) |-> (cpu_req_be != '0);
    endproperty
    assert_write_be_nonzero: assert property(p_write_be_nonzero)
        else uvm_report_error("SVA", "write request with all byte enables clear");

    // 6. A read response must never carry X/Z.
    property p_rsp_no_xz;
        @(posedge clk) disable iff (!rst_n)
        cpu_rsp_valid |-> !$isunknown(cpu_rsp_rdata);
    endproperty
    assert_rsp_no_xz: assert property(p_rsp_no_xz)
        else uvm_report_error("SVA", "cpu_rsp_rdata contains X or Z while cpu_rsp_valid");

    // 7. No response during reset.
    property p_no_rsp_in_reset;
        @(posedge clk) (!rst_n) |-> (cpu_rsp_valid === 1'b0);
    endproperty
    assert_no_rsp_in_reset: assert property(p_no_rsp_in_reset)
        else uvm_report_error("SVA", "cpu_rsp_valid asserted during reset");

    // ---- Memory request channel -------------------------------------------

    // 8. A memory request holds VALID + payload until accepted.
    property p_mem_req_stable;
        @(posedge clk) disable iff (!rst_n)
        (mem_req_valid && !mem_req_ready) |=>
            mem_req_valid && $stable(mem_req_addr) && $stable(mem_req_rw) &&
            $stable(mem_req_len);
    endproperty
    assert_mem_req_stable: assert property(p_mem_req_stable)
        else uvm_report_error("SVA", "memory request changed/dropped before it was accepted");

    // 9. Memory request payload is never X/Z.
    property p_mem_req_no_xz;
        @(posedge clk) disable iff (!rst_n)
        mem_req_valid |-> !$isunknown({mem_req_addr, mem_req_rw, mem_req_len});
    endproperty
    assert_mem_req_no_xz: assert property(p_mem_req_no_xz)
        else uvm_report_error("SVA", "memory request payload contains X or Z");

    // 10. Requests are line aligned.
    property p_mem_req_aligned;
        @(posedge clk) disable iff (!rst_n)
        mem_req_valid |-> (mem_req_addr[OFFSET_BITS-1:0] == '0);
    endproperty
    assert_mem_req_aligned: assert property(p_mem_req_aligned)
        else uvm_report_error("SVA", "memory request address is not line aligned");

    // ---- Memory write-data channel ----------------------------------------

    // 11. Write data holds until accepted.
    property p_mem_wr_stable;
        @(posedge clk) disable iff (!rst_n)
        (mem_wr_valid && !mem_wr_ready) |=>
            mem_wr_valid && $stable(mem_wr_data) && $stable(mem_wr_last);
    endproperty
    assert_mem_wr_stable: assert property(p_mem_wr_stable)
        else uvm_report_error("SVA", "write-back beat changed/dropped before it was accepted");

    // 12. Write-back data is never X/Z.
    property p_mem_wr_no_xz;
        @(posedge clk) disable iff (!rst_n)
        mem_wr_valid |-> !$isunknown({mem_wr_data, mem_wr_last});
    endproperty
    assert_mem_wr_no_xz: assert property(p_mem_wr_no_xz)
        else uvm_report_error("SVA", "write-back data contains X or Z");

    // 13. Fill data is never X/Z.
    property p_mem_rd_no_xz;
        @(posedge clk) disable iff (!rst_n)
        mem_rd_valid |-> !$isunknown({mem_rd_data, mem_rd_last});
    endproperty
    assert_mem_rd_no_xz: assert property(p_mem_rd_no_xz)
        else uvm_report_error("SVA", "fill data contains X or Z");

    // ---- Burst beat accounting --------------------------------------------
    // Every burst must deliver exactly mem_req_len+1 beats and raise LAST on
    // the final one - no short bursts, no runaway bursts.
    int unsigned wr_beats, rd_beats, exp_beats;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_beats  <= 0;
            rd_beats  <= 0;
            exp_beats <= 0;
        end else begin
            if (mem_req_valid && mem_req_ready) exp_beats <= mem_req_len + 1;
            if (mem_wr_valid  && mem_wr_ready)  wr_beats  <= mem_wr_last ? 0 : wr_beats + 1;
            if (mem_rd_valid)                   rd_beats  <= mem_rd_last ? 0 : rd_beats + 1;
        end
    end

    property p_wr_burst_len;
        @(posedge clk) disable iff (!rst_n)
        (mem_wr_valid && mem_wr_ready && mem_wr_last) |-> (wr_beats == exp_beats - 1);
    endproperty
    assert_wr_burst_len: assert property(p_wr_burst_len)
        else uvm_report_error("SVA", "write-back burst delivered the wrong number of beats");

    property p_rd_burst_len;
        @(posedge clk) disable iff (!rst_n)
        (mem_rd_valid && mem_rd_last) |-> (rd_beats == exp_beats - 1);
    endproperty
    assert_rd_burst_len: assert property(p_rd_burst_len)
        else uvm_report_error("SVA", "fill burst delivered the wrong number of beats");

    // ---- Cover -------------------------------------------------------------
    cover_read_b2b:  cover property (
        @(posedge clk) disable iff (!rst_n) cpu_rsp_valid ##1 cpu_rsp_valid);
    cover_stall:     cover property (
        @(posedge clk) disable iff (!rst_n) cpu_req_valid && !cpu_req_ready);
    cover_eviction:  cover property (
        @(posedge clk) disable iff (!rst_n) mem_req_valid && mem_req_rw && mem_req_ready);
    cover_partial_be: cover property (
        @(posedge clk) disable iff (!rst_n)
        cpu_req_valid && cpu_req_rw && cpu_req_ready && (cpu_req_be != '1));

    // ========================================================================
    // Reset helper - used by the reset agent
    // ========================================================================
    task automatic assert_reset(int unsigned cycles);
        rst_n <= 1'b0;
        repeat (cycles) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

endinterface
