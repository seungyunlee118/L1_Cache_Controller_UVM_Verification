`timescale 1ns/1ps

class l1_cache_env extends uvm_env;

    `uvm_component_utils(l1_cache_env)

    l1_cache_cpu_agent   cpu_agt;
    l1_cache_mem_agent   mem_agt;
    l1_cache_reset_agent rst_agt;
    l1_cache_scoreboard  scb;
    l1_cache_coverage    cov;

    function new(string name = "l1_cache_env", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cpu_agt = l1_cache_cpu_agent::type_id::create("cpu_agt", this);
        mem_agt = l1_cache_mem_agent::type_id::create("mem_agt", this);
        rst_agt = l1_cache_reset_agent::type_id::create("rst_agt", this);
        scb     = l1_cache_scoreboard::type_id::create("scb", this);
        cov     = l1_cache_coverage::type_id::create("cov", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Accepted requests (issue order) and read responses go to separate
        // scoreboard ports so program order survives the pipeline overlap.
        cpu_agt.mon.req_ap.connect(scb.req_export);
        cpu_agt.mon.rsp_ap.connect(scb.rsp_export);
        mem_agt.mon.ap.connect(scb.mem_export);

        // The reset driver announces a reset before pulling it, so the model
        // flushes at the same instant the DUT does.
        rst_agt.drv.ap.connect(scb.rst_export);

        // Coverage is fed from the scoreboard, not the monitor: hit/miss, way
        // and victim state only exist in the golden cache model.
        scb.cov_ap.connect(cov.analysis_export);
    endfunction

endclass
