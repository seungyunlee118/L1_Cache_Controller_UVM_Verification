`timescale 1ns/1ps

// CPU -> cache transaction
class l1_cache_item extends uvm_sequence_item;

    //------------------------------------------
    // Stimulus
    //------------------------------------------
    rand bit        rw;      // 0: Read, 1: Write
    rand bit [31:0] addr;
    rand bit [3:0]  be;      // byte enables (writes only)
    rand bit [31:0] wdata;

    //------------------------------------------
    // Response
    //------------------------------------------
    bit [31:0]      rdata;

    //------------------------------------------
    // Reference-model 
    //------------------------------------------
    bit             hit;
    bit             did_evict;
    bit [1:0]       way;           // way hit, or way replaced on a miss
    bit [1:0]       word_off;      // word within the line

    typedef enum bit [1:0] {
        VICTIM_INVALID = 2'd0,   // cold miss - way was never used
        VICTIM_CLEAN   = 2'd1,   // capacity/conflict miss, no write-back
        VICTIM_DIRTY   = 2'd2,   // conflict miss, forces a write-back
        VICTIM_NONE    = 2'd3    // hit - nothing replaced
    } victim_e;
    victim_e        victim_state;

    `uvm_object_utils_begin(l1_cache_item)
        `uvm_field_int(rw,        UVM_ALL_ON)
        `uvm_field_int(addr,      UVM_ALL_ON)
        `uvm_field_int(be,        UVM_ALL_ON)
        `uvm_field_int(wdata,     UVM_ALL_ON)
        `uvm_field_int(rdata,     UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(hit,       UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(did_evict, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(way,       UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_object_utils_end

    //------------------------------------------
    // Constraints
    //------------------------------------------
    // The cache addresses words; byte selection is done with `be`.
    constraint c_addr_align {
        addr[1:0] == 2'b00;
    }

    // A write must enable at least one lane. Full-word writes dominate, but
    // partial writes appear often enough to exercise the byte-enable path.
    constraint c_be {
        if (rw) {
            be != 4'b0000;
            soft be dist { 4'b1111 := 60, [4'b0001:4'b1110] :/ 40 };
        } else {
            be == 4'b1111;      // reads ignore be; keep it defined
        }
    }

    // Default 50/50 read/write - sequences override with inline constraints.
    constraint c_rw_dist {
        soft rw dist {1'b0 := 50, 1'b1 := 50};
    }

    function new(string name = "l1_cache_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("%s addr=0x%08x be=%4b wdata=0x%08x rdata=0x%08x hit=%0b way=%0d evict=%0b",
                         rw ? "WR" : "RD", addr, be, wdata, rdata, hit, way, did_evict);
    endfunction

endclass
