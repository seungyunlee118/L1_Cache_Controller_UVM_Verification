`timescale 1ns/1ps

class l1_cache_mem_driver extends uvm_driver #(l1_cache_mem_item);
    `uvm_component_utils(l1_cache_mem_driver)

    virtual l1_cache_if vif;

    bit [31:0] main_mem [int];
    bit        aborted;          // set when reset cut the current transfer short

    function new(string name = "l1_cache_mem_driver", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual l1_cache_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF", "virtual interface must be set for vif")
    endfunction

    virtual task run_phase(uvm_phase phase);
        drive_idle();
        forever begin
            wait (vif.rst_n === 1'b1);
            service_one_request();
            if (aborted) begin
                drive_idle();
                wait (vif.rst_n === 1'b1);
            end
        end
    endtask

    // One clock, with an abort check. Every wait in the transfer goes through
    // this, so reset can interrupt at any point.
    virtual task tick();
        @(vif.cb_mem);
        if (vif.rst_n !== 1'b1) aborted = 1'b1;
    endtask

    virtual task service_one_request();
        l1_cache_mem_item item;

        aborted = 1'b0;

        // 1. Wait for a request (reset may interrupt the wait).
        forever begin
            tick();
            if (aborted)                            return;
            if (vif.cb_mem.mem_req_valid === 1'b1)  break;
        end

        // From here the get/item_done pair is always balanced, whatever reset
        // does to the transfer in between.
        seq_item_port.get_next_item(item);
        do_transfer(item);
        seq_item_port.item_done();
    endtask

    virtual task do_transfer(l1_cache_mem_item item);
        bit [31:0] addr;
        int        nbeats;

        // 2. Request-channel backpressure.
        repeat (item.ready_stall) begin
            tick();
            if (aborted) return;
        end

        // 3. Accept the request.
        vif.cb_mem.mem_req_ready <= 1'b1;
        tick();
        if (aborted) begin
            vif.cb_mem.mem_req_ready <= 1'b0;
            return;
        end

        item.req_rw   = vif.cb_mem.mem_req_rw;
        item.req_addr = vif.cb_mem.mem_req_addr;
        item.req_len  = vif.cb_mem.mem_req_len;
        vif.cb_mem.mem_req_ready <= 1'b0;

        nbeats     = item.req_len + 1;
        item.beats = new[nbeats];

        if (item.req_rw == 1'b1) begin
            // ---- write-back: accept nbeats on the write-data channel -------
            for (int b = 0; b < nbeats; b++) begin
                repeat (item.beat_gap) begin        // withhold READY
                    vif.cb_mem.mem_wr_ready <= 1'b0;
                    tick();
                    if (aborted) return;
                end

                vif.cb_mem.mem_wr_ready <= 1'b1;
                forever begin
                    tick();
                    if (aborted) begin
                        vif.cb_mem.mem_wr_ready <= 1'b0;
                        return;
                    end
                    if (vif.cb_mem.mem_wr_valid === 1'b1) break;
                end

                addr           = item.req_addr + (b * 4);
                item.beats[b]  = vif.cb_mem.mem_wr_data;
                main_mem[addr] = vif.cb_mem.mem_wr_data;
                vif.cb_mem.mem_wr_ready <= 1'b0;

                if (vif.cb_mem.mem_wr_last && (b != nbeats-1))
                    `uvm_error("MEM_DRV", $sformatf("LAST asserted on beat %0d of %0d", b, nbeats))
            end
            `uvm_info("MEM_DRV", $sformatf("Store line 0x%08x %p", item.req_addr, item.beats), UVM_HIGH)
        end
        else begin
            // ---- line fetch: return nbeats after `latency` cycles ----------
            repeat (item.latency) begin
                tick();
                if (aborted) return;
            end

            for (int b = 0; b < nbeats; b++) begin
                repeat (item.beat_gap) begin
                    vif.cb_mem.mem_rd_valid <= 1'b0;
                    tick();
                    if (aborted) return;
                end

                addr          = item.req_addr + (b * 4);
                item.beats[b] = main_mem.exists(addr) ? main_mem[addr] : `L1_MEM_DEFAULT(addr);

                vif.cb_mem.mem_rd_valid <= 1'b1;
                vif.cb_mem.mem_rd_data  <= item.beats[b];
                vif.cb_mem.mem_rd_last  <= (b == nbeats-1);
                tick();
                if (aborted) begin
                    vif.cb_mem.mem_rd_valid <= 1'b0;
                    vif.cb_mem.mem_rd_last  <= 1'b0;
                    return;
                end
            end
            vif.cb_mem.mem_rd_valid <= 1'b0;
            vif.cb_mem.mem_rd_last  <= 1'b0;

            `uvm_info("MEM_DRV", $sformatf("Fetch line 0x%08x %p (latency=%0d)",
                                           item.req_addr, item.beats, item.latency), UVM_HIGH)
        end
    endtask

    virtual task drive_idle();
        vif.mem_req_ready = 1'b0;
        vif.mem_wr_ready  = 1'b0;
        vif.mem_rd_valid  = 1'b0;
        vif.mem_rd_data   = 32'b0;
        vif.mem_rd_last   = 1'b0;
    endtask

endclass
