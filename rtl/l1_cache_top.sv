`timescale 1ns/1ps
import l1_cache_pkg::*;

module l1_cache_top (
    input  logic        clk,
    input  logic        rst_n,

    // CPU interface
    input  logic        cpu_req_valid,
    input  logic        cpu_req_rw,
    input  logic [31:0] cpu_req_addr,
    input  be_t         cpu_req_be,
    input  logic [31:0] cpu_req_wdata,
    output logic        cpu_req_ready,
    output logic        cpu_rsp_valid,
    output logic [31:0] cpu_rsp_rdata,

    // Main memory, burst
    output logic        mem_req_valid,
    input  logic        mem_req_ready,
    output logic        mem_req_rw,
    output logic [31:0] mem_req_addr,
    output logic [7:0]  mem_req_len,

    output logic        mem_wr_valid,
    input  logic        mem_wr_ready,
    output logic [31:0] mem_wr_data,
    output logic        mem_wr_last,

    input  logic        mem_rd_valid,
    input  logic [31:0] mem_rd_data,
    input  logic        mem_rd_last
);

    logic pipeline_stall;
    assign cpu_req_ready = ~pipeline_stall;

    // ---- array interconnect ------------------------------------------------
    logic [WAYS-1:0]               tag_we;
    set_t                          tag_waddr, tag_raddr;
    tag_t                          tag_wdata;
    logic [WAYS-1:0][TAG_BITS-1:0] tag_rdata;

    logic [WAYS-1:0]               data_we;
    be_t                           data_wbe;
    data_addr_t                    data_waddr, data_raddr;
    logic [31:0]                   data_wdata;
    logic [WAYS-1:0][31:0]         data_rdata;

    l1_cache_core u_core (
        .clk(clk), .rst_n(rst_n),
        .cpu_req_valid(cpu_req_valid), .cpu_req_rw(cpu_req_rw),
        .cpu_req_addr(cpu_req_addr), .cpu_req_be(cpu_req_be),
        .cpu_req_wdata(cpu_req_wdata), .pipeline_stall(pipeline_stall),
        .cpu_rsp_valid(cpu_rsp_valid), .cpu_rsp_rdata(cpu_rsp_rdata),

        .tag_we(tag_we), .tag_waddr(tag_waddr), .tag_wdata(tag_wdata),
        .tag_raddr(tag_raddr), .tag_rdata(tag_rdata),

        .data_we(data_we), .data_wbe(data_wbe), .data_waddr(data_waddr),
        .data_wdata(data_wdata), .data_raddr(data_raddr), .data_rdata(data_rdata),

        .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
        .mem_req_rw(mem_req_rw), .mem_req_addr(mem_req_addr), .mem_req_len(mem_req_len),
        .mem_wr_valid(mem_wr_valid), .mem_wr_ready(mem_wr_ready),
        .mem_wr_data(mem_wr_data), .mem_wr_last(mem_wr_last),
        .mem_rd_valid(mem_rd_valid), .mem_rd_data(mem_rd_data), .mem_rd_last(mem_rd_last)
    );

    // ---- one tag + one data array per way ----------------------------------
    genvar w;
    generate
        for (w = 0; w < WAYS; w++) begin : g_way
            sram_macro #(
                .DATA_WIDTH(TAG_BITS),
                .ADDR_WIDTH(SET_BITS)
            ) u_tag_ram (
                .clk(clk), .we(tag_we[w]), .waddr(tag_waddr), .wdata(tag_wdata),
                .raddr(tag_raddr), .rdata(tag_rdata[w])
            );

            sram_macro_be #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(DATA_ADDR_BITS),
                .BE_WIDTH  (BE_WIDTH)
            ) u_data_ram (
                .clk(clk), .we(data_we[w]), .wbe(data_wbe), .waddr(data_waddr),
                .wdata(data_wdata), .raddr(data_raddr), .rdata(data_rdata[w])
            );
        end
    endgenerate

endmodule
