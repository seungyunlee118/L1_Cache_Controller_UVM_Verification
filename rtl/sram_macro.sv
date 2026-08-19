`timescale 1ns/1ps

// ============================================================================
// Behavioural SRAM models - 1 write port, 1 read port, SYNCHRONOUS read.
// ============================================================================

// ---- plain SRAM (tag arrays) ----------------------------------------------
module sram_macro #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 8
)(
    input  logic                  clk,
    input  logic                  we,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
);

    logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    always_ff @(posedge clk) begin
        rdata <= mem[raddr];              // sampled before this edge's write
        if (we) mem[waddr] <= wdata;
    end

endmodule


// ---- byte-enabled SRAM (data arrays) --------------------------------------
module sram_macro_be #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 8,
    parameter int BE_WIDTH   = DATA_WIDTH/8
)(
    input  logic                  clk,
    input  logic                  we,
    input  logic [BE_WIDTH-1:0]   wbe,     // per-byte write enable
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
);

    logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    always_ff @(posedge clk) begin
        rdata <= mem[raddr];
        if (we) begin
            for (int b = 0; b < BE_WIDTH; b++)
                if (wbe[b]) mem[waddr][b*8 +: 8] <= wdata[b*8 +: 8];
        end
    end

endmodule
