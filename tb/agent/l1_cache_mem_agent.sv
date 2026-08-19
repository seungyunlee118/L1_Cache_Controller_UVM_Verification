`timescale 1ns/1ps

class l1_cache_mem_agent extends uvm_agent;
    `uvm_component_utils(l1_cache_mem_agent)

    l1_cache_mem_sequencer sqr;
    l1_cache_mem_driver    drv;
    l1_cache_mem_monitor   mon;

    function new(string name = "l1_cache_mem_agent", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = l1_cache_mem_monitor::type_id::create("mon", this);
        sqr = l1_cache_mem_sequencer::type_id::create("sqr", this);
        drv = l1_cache_mem_driver::type_id::create("drv", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
