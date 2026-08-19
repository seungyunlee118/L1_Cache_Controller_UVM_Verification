`timescale 1ns/1ps

class l1_cache_mem_item extends uvm_sequence_item;

    //------------------------------------------
    // Observed transfer
    //------------------------------------------
    bit        req_rw;          // 1 = write-back, 0 = line fetch
    bit [31:0] req_addr;        // line aligned
    bit [7:0]  req_len;         // beats - 1
    bit [31:0] beats [];        // write-back data, or fill data returned

    //------------------------------------------
    // Randomised response timing
    //------------------------------------------
    rand int unsigned latency;      // cycles from accept to the first beat
    rand int unsigned ready_stall;  // cycles READY is withheld on the request
    rand int unsigned beat_gap;     // idle cycles inserted between beats

    //------------------------------------------
    // Bounds, driven from l1_cache_config by the responder sequence
    //------------------------------------------
    int unsigned min_latency     = 1;
    int unsigned max_latency     = 8;
    int unsigned max_ready_stall = 3;
    int unsigned ready_stall_pct = 20;
    int unsigned max_beat_gap    = 2;
    int unsigned beat_gap_pct    = 30;

    `uvm_object_utils_begin(l1_cache_mem_item)
        `uvm_field_int(req_rw,      UVM_ALL_ON)
        `uvm_field_int(req_addr,    UVM_ALL_ON)
        `uvm_field_int(req_len,     UVM_ALL_ON | UVM_DEC)
        `uvm_field_array_int(beats, UVM_ALL_ON)
        `uvm_field_int(latency,     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(ready_stall, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(beat_gap,    UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    constraint c_latency {
        latency inside {[min_latency : max_latency]};
    }

    constraint c_ready_stall {
        ready_stall dist {
            0                     := 100 - ready_stall_pct,
            [1 : max_ready_stall] :/ ready_stall_pct
        };
    }

    constraint c_beat_gap {
        beat_gap dist {
            0                  := 100 - beat_gap_pct,
            [1 : max_beat_gap] :/ beat_gap_pct
        };
    }

    function new(string name = "l1_cache_mem_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("%s addr=0x%08x len=%0d beats=%p",
                         req_rw ? "EVICT" : "FETCH", req_addr, req_len, beats);
    endfunction

endclass
