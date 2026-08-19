`timescale 1ns/1ps

class l1_cache_coverage extends uvm_subscriber #(l1_cache_item);
    `uvm_component_utils(l1_cache_coverage)

    l1_cache_item tr;

    covergroup cg_cache_ops;
        option.per_instance = 1;
        option.name         = "cache_ops";

        cp_rw: coverpoint tr.rw {
            bins read  = {1'b0};
            bins write = {1'b1};
        }

        cp_hit: coverpoint tr.hit {
            bins miss = {1'b0};
            bins hit  = {1'b1};
        }

        cp_evict: coverpoint tr.did_evict {
            bins no_evict    = {1'b0};
            bins dirty_evict = {1'b1};
        }

        // Cold miss vs conflict miss vs conflict-with-write-back.
        cp_victim: coverpoint tr.victim_state {
            bins cold_miss     = {l1_cache_item::VICTIM_INVALID};
            bins conflict_cln  = {l1_cache_item::VICTIM_CLEAN};
            bins conflict_drty = {l1_cache_item::VICTIM_DIRTY};
            bins was_a_hit     = {l1_cache_item::VICTIM_NONE};
        }

        // All four ways must be used - catches a broken PLRU that always
        // picks the same victim.
        cp_way: coverpoint tr.way {
            bins way[4] = {[0:3]};
        }

        // Every word position inside a line must be accessed.
        cp_word: coverpoint tr.word_off {
            bins word[4] = {[0:3]};
        }

        // Set reach, in 8 buckets of 8 sets.
        cp_set: coverpoint get_set(tr.addr) {
            bins set_grp[8] = {[0:SETS-1]};
        }

        // Byte-enable shapes on writes.
        cp_be: coverpoint tr.be iff (tr.rw) {
            bins full_word = {4'b1111};
            bins one_byte  = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
            bins halfword  = {4'b0011, 4'b1100};
            bins other     = default;
        }

        // read-hit / read-miss / write-hit / write-miss must all occur
        x_rw_hit:    cross cp_rw, cp_hit;

        // an eviction must be provoked by both a read miss and a write miss
        x_rw_evict:  cross cp_rw, cp_evict {
            ignore_bins no_evict_bins = binsof(cp_evict.no_evict);
        }

        // every way must serve both a hit and a fill
        x_way_hit:   cross cp_way, cp_hit;

        // every word position must be both read and written
        x_word_rw:   cross cp_word, cp_rw;

        // both kinds of victim must be replaced in every way
        x_way_victim: cross cp_way, cp_victim {
            ignore_bins hits = binsof(cp_victim.was_a_hit);
        }

        // partial writes must land on both hits and misses
        x_be_hit:    cross cp_be, cp_hit;
    endgroup

    function new(string name = "l1_cache_coverage", uvm_component parent);
        super.new(name, parent);
        cg_cache_ops = new();
    endfunction

    virtual function void write(l1_cache_item t);
        tr = t;
        cg_cache_ops.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_type_name(), "========================================", UVM_NONE)
        `uvm_info(get_type_name(), " FUNCTIONAL COVERAGE", UVM_NONE)
        `uvm_info(get_type_name(), "========================================", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(" cache_ops covergroup : %0.2f%%", cg_cache_ops.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   cp_rw        : %0.2f%%", cg_cache_ops.cp_rw.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   cp_hit       : %0.2f%%", cg_cache_ops.cp_hit.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   cp_evict     : %0.2f%%", cg_cache_ops.cp_evict.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   cp_victim    : %0.2f%%", cg_cache_ops.cp_victim.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   cp_way       : %0.2f%%", cg_cache_ops.cp_way.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   cp_word      : %0.2f%%", cg_cache_ops.cp_word.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   cp_set       : %0.2f%%", cg_cache_ops.cp_set.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   cp_be        : %0.2f%%", cg_cache_ops.cp_be.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   x_rw_hit     : %0.2f%%", cg_cache_ops.x_rw_hit.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   x_rw_evict   : %0.2f%%", cg_cache_ops.x_rw_evict.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   x_way_hit    : %0.2f%%", cg_cache_ops.x_way_hit.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   x_word_rw    : %0.2f%%", cg_cache_ops.x_word_rw.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   x_way_victim : %0.2f%%", cg_cache_ops.x_way_victim.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("   x_be_hit     : %0.2f%%", cg_cache_ops.x_be_hit.get_coverage()), UVM_NONE)
        `uvm_info(get_type_name(), "========================================", UVM_NONE)
        // Machine-readable line for the regression script.
        `uvm_info(get_type_name(), $sformatf("FUNCCOV=%0.2f", cg_cache_ops.get_coverage()), UVM_NONE)
    endfunction

endclass
