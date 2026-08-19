`timescale 1ns/1ps

class l1_cache_mem_monitor extends uvm_monitor;

    `uvm_component_utils(l1_cache_mem_monitor)

    virtual l1_cache_if vif;
    uvm_analysis_port #(l1_cache_mem_item) ap;

    function new(string name = "l1_cache_mem_monitor", uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual l1_cache_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"})
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            wait (vif.rst_n === 1'b1);
            fork
                begin : collect
                    forever collect_burst();
                end
                begin : watch_reset
                    @(negedge vif.rst_n);
                end
            join_any
            disable fork;
            // Any partially collected burst is abandoned on reset.
            wait (vif.rst_n === 1'b1);
        end
    endtask

    virtual task collect_burst();
        l1_cache_mem_item item;
        int               nbeats, b;

        @(vif.cb_mem_mon);
        if (!(vif.cb_mem_mon.mem_req_valid === 1'b1 && vif.cb_mem_mon.mem_req_ready === 1'b1))
            return;

        item          = l1_cache_mem_item::type_id::create("item");
        item.req_rw   = vif.cb_mem_mon.mem_req_rw;
        item.req_addr = vif.cb_mem_mon.mem_req_addr;
        item.req_len  = vif.cb_mem_mon.mem_req_len;
        nbeats        = item.req_len + 1;
        item.beats    = new[nbeats];

        b = 0;
        if (item.req_rw == 1'b1) begin
            while (b < nbeats) begin
                @(vif.cb_mem_mon);
                if (vif.cb_mem_mon.mem_wr_valid === 1'b1 && vif.cb_mem_mon.mem_wr_ready === 1'b1) begin
                    item.beats[b] = vif.cb_mem_mon.mem_wr_data;
                    b++;
                end
            end
        end
        else begin
            while (b < nbeats) begin
                @(vif.cb_mem_mon);
                if (vif.cb_mem_mon.mem_rd_valid === 1'b1) begin
                    item.beats[b] = vif.cb_mem_mon.mem_rd_data;
                    b++;
                end
            end
        end

        ap.write(item);
        `uvm_info(get_type_name(), item.convert2string(), UVM_HIGH)
    endtask

endclass
