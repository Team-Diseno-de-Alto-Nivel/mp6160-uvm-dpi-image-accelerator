// axi4_sequences — stimulus sequences.
//
// `included from axi4_pkg.sv, after axi4_seq_item.sv.
//
// Owned by #12 (Epic #27). Only axi4_smoke_seq exists today; the rest are
// the remaining scope of #12.

virtual class axi4_base_seq extends uvm_sequence #(axi4_seq_item);

    function new(string name = "axi4_base_seq");
        super.new(name);
    endfunction

    task write_burst(input bit [31:0] addr, input int unsigned beats);
        axi4_seq_item item;
        item          = axi4_seq_item::type_id::create("wr");
        item.is_write = 1'b1;
        item.addr     = addr;
        item.beats    = beats;
        item.burst    = BURST_INCR;
        item.size     = BURST_SIZE;
        for (int i = 0; i < beats * BYTES_PER_BEAT; i++)
            item.data.push_back($urandom_range(0, 255));
        start_item(item);
        finish_item(item);
    endtask

    task read_burst(input bit [31:0] addr, input int unsigned beats);
        axi4_seq_item item;
        item          = axi4_seq_item::type_id::create("rd");
        item.is_write = 1'b0;
        item.addr     = addr;
        item.beats    = beats;
        item.burst    = BURST_INCR;
        item.size     = BURST_SIZE;
        start_item(item);
        finish_item(item);
    endtask

endclass

// Write then read back. The scoreboard does the comparison.
class axi4_smoke_seq extends axi4_base_seq;

    `uvm_object_utils(axi4_smoke_seq)

    function new(string name = "axi4_smoke_seq");
        super.new(name);
    endfunction

    task body();
        `uvm_info("SMOKE", "single-beat write then read back", UVM_LOW)
        write_burst(32'h0000_0000, 1);
        read_burst(32'h0000_0000, 1);

        `uvm_info("SMOKE", "four-beat burst write then read back", UVM_LOW)
        write_burst(32'h0000_0100, 4);
        read_burst(32'h0000_0100, 4);
    endtask

endclass

// TODO(#12): axi4_burst_seq  — INCR of 1/2/16/256 beats, FIXED, back-to-back
// TODO(#12): axi4_narrow_seq — AWSIZE below the bus width, partial WSTRB
// TODO(#12): axi4_error_seq  — addresses past MEM_DEPTH, expecting SLVERR
// TODO(#12): axi4_random_seq — constrained random stimulus
