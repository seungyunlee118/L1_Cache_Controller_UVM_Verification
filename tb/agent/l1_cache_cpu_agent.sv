`timescale 1ns/1ps

class l1_cache_cpu_agent extends uvm_agent;

    `uvm_component_utils(l1_cache_cpu_agent)

    l1_cache_cpu_sequencer sqr;
    l1_cache_cpu_driver    drv;
    l1_cache_cpu_monitor   mon;

    l1_cache_config        cfg;

    function new(string name = "l1_cache_cpu_agent", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(l1_cache_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("NO_CFG", {"Config must be set for: ", get_full_name(), ".cfg"})

        is_active = cfg.cpu_is_active;

        mon = l1_cache_cpu_monitor::type_id::create("mon", this);

        if (get_is_active() == UVM_ACTIVE) begin
            sqr = l1_cache_cpu_sequencer::type_id::create("sqr", this);
            drv = l1_cache_cpu_driver::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass
