`timescale 1ns/1ps

// ============================================================================
// Base test.
//
// Owns the config object, builds the env, forks off the endless main-memory
// responder and the reset sequence, and runs one CPU stimulus sequence.
//
// Derived tests override configure() to change knobs and set seq_name.
// Sequence selection stays overridable at runtime with +SEQ=<name>.
// ============================================================================
class l1_cache_base_test extends uvm_test;
    `uvm_component_utils(l1_cache_base_test)

    l1_cache_env    env;
    l1_cache_config cfg;
    string          seq_name = "l1_cache_mix_seq";

    function new(string name = "l1_cache_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Hook for derived tests.
    virtual function void configure(l1_cache_config c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        cfg = l1_cache_config::type_id::create("cfg");
        configure(cfg);
        void'($value$plusargs("SEQ=%s",       seq_name));
        void'($value$plusargs("NUM_TRANS=%d", cfg.num_trans));

        uvm_config_db#(l1_cache_config)::set(this, "*", "cfg", cfg);

        env = l1_cache_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info(get_type_name(), {"\n", cfg.sprint()}, UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        // Factory access differs across UVM versions: 1.2 removed
        // uvm_factory::get() in favour of the core service, while 1.1d (the
        // default UVM in Questa FSE) has no uvm_coreservice_t. UVM_POST_VERSION_1_1
        // is defined only in 1.2+, so it selects the right API for either
        // simulator (Vivado xsim = 1.2, Questa = 1.1d).
        uvm_factory                   f;
        uvm_object                    obj;
        uvm_sequence #(l1_cache_item) seq;
        l1_cache_mem_rsp_seq          rsp_seq;
        l1_cache_reset_seq            rst_seq;

        `ifdef UVM_POST_VERSION_1_1
            f = uvm_coreservice_t::get().get_factory();
        `else
            f = uvm_factory::get();
        `endif

        phase.raise_objection(this);
        // Long enough to drain a miss that is still waiting on slow memory.
        phase.phase_done.set_drain_time(this, 3us);

        // Endless responder - must not hold an objection.
        rsp_seq = l1_cache_mem_rsp_seq::type_id::create("rsp_seq");
        fork
            rsp_seq.start(env.mem_agt.sqr);
        join_none

        // Mid-traffic resets, if this test asked for any.
        if (cfg.num_resets > 0) begin
            rst_seq = l1_cache_reset_seq::type_id::create("rst_seq");
            fork
                rst_seq.start(env.rst_agt.sqr);
            join_none
        end

        obj = f.create_object_by_name(seq_name, get_full_name(), "seq");
        if (obj == null || !$cast(seq, obj))
            `uvm_fatal("BAD_SEQ", $sformatf("'%s' is not a registered l1_cache_item sequence", seq_name))

        `uvm_info(get_type_name(), $sformatf("Running sequence: %s", seq_name), UVM_NONE)

        // Wait for the reset agent to release power-on reset.
        wait (env.cpu_agt.drv.vif.rst_n === 1'b1);
        repeat (5) @(posedge env.cpu_agt.drv.vif.clk);

        seq.start(env.cpu_agt.sqr);
        #200ns;

        phase.drop_objection(this);
    endtask

endclass


// ---------------------------------------------------------------------------
// Scenario tests
// ---------------------------------------------------------------------------

// Quick sanity run - short, gentle memory.
class l1_cache_smoke_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_smoke_test)
    function new(string name = "l1_cache_smoke_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_mix_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.num_trans           = 300;
        c.mem_min_latency     = 1;
        c.mem_max_latency     = 3;
        c.mem_ready_stall_pct = 0;
        c.mem_beat_gap_pct    = 0;
    endfunction
endclass


// Default regression workhorse.
class l1_cache_random_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_random_test)
    function new(string name = "l1_cache_random_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_mix_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.num_trans = 2000;
    endfunction
endclass


// Whole-address-space random traffic: almost everything misses.
class l1_cache_thrash_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_thrash_test)
    function new(string name = "l1_cache_thrash_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_rand_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.num_trans = 1000;
    endfunction
endclass


// Dirty write-back / allocate stress across all four ways.
class l1_cache_eviction_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_eviction_test)
    function new(string name = "l1_cache_eviction_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_eviction_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.num_trans = 1200;
    endfunction
endclass


// True back-to-back requests: VALID never drops between accepted requests.
class l1_cache_b2b_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_b2b_test)
    function new(string name = "l1_cache_b2b_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_b2b_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.min_idle  = 0;
        c.max_idle  = 0;
        c.num_trans = 800;
    endfunction
endclass


// Multi-word line / spatial locality: proves the burst fill lands correctly.
class l1_cache_line_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_line_test)
    function new(string name = "l1_cache_line_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_line_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.num_trans = 1200;
    endfunction
endclass


// Byte enables, back to back so the per-byte forwarding path is exercised.
class l1_cache_be_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_be_test)
    function new(string name = "l1_cache_be_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_be_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.min_idle  = 0;
        c.max_idle  = 0;
        c.num_trans = 900;
    endfunction
endclass


// Worst case: no idle gaps, slow memory, heavy backpressure on both channels.
class l1_cache_stress_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_stress_test)
    function new(string name = "l1_cache_stress_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_mix_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.min_idle            = 0;
        c.max_idle            = 0;
        c.num_trans           = 1200;
        c.mem_min_latency     = 10;
        c.mem_max_latency     = 50;
        c.mem_ready_stall_pct = 60;
        c.mem_max_ready_stall = 6;
        c.mem_beat_gap_pct    = 60;
        c.mem_max_beat_gap    = 4;
    endfunction
endclass


// Reset while traffic is flowing, with the memory bus quiesced first so every
// check stays live. Proves the cache flushes and recovers.
class l1_cache_reset_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_reset_test)
    function new(string name = "l1_cache_reset_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_mix_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.num_trans     = 1500;
        c.num_resets    = 4;
        c.reset_min_gap = 300;
        c.reset_max_gap = 900;
        c.async_reset   = 1'b0;
    endfunction
endclass


// ---------------------------------------------------------------------------
// Passive-agent test.
//
// The CPU agent's passive mode exists so the whole environment can be reused
// inside a larger SoC testbench, where some other master drives the CPU port.
// Left untested it is just dead code, and the usual way it rots is that the
// monitor quietly grows a dependency on the driver.
//
// So: build the agent passive (no sequencer, no driver) and drive the pins
// from a small BFM in the test itself. The monitor, scoreboard and coverage
// must work exactly as before.
// ---------------------------------------------------------------------------
class l1_cache_passive_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_passive_test)

    virtual l1_cache_if vif;

    function new(string name = "l1_cache_passive_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void configure(l1_cache_config c);
        c.cpu_is_active       = UVM_PASSIVE;
        c.num_trans           = 0;      // stimulus comes from the BFM below
        c.mem_ready_stall_pct = 30;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual l1_cache_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF", "virtual interface must be set for vif")
    endfunction

    virtual task run_phase(uvm_phase phase);
        l1_cache_mem_rsp_seq rsp_seq;

        // No driver exists in passive mode, so the bus must be parked here or
        // it sits at X through reset and trips the reset assertion.
        vif.cpu_req_valid = 1'b0;
        vif.cpu_req_rw    = 1'bx;
        vif.cpu_req_addr  = 32'bx;
        vif.cpu_req_be    = 'x;
        vif.cpu_req_wdata = 32'bx;

        phase.raise_objection(this);
        phase.phase_done.set_drain_time(this, 3us);

        rsp_seq = l1_cache_mem_rsp_seq::type_id::create("rsp_seq");
        fork
            rsp_seq.start(env.mem_agt.sqr);
        join_none

        wait (vif.rst_n === 1'b1);
        repeat (5) @(vif.cb_cpu);

        // Walk several lines: write every word, then read them all back.
        for (int ln = 0; ln < 24; ln++) begin
            // Declare and assign separately. A declaration initialiser inside
            // a loop body is not guaranteed to re-evaluate per iteration -
            // xsim ran this one once, leaving base stuck at its first value,
            // which quietly turned 24 distinct lines into 1.
            bit [31:0] base;
            base = make_line_addr(tag_t'(ln + 1), set_t'(ln * 3));
            for (int w = 0; w < WORDS_PER_LINE; w++)
                bfm_req(1'b1, base + (w*4), 4'b1111, 32'hA5A5_0000 + (ln*16) + w);
            for (int w = 0; w < WORDS_PER_LINE; w++)
                bfm_req(1'b0, base + (w*4), 4'b1111, 32'b0);
        end

        bfm_idle();
        repeat (20) @(vif.cb_cpu);

        phase.drop_objection(this);
    endtask

    // Minimal in-test driver: exactly the handshake the real driver uses.
    virtual task bfm_req(bit rw, bit [31:0] addr, bit [3:0] be, bit [31:0] wdata);
        vif.cb_cpu.cpu_req_valid <= 1'b1;
        vif.cb_cpu.cpu_req_rw    <= rw;
        vif.cb_cpu.cpu_req_addr  <= addr;
        vif.cb_cpu.cpu_req_be    <= be;
        vif.cb_cpu.cpu_req_wdata <= wdata;
        do @(vif.cb_cpu); while (vif.cb_cpu.cpu_req_ready !== 1'b1);
    endtask

    virtual task bfm_idle();
        vif.cb_cpu.cpu_req_valid <= 1'b0;
        vif.cb_cpu.cpu_req_rw    <= 1'bx;
        vif.cb_cpu.cpu_req_addr  <= 32'bx;
        vif.cb_cpu.cpu_req_be    <= 'x;
        vif.cb_cpu.cpu_req_wdata <= 32'bx;
    endtask
endclass


// Reset at a genuinely arbitrary moment, including mid-burst. Data checking is
// suppressed only for lines whose write-back was cut short; every protocol,
// ordering and burst-length check stays active.
class l1_cache_reset_async_test extends l1_cache_base_test;
    `uvm_component_utils(l1_cache_reset_async_test)
    function new(string name = "l1_cache_reset_async_test", uvm_component parent = null);
        super.new(name, parent);
        seq_name = "l1_cache_mix_seq";
    endfunction
    virtual function void configure(l1_cache_config c);
        c.num_trans           = 1500;
        c.num_resets          = 6;
        c.reset_min_gap       = 150;
        c.reset_max_gap       = 600;
        c.async_reset         = 1'b1;
        c.mem_min_latency     = 6;
        c.mem_max_latency     = 20;
        c.mem_beat_gap_pct    = 50;
    endfunction
endclass
