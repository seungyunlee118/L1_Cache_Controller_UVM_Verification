`timescale 1ns/1ps
class l1_cache_cpu_sequencer extends uvm_sequencer #(l1_cache_item);

    `uvm_component_utils(l1_cache_cpu_sequencer)

    function new(string name = "l1_cache_cpu_sequencer", uvm_component parent);
        super.new(name, parent);
    endfunction

endclass