`timescale 1ns/1ps

// ============================================================================
// Eviction stress: hammer a handful of sets with more distinct tags than the
// cache has ways, so the PLRU tree is forced to evict continuously.
//
// With 4 ways, cycling 6 tags through one set guarantees a replacement on
// every other access. Interleaved reads confirm the freshly allocated line,
// and re-reads of a long-evicted address confirm the write-back actually
// reached main memory.
// ============================================================================
class l1_cache_eviction_seq extends l1_cache_base_seq;
    `uvm_object_utils(l1_cache_eviction_seq)

    localparam int TAGS_PER_SET = 6;   // > WAYS, so the set always overflows

    function new(string name = "l1_cache_eviction_seq");
        super.new(name);
    endfunction

    virtual task body();
        l1_cache_item item;
        int           rounds = (cfg.num_trans / (TAGS_PER_SET * 2));
        bit [31:0]    history[$];

        `uvm_info(get_type_name(), $sformatf("== Eviction sequence: %0d rounds ==", rounds), UVM_LOW)

        for (int r = 0; r < rounds; r++) begin
            // A few hot sets, cycled through many tags.
            // Declare and assign separately - a declaration initialiser inside
            // a loop body is not guaranteed to re-evaluate per iteration.
            set_t st;
            st = set_t'($urandom_range(0, 7) * 8);

            for (int k = 1; k <= TAGS_PER_SET; k++) begin
                tag_t      tg;
                word_t     wd;
                bit [31:0] a;

                tg = tag_t'(r * TAGS_PER_SET + k);
                wd = word_t'($urandom_range(0, WORDS_PER_LINE-1));
                a  = make_line_addr(tg, st) | (wd << BYTE_BITS);

                // Write: allocates, and evicts whatever dirty line was there.
                item = l1_cache_item::type_id::create("item");
                start_item(item);
                if (!item.randomize() with { rw == 1'b1; addr == a; })
                    `uvm_error(get_type_name(), "randomize() failed (evict write)")
                finish_item(item);
                history.push_back(a);

                // Read it straight back - must hit and return what we wrote.
                item = l1_cache_item::type_id::create("item");
                start_item(item);
                if (!item.randomize() with { rw == 1'b0; addr == a; })
                    `uvm_error(get_type_name(), "randomize() failed (evict read)")
                finish_item(item);
            end

            // Re-read something evicted a while ago: forces an allocate that
            // must return the data the write-back put into main memory.
            if (history.size() > 16) begin
                bit [31:0] old_a;
                old_a = history[$urandom_range(0, history.size()-17)];
                item = l1_cache_item::type_id::create("item");
                start_item(item);
                if (!item.randomize() with { rw == 1'b0; addr == old_a; })
                    `uvm_error(get_type_name(), "randomize() failed (evict recheck)")
                finish_item(item);
            end
        end

        `uvm_info(get_type_name(), "== Eviction sequence completed ==", UVM_LOW)
    endtask
endclass
