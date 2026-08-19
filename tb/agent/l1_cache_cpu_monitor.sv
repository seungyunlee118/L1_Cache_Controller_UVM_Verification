`timescale 1ns/1ps

class l1_cache_cpu_monitor extends uvm_monitor;

    `uvm_component_utils(l1_cache_cpu_monitor)

    virtual l1_cache_if vif;

    uvm_analysis_port #(l1_cache_item) req_ap;
    uvm_analysis_port #(l1_cache_item) rsp_ap;

    l1_cache_item req_q[$];   // reads waiting for their data

    function new(string name = "l1_cache_cpu_monitor", uvm_component parent);
        super.new(name, parent);
        req_ap = new("req_ap", this);
        rsp_ap = new("rsp_ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual l1_cache_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"})
    endfunction

    virtual task run_phase(uvm_phase phase);
        fork
            observe_requests();
            observe_responses();
            handle_reset();
        join
    endtask


    virtual task handle_reset();
        forever begin
            @(negedge vif.rst_n);
            req_q.delete();
            `uvm_info(get_type_name(), "Reset: dropped in-flight read tracking", UVM_MEDIUM)
        end
    endtask

    virtual task observe_requests();
        l1_cache_item item;
        forever begin
            @(vif.cb_cpu_mon);
            if (vif.rst_n !== 1'b1) continue;

            if (vif.cb_cpu_mon.cpu_req_valid === 1'b1 &&
                vif.cb_cpu_mon.cpu_req_ready === 1'b1) begin

                item = l1_cache_item::type_id::create("item");
                item.rw    = vif.cb_cpu_mon.cpu_req_rw;
                item.addr  = vif.cb_cpu_mon.cpu_req_addr;
                item.be    = vif.cb_cpu_mon.cpu_req_be;
                item.wdata = vif.cb_cpu_mon.cpu_req_wdata;

                req_ap.write(item);                          // issue order
                if (item.rw == 1'b0) req_q.push_back(item);

                `uvm_info(get_type_name(),
                          $sformatf("Req accepted: %s", item.convert2string()), UVM_HIGH)
            end
        end
    endtask

    virtual task observe_responses();
        l1_cache_item rsp_item;
        forever begin
            @(vif.cb_cpu_mon);
            if (vif.rst_n !== 1'b1) continue;

            if (vif.cb_cpu_mon.cpu_rsp_valid === 1'b1) begin
                if (req_q.size() > 0) begin
                    rsp_item       = req_q.pop_front();
                    rsp_item.rdata = vif.cb_cpu_mon.cpu_rsp_rdata;
                    rsp_ap.write(rsp_item);

                    `uvm_info(get_type_name(),
                              $sformatf("Read rsp: Addr=0x%08x RData=0x%08x",
                                        rsp_item.addr, rsp_item.rdata), UVM_HIGH)
                end else begin
                    `uvm_error("MON_SYNC", "cpu_rsp_valid asserted with no pending read request")
                end
            end
        end
    endtask

endclass
