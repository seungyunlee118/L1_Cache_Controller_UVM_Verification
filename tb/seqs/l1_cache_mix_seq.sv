`timescale 1ns/1ps

// ============================================================================
// Main random sequence: mixed reads and writes over a small tag pool.
//
// The pool holds 8 tags competing for 64 sets of 4 ways, so every set sees
// twice as many tags as it has ways - conflict misses and dirty evictions
// happen constantly instead of the cache simply warming up and staying warm.
//
// Reads are aimed at addresses already written, so every read is a meaningful
// data check rather than a cold fetch.
// ============================================================================
class l1_cache_mix_seq extends l1_cache_base_seq;
    `uvm_object_utils(l1_cache_mix_seq)

    tag_t tag_pool[8];

    function new(string name = "l1_cache_mix_seq");
        super.new(name);
        foreach (tag_pool[i]) tag_pool[i] = tag_t'(i * 32'h0011_1111);
    endfunction

    virtual task body();
        l1_cache_item item;
        bit [31:0]    written_addrs[$];
        int           n = cfg.num_trans;

        `uvm_info(get_type_name(), $sformatf("== Mixed R/W sequence: %0d transactions ==", n), UVM_LOW)

        for (int i = 0; i < n; i++) begin
            item = l1_cache_item::type_id::create("item");
            start_item(item);

            if (written_addrs.size() == 0 || $urandom_range(0, 1) == 1) begin
                // WRITE somewhere in the thrashing pool.
                if (!item.randomize() with {
                        rw == 1'b1;
                        addr[ADDR_WIDTH-1 -: TAG_BITS] inside {tag_pool};
                    })
                    `uvm_error(get_type_name(), "randomize() failed (write)")
            end
            else begin
                // READ an address we have already written.
                // Declare and assign separately - see l1_cache_line_seq.
                bit [31:0] target;
                target = written_addrs[$urandom_range(0, written_addrs.size()-1)];
                if (!item.randomize() with {
                        rw   == 1'b0;
                        addr == target;
                    })
                    `uvm_error(get_type_name(), "randomize() failed (read)")
            end

            if (item.rw == 1'b1) written_addrs.push_back(item.addr);

            finish_item(item);
        end

        `uvm_info(get_type_name(), "== Mixed R/W sequence completed ==", UVM_LOW)
    endtask
endclass
