`timescale 1ns/1ps

// ============================================================================
// Unconstrained random traffic across the whole 32-bit address space.
//
// Almost every access misses and most reads fetch a never-written line
// (DEADBEEF), which exercises the allocate path and the "clean victim - no
// write-back" branch far harder than the locality-friendly mix sequence.
// ============================================================================
class l1_cache_rand_seq extends l1_cache_base_seq;
    `uvm_object_utils(l1_cache_rand_seq)

    function new(string name = "l1_cache_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        l1_cache_item item;
        int           n = cfg.num_trans;

        `uvm_info(get_type_name(), $sformatf("== Fully random sequence: %0d transactions ==", n), UVM_LOW)

        for (int i = 0; i < n; i++) begin
            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize())          // only c_addr_align applies
                `uvm_error(get_type_name(), "randomize() failed")
            finish_item(item);
        end

        `uvm_info(get_type_name(), "== Fully random sequence completed ==", UVM_LOW)
    endtask
endclass
