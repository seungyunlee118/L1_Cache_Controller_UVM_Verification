`timescale 1ns/1ps

// ============================================================================
// Byte-enable sequence.
//
// Writes a known full word, then overwrites individual byte lanes and reads
// back, so the untouched lanes must survive. This is the check that catches a
// data array that ignores byte enables (every lane overwritten) as well as a
// forwarding path that forwards the whole word instead of merging per byte -
// the latter only shows up when the read lands in the cycle right after the
// partial write, which back-to-back mode makes routine.
// ============================================================================
class l1_cache_be_seq extends l1_cache_base_seq;
    `uvm_object_utils(l1_cache_be_seq)

    function new(string name = "l1_cache_be_seq");
        super.new(name);
    endfunction

    virtual task body();
        l1_cache_item item;
        int           rounds = (cfg.num_trans / 6);

        `uvm_info(get_type_name(), $sformatf("== Byte-enable sequence: %0d rounds ==", rounds), UVM_LOW)

        for (int r = 0; r < rounds; r++) begin
            // Declare and assign separately - a declaration initialiser inside
            // a loop body is not guaranteed to re-evaluate per iteration.
            tag_t      tg;
            set_t      st;
            word_t     wd;
            bit [31:0] a;
            bit [3:0]  lanes;

            tg = tag_t'($urandom_range(0, 63));
            st = set_t'($urandom_range(0, SETS-1));
            wd = word_t'($urandom_range(0, WORDS_PER_LINE-1));
            a  = make_line_addr(tg, st) | (wd << BYTE_BITS);

            // 1. Establish a known full word.
            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b1; addr == a; be == 4'b1111; })
                `uvm_error(get_type_name(), "randomize() failed (be seed)")
            finish_item(item);

            // 2. Overwrite a random subset of lanes.
            lanes = 4'(1 << $urandom_range(0, 3));
            if ($urandom_range(0, 1)) lanes |= 4'(1 << $urandom_range(0, 3));

            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b1; addr == a; be == lanes; })
                `uvm_error(get_type_name(), "randomize() failed (be partial)")
            finish_item(item);

            // 3. Read back - the lanes we did not touch must be unchanged.
            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b0; addr == a; })
                `uvm_error(get_type_name(), "randomize() failed (be verify)")
            finish_item(item);

            // 4. Another partial write on a different lane, then verify again.
            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b1; addr == a; be != 4'b1111; be != 4'b0000; })
                `uvm_error(get_type_name(), "randomize() failed (be partial 2)")
            finish_item(item);

            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b0; addr == a; })
                `uvm_error(get_type_name(), "randomize() failed (be verify 2)")
            finish_item(item);
        end

        `uvm_info(get_type_name(), "== Byte-enable sequence completed ==", UVM_LOW)
    endtask
endclass
