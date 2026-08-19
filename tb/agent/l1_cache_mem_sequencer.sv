`timescale 1ns/1ps

class l1_cache_mem_sequencer extends uvm_sequencer #(l1_cache_mem_item);

    `uvm_component_utils(l1_cache_mem_sequencer)

    function new(string name = "l1_cache_mem_sequencer", uvm_component parent);
        super.new(name, parent);
    endfunction

endclass