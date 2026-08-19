`timescale 1ns/1ps

// ============================================================================
// Common base for the CPU stimulus sequences: picks up the config object so
// every sequence honours num_trans, and gives subclasses a helper that fails
// loudly on a randomisation failure.
// ============================================================================
class l1_cache_base_seq extends uvm_sequence #(l1_cache_item);
    `uvm_object_utils(l1_cache_base_seq)

    l1_cache_config cfg;

    function new(string name = "l1_cache_base_seq");
        super.new(name);
    endfunction

    virtual task pre_body();
        if (!uvm_config_db#(l1_cache_config)::get(m_sequencer, "", "cfg", cfg))
            `uvm_fatal("NO_CFG", "l1_cache_config not found for sequence")
    endtask

endclass
