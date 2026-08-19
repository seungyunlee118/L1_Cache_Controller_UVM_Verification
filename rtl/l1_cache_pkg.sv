`timescale 1ns/1ps

package l1_cache_pkg;

    // ------------------------------------------------------------------------
    // Cache geometry
    //   4-way set associative, write-back / write-allocate, tree-PLRU
    //   4 words (16 B) per line x 64 sets x 4 ways = 4 KB
    // ------------------------------------------------------------------------
    localparam int WAY_BITS       = 2;                     // $clog2(WAYS)
    localparam int SETS           = 64;
    localparam int SET_BITS       = 6;                     // $clog2(SETS)
    localparam int WORDS_PER_LINE = 4;
    localparam int WORD_BITS      = 2;                     // $clog2(WORDS_PER_LINE)
    localparam int BYTE_BITS      = 2;                     // byte within a word
    localparam int OFFSET_BITS    = WORD_BITS + BYTE_BITS; // 4 -> 16 B line
    localparam int TAG_BITS       = ADDR_WIDTH - SET_BITS - OFFSET_BITS;  // 22

    // Data array per way is addressed by {set, word}
    localparam int DATA_ADDR_BITS = SET_BITS + WORD_BITS;  // 8 -> 256 words/way

    typedef logic [SET_BITS-1:0]       set_t;
    typedef logic [TAG_BITS-1:0]       tag_t;
    typedef logic [WAY_BITS-1:0]       way_t;
    typedef logic [WORD_BITS-1:0]      word_t;
    typedef logic [DATA_ADDR_BITS-1:0] data_addr_t;
    typedef logic [BE_WIDTH-1:0]       be_t;

    // ------------------------------------------------------------------------
    // Controller FSM
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE     = 3'd0,
        ST_WB_READ  = 3'd1,   // copy the dirty victim out of the data array
        ST_WB_SEND  = 3'd2,   // stream the victim to main memory
        ST_FILL_REQ = 3'd3,   // issue the line fetch
        ST_FILL_RCV = 3'd4,   // receive the burst, write it into the array
        ST_COMPLETE = 3'd5    // update tag/valid/dirty/PLRU, answer the CPU
    } cache_state_t;

    // ------------------------------------------------------------------------
    // Tag array entry. 
    // ------------------------------------------------------------------------
    typedef struct packed {
        tag_t tag;
    } tag_data_t;

    // ------------------------------------------------------------------------
    // Address helpers - single source of truth for the address split.
    // ------------------------------------------------------------------------
    function automatic set_t get_set(input logic [ADDR_WIDTH-1:0] addr_in);
        return addr_in[OFFSET_BITS +: SET_BITS];
    endfunction

    function automatic tag_t get_tag(input logic [ADDR_WIDTH-1:0] addr_in);
        return addr_in[ADDR_WIDTH-1 -: TAG_BITS];
    endfunction

    function automatic word_t get_word(input logic [ADDR_WIDTH-1:0] addr_in);
        return addr_in[BYTE_BITS +: WORD_BITS];
    endfunction

    // Base (word 0) address of the line containing addr_in.
    function automatic logic [ADDR_WIDTH-1:0] get_line_addr(input logic [ADDR_WIDTH-1:0] addr_in);
        return {addr_in[ADDR_WIDTH-1 : OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    endfunction

    function automatic logic [ADDR_WIDTH-1:0] make_line_addr(input tag_t tag_in, input set_t set_in);
        return {tag_in, set_in, {OFFSET_BITS{1'b0}}};
    endfunction

    function automatic data_addr_t make_data_addr(input set_t set_in, input word_t word_in);
        return {set_in, word_in};
    endfunction

    // ------------------------------------------------------------------------
    // Tree PLRU for 4 ways - 3 state bits per set.
    // ------------------------------------------------------------------------
    localparam int PLRU_BITS = 3;
    typedef logic [PLRU_BITS-1:0] plru_t;

    function automatic way_t plru_victim(input plru_t plru_in);
        return plru_in[0] ? (plru_in[2] ? way_t'(3) : way_t'(2))
                          : (plru_in[1] ? way_t'(1) : way_t'(0));
    endfunction

    // Point the tree away from the way that was just touched.
    function automatic plru_t plru_update(input plru_t plru_in, input way_t way_in);
        plru_t nxt = plru_in;
        nxt[0] = ~way_in[1];
        if (way_in[1] == 1'b0) nxt[1] = ~way_in[0];
        else                   nxt[2] = ~way_in[0];
        return nxt;
    endfunction

endpackage
