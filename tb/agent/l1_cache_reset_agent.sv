`timescale 1ns/1ps


class l1_cache_reset_item extends uvm_sequence_item;
    `uvm_object_utils(l1_cache_reset_item)

    rand int unsigned gap;        // cycles of traffic before pulling reset
    rand int unsigned duration;   // cycles reset is held

    int unsigned min_gap = 200, max_gap = 800, fixed_duration = 3;

    constraint c_gap      { gap inside {[min_gap : max_gap]}; }
    constraint c_duration { duration == fixed_duration; }

    function new(string name = "l1_cache_reset_item");
        super.new(name);
    endfunction
endclass


class l1_cache_reset_sequencer extends uvm_sequencer #(l1_cache_reset_item);
    `uvm_component_utils(l1_cache_reset_sequencer)
    function new(string name = "l1_cache_reset_sequencer", uvm_component parent);
        super.new(name, parent);
    endfunction
endclass


class l1_cache_reset_driver extends uvm_driver #(l1_cache_reset_item);
    `uvm_component_utils(l1_cache_reset_driver)

    virtual l1_cache_if vif;
    l1_cache_config     cfg;

    // Broadcast so the scoreboard can flush at exactly the right moment.
    uvm_analysis_port #(l1_cache_reset_item) ap;

    function new(string name = "l1_cache_reset_driver", uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual l1_cache_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF", "virtual interface must be set for vif")
        if (!uvm_config_db#(l1_cache_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("NO_CFG", "config must be set for cfg")
    endfunction

    virtual task run_phase(uvm_phase phase);
        l1_cache_reset_item item;

        // ---- power-on reset ------------------------------------------------
        repeat (cfg.por_cycles) @(posedge vif.clk);
        vif.rst_n <= 1'b1;
        `uvm_info(get_type_name(), "Power-on reset released", UVM_LOW)

        // ---- mid-traffic resets --------------------------------------------
        forever begin
            seq_item_port.get_next_item(item);

            repeat (item.gap) @(posedge vif.clk);

            if (!cfg.async_reset) begin
                // Let any burst in flight finish so nothing is lost.
                while (vif.mem_req_valid || vif.mem_wr_valid || vif.mem_rd_valid)
                    @(posedge vif.clk);
            end

            `uvm_info(get_type_name(),
                      $sformatf("Asserting reset for %0d cycles (%s)",
                                item.duration, cfg.async_reset ? "async" : "quiesced"), UVM_LOW)

            ap.write(item);

            vif.assert_reset(item.duration);

            seq_item_port.item_done();
        end
    endtask
endclass


class l1_cache_reset_agent extends uvm_agent;
    `uvm_component_utils(l1_cache_reset_agent)

    l1_cache_reset_sequencer sqr;
    l1_cache_reset_driver    drv;

    function new(string name = "l1_cache_reset_agent", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = l1_cache_reset_sequencer::type_id::create("sqr", this);
        drv = l1_cache_reset_driver::type_id::create("drv", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass


// ============================================================================
// Sequence that fires cfg.num_resets mid-traffic resets.
// ============================================================================
class l1_cache_reset_seq extends uvm_sequence #(l1_cache_reset_item);
    `uvm_object_utils(l1_cache_reset_seq)

    l1_cache_config cfg;

    function new(string name = "l1_cache_reset_seq");
        super.new(name);
    endfunction

    virtual task body();
        if (!uvm_config_db#(l1_cache_config)::get(m_sequencer, "", "cfg", cfg))
            `uvm_fatal("NO_CFG", "l1_cache_config not found for the reset sequence")

        for (int i = 0; i < cfg.num_resets; i++) begin
            req = l1_cache_reset_item::type_id::create("req");
            start_item(req);
            req.min_gap        = cfg.reset_min_gap;
            req.max_gap        = cfg.reset_max_gap;
            req.fixed_duration = cfg.reset_duration;
            if (!req.randomize())
                `uvm_error(get_type_name(), "randomize() failed on l1_cache_reset_item")
            finish_item(req);
        end
    endtask
endclass
