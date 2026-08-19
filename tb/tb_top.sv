`timescale 1ns/1ps

import uvm_pkg::*;        // UVM base library
`include "uvm_macros.svh"

import l1_cache_pkg::*;   // DUT parameters / address helpers, shared with the TB

`include "tb_classes.svh"

module tb_top;

    //=========================================================
    // 1. Clock
    //=========================================================
    logic clk;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    //=========================================================
    // 2. Interface
    //=========================================================
    l1_cache_if vif(clk);

    //=========================================================
    // 3. DUT
    //=========================================================
    l1_cache_top u_dut (
        .clk             (clk),
        .rst_n           (vif.rst_n),

        .cpu_req_valid   (vif.cpu_req_valid),
        .cpu_req_rw      (vif.cpu_req_rw),
        .cpu_req_addr    (vif.cpu_req_addr),
        .cpu_req_be      (vif.cpu_req_be),
        .cpu_req_wdata   (vif.cpu_req_wdata),
        .cpu_req_ready   (vif.cpu_req_ready),
        .cpu_rsp_valid   (vif.cpu_rsp_valid),
        .cpu_rsp_rdata   (vif.cpu_rsp_rdata),

        .mem_req_valid   (vif.mem_req_valid),
        .mem_req_ready   (vif.mem_req_ready),
        .mem_req_rw      (vif.mem_req_rw),
        .mem_req_addr    (vif.mem_req_addr),
        .mem_req_len     (vif.mem_req_len),

        .mem_wr_valid    (vif.mem_wr_valid),
        .mem_wr_ready    (vif.mem_wr_ready),
        .mem_wr_data     (vif.mem_wr_data),
        .mem_wr_last     (vif.mem_wr_last),

        .mem_rd_valid    (vif.mem_rd_valid),
        .mem_rd_data     (vif.mem_rd_data),
        .mem_rd_last     (vif.mem_rd_last)
    );

    //=========================================================
    // 4. UVM start
    //=========================================================
    initial begin
        uvm_config_db#(virtual l1_cache_if)::set(null, "*", "vif", vif);

        // Default test; override with +UVM_TESTNAME=<test>
        run_test("l1_cache_random_test");
    end

    //=========================================================
    // 5. Waveform dumping (opt in: xelab -d DUMP_VCD)
    //=========================================================
`ifdef DUMP_VCD
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end
`endif

    //=========================================================
    // 6. White-box FSM coverage
    //=========================================================
    bind l1_cache_core l1_cache_fsm_cov u_fsm_cov (
        .clk           (clk),
        .rst_n         (rst_n),
        .state         (state),
        .s2_valid      (s2_valid),
        .cache_hit     (cache_hit),
        .pipeline_stall(pipeline_stall),
        .hit_way       (hit_way),
        .victim_way    (victim_way),
        .fill_beat     (fill_beat),
        .mem_req_valid (mem_req_valid),
        .mem_req_rw    (mem_req_rw),
        .mem_req_ready (mem_req_ready),
        .mem_wr_valid  (mem_wr_valid),
        .mem_wr_ready  (mem_wr_ready),
        .mem_rd_valid  (mem_rd_valid)
    );

endmodule
