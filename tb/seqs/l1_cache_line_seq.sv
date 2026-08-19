`timescale 1ns/1ps

// ============================================================================
// Spatial-locality sequence - targets the multi-word line.
//
// Touch one word of a line (a miss that fetches all four words), then walk the
// other three. Those must all HIT, which is only true if the burst fill wrote
// every beat into the right word slot. A single-word fill, or beats landing in
// the wrong order, shows up here immediately.
//
// Then rewrite the whole line word by word and force it out, so the write-back
// carries four freshly written words in the correct order.
// ============================================================================
class l1_cache_line_seq extends l1_cache_base_seq;
    `uvm_object_utils(l1_cache_line_seq)

    function new(string name = "l1_cache_line_seq");
        super.new(name);
    endfunction

    virtual task body();
        l1_cache_item item;
        int           rounds = (cfg.num_trans / 12);

        `uvm_info(get_type_name(), $sformatf("== Line/spatial sequence: %0d rounds ==", rounds), UVM_LOW)

        for (int r = 0; r < rounds; r++) begin
            // Declare and assign separately - a declaration initialiser inside
            // a loop body is not guaranteed to re-evaluate per iteration.
            tag_t      tg;
            set_t      st;
            bit [31:0] base;
            int        first;

            tg    = tag_t'($urandom_range(0, 255));
            st    = set_t'($urandom_range(0, SETS-1));
            base  = make_line_addr(tg, st);
            first = $urandom_range(0, WORDS_PER_LINE-1);

            // 1. Cold-touch one word: misses, fetches the whole line.
            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b0; addr == base + (first * 4); })
                `uvm_error(get_type_name(), "randomize() failed (line probe)")
            finish_item(item);

            // 2. Walk the rest of the line - every one of these must hit.
            for (int w = 0; w < WORDS_PER_LINE; w++) begin
                if (w == first) continue;
                item = l1_cache_item::type_id::create("item");
                start_item(item);
                if (!item.randomize() with { rw == 1'b0; addr == base + (w * 4); })
                    `uvm_error(get_type_name(), "randomize() failed (line walk)")
                finish_item(item);
            end

            // 3. Rewrite every word, so the line is fully dirty.
            for (int w = 0; w < WORDS_PER_LINE; w++) begin
                item = l1_cache_item::type_id::create("item");
                start_item(item);
                if (!item.randomize() with { rw == 1'b1; addr == base + (w * 4); be == 4'b1111; })
                    `uvm_error(get_type_name(), "randomize() failed (line write)")
                finish_item(item);
            end

            // 4. Read them all back before the line is displaced.
            for (int w = 0; w < WORDS_PER_LINE; w++) begin
                item = l1_cache_item::type_id::create("item");
                start_item(item);
                if (!item.randomize() with { rw == 1'b0; addr == base + (w * 4); })
                    `uvm_error(get_type_name(), "randomize() failed (line verify)")
                finish_item(item);
            end
        end

        `uvm_info(get_type_name(), "== Line/spatial sequence completed ==", UVM_LOW)
    endtask
endclass
