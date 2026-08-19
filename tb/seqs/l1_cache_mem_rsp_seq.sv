`timescale 1ns/1ps

// ============================================================================
// Endless responder sequence for the main-memory agent.
// Supplies one timing item per burst the cache issues.  Runs for the whole
// test and must NOT raise an objection - the base test forks it off.
// ============================================================================
class l1_cache_mem_rsp_seq extends uvm_sequence #(l1_cache_mem_item);
    `uvm_object_utils(l1_cache_mem_rsp_seq)

    l1_cache_config cfg;

    function new(string name = "l1_cache_mem_rsp_seq");
        super.new(name);
    endfunction

    virtual task body();
        if (!uvm_config_db#(l1_cache_config)::get(m_sequencer, "", "cfg", cfg))
            `uvm_fatal("NO_CFG", "l1_cache_config not found for the memory responder sequence")

        `uvm_info(get_type_name(),
                  $sformatf("Memory responder: latency %0d-%0d cycles, %0d%% of bursts see up to %0d cycles of request backpressure, %0d%% see up to %0d idle cycles between beats",
                            cfg.mem_min_latency, cfg.mem_max_latency,
                            cfg.mem_ready_stall_pct, cfg.mem_max_ready_stall,
                            cfg.mem_beat_gap_pct, cfg.mem_max_beat_gap), UVM_LOW)

        forever begin
            req = l1_cache_mem_item::type_id::create("req");
            start_item(req);
            req.min_latency     = cfg.mem_min_latency;
            req.max_latency     = cfg.mem_max_latency;
            req.max_ready_stall = cfg.mem_max_ready_stall;
            req.ready_stall_pct = cfg.mem_ready_stall_pct;
            req.max_beat_gap    = cfg.mem_max_beat_gap;
            req.beat_gap_pct    = cfg.mem_beat_gap_pct;
            if (!req.randomize())
                `uvm_error(get_type_name(), "randomize() failed on l1_cache_mem_item")
            finish_item(req);
        end
    endtask
endclass
