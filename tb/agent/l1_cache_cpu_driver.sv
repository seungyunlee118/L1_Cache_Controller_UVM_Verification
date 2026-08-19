`timescale 1ns/1ps

class l1_cache_cpu_driver extends uvm_driver #(l1_cache_item);

    `uvm_component_utils(l1_cache_cpu_driver)

    virtual l1_cache_if vif;
    l1_cache_config     cfg;
    bit                 accept_ok;

    function new(string name = "l1_cache_cpu_driver", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual l1_cache_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"})
        if (!uvm_config_db#(l1_cache_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("NO_CFG", {"Config must be set for: ", get_full_name(), ".cfg"})
    endfunction

    virtual task run_phase(uvm_phase phase);
        l1_cache_item item;
        int unsigned  gap;

        park_bus();
        wait (vif.rst_n === 1'b1);
        @(vif.cb_cpu);

        forever begin
            if (item == null) begin
                drive_idle();
                seq_item_port.get_next_item(item);
                @(vif.cb_cpu);
            end

            if (vif.rst_n !== 1'b1) begin
                seq_item_port.item_done();
                item = null;
                recover_from_reset();
                continue;
            end

            drive_payload(item);
            wait_accept(accept_ok);

            if (!accept_ok) begin
                // Reset cut the request short. Retire it and resynchronise.
                seq_item_port.item_done();
                item = null;
                recover_from_reset();
                continue;
            end

            seq_item_port.item_done();

            gap = $urandom_range(cfg.min_idle, cfg.max_idle);

            if (gap == 0) begin
                // Back-to-back: take the next item without releasing the bus.
                // Assigning here - still in the accept edge's reactive region -
                // puts the new payload out for the very next cycle.
                seq_item_port.try_next_item(item);
                if (item == null) drive_idle();
            end
            else begin
                item = null;
                drive_idle();
                repeat (gap) @(vif.cb_cpu);
            end
        end
    endtask

    // Waits for the accept edge. Sets ok = 0 if reset abandoned the request.
    virtual task wait_accept(output bit ok);
        forever begin
            @(vif.cb_cpu);
            if (vif.rst_n !== 1'b1) begin
                drive_idle();
                ok = 1'b0;
                return;
            end
            if (vif.cb_cpu.cpu_req_ready === 1'b1) begin
                ok = 1'b1;
                return;
            end
        end
    endtask

    virtual task recover_from_reset();
        drive_idle();
        wait (vif.rst_n === 1'b1);
        @(vif.cb_cpu);
    endtask

    // Direct (non-clocking) assignment so the bus is defined at time 0, before
    // the first clock edge the reset assertion can sample.
    virtual task park_bus();
        vif.cpu_req_valid = 1'b0;
        vif.cpu_req_rw    = 1'bx;
        vif.cpu_req_addr  = 32'bx;
        vif.cpu_req_be    = 'x;
        vif.cpu_req_wdata = 32'bx;
    endtask

    // X on the payload while idle: anything that latches it without checking
    // VALID shows up immediately.
    virtual task drive_idle();
        vif.cb_cpu.cpu_req_valid <= 1'b0;
        vif.cb_cpu.cpu_req_rw    <= 1'bx;
        vif.cb_cpu.cpu_req_addr  <= 32'bx;
        vif.cb_cpu.cpu_req_be    <= 'x;
        vif.cb_cpu.cpu_req_wdata <= 32'bx;
    endtask

    virtual task drive_payload(l1_cache_item item);
        vif.cb_cpu.cpu_req_valid <= 1'b1;
        vif.cb_cpu.cpu_req_rw    <= item.rw;
        vif.cb_cpu.cpu_req_addr  <= item.addr;
        vif.cb_cpu.cpu_req_be    <= item.be;
        vif.cb_cpu.cpu_req_wdata <= item.wdata;
    endtask

endclass
