`timescale 1ns/1ps

class l1_cache_config extends uvm_object;

    // ---- topology ----------------------------------------------------------
    uvm_active_passive_enum cpu_is_active = UVM_ACTIVE;

    // ---- CPU driver --------------------------------------------------------
    // Idle cycles inserted between requests. 0/0 gives true back-to-back
    // traffic (VALID never drops between accepted requests).
    int unsigned min_idle = 0;
    int unsigned max_idle = 2;

    // ---- Main memory responder --------------------------------------------
    int unsigned mem_min_latency     = 1;   // accept -> first fill beat
    int unsigned mem_max_latency     = 8;
    int unsigned mem_ready_stall_pct = 20;  // % of bursts that see request backpressure
    int unsigned mem_max_ready_stall = 3;
    int unsigned mem_beat_gap_pct    = 30;  // % of bursts with gaps between beats
    int unsigned mem_max_beat_gap    = 2;

    // ---- Reset agent -------------------------------------------------------
    int unsigned por_cycles     = 5;    // power-on reset length
    int unsigned num_resets     = 0;    // mid-traffic resets (0 = none)
    int unsigned reset_min_gap  = 200;  // cycles of traffic between resets
    int unsigned reset_max_gap  = 800;
    int unsigned reset_duration = 3;
    bit          async_reset    = 1'b0;

    // ---- Stimulus ----------------------------------------------------------
    int unsigned num_trans = 3000;

    `uvm_object_utils_begin(l1_cache_config)
        `uvm_field_enum(uvm_active_passive_enum, cpu_is_active, UVM_ALL_ON)
        `uvm_field_int(min_idle,            UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(max_idle,            UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(mem_min_latency,     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(mem_max_latency,     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(mem_ready_stall_pct, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(mem_max_ready_stall, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(mem_beat_gap_pct,    UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(mem_max_beat_gap,    UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(por_cycles,          UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(num_resets,          UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(reset_min_gap,       UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(reset_max_gap,       UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(reset_duration,      UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(async_reset,         UVM_ALL_ON)
        `uvm_field_int(num_trans,           UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "l1_cache_config");
        super.new(name);
    endfunction

endclass
