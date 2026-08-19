`timescale 1ns/1ps


class l1_cache_b2b_seq extends l1_cache_base_seq;
    `uvm_object_utils(l1_cache_b2b_seq)

    function new(string name = "l1_cache_b2b_seq");
        super.new(name);
    endfunction

    virtual task body();
        l1_cache_item item;
        int           rounds = (cfg.num_trans / 4);

        `uvm_info(get_type_name(), $sformatf("== Back-to-back RAW sequence: %0d rounds ==", rounds), UVM_LOW)

        for (int r = 0; r < rounds; r++) begin
            bit [31:0] a;

            // 1. write
            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b1; addr[31:16] == 16'h0000; })
                `uvm_error(get_type_name(), "randomize() failed (b2b write)")
            a = item.addr;
            finish_item(item);

            // 2. read the same address immediately (RAW through the pipeline)
            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b0; addr == a; })
                `uvm_error(get_type_name(), "randomize() failed (b2b read)")
            finish_item(item);

            // 3. overwrite, then read again - back-to-back WAW followed by RAW
            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b1; addr == a; })
                `uvm_error(get_type_name(), "randomize() failed (b2b rewrite)")
            finish_item(item);

            item = l1_cache_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { rw == 1'b0; addr == a; })
                `uvm_error(get_type_name(), "randomize() failed (b2b reread)")
            finish_item(item);
        end

        `uvm_info(get_type_name(), "== Back-to-back RAW sequence completed ==", UVM_LOW)
    endtask
endclass
