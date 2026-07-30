// axi4_sequences — stimulus sequences.
//
// `included from axi4_pkg.sv, after axi4_seq_item.sv.
//
// Owned by #12 (Epic #27). Only axi4_smoke_seq exists today; the rest are
// the remaining scope of #12.
//------------------------------------------------------------------------------
// axi4_base_seq
//
// Provides helper tasks for generating AXI transactions. The current driver
// supports:
//
//   • INCR bursts
//   • Full-width transfers
//   • 1–16 beats
//
// Future sequences (narrow/error/FIXED) can override the default values by
// modifying the seq_item before finish_item().
//
//------------------------------------------------------------------------------


virtual class axi4_base_seq extends uvm_sequence #(axi4_seq_item);

    function new(string name = "axi4_base_seq");
        super.new(name);
    endfunction

    //----------------------------------------------------------------------
    // Fill a transaction with random payload bytes.
    //----------------------------------------------------------------------

    protected function void fill_random_payload(ref axi4_seq_item item);

        item.data.delete();
        item.strb.delete();

        for (int i = 0; i < item.beats * BYTES_PER_BEAT; i++) begin
            item.data.push_back($urandom_range(0,255));
            item.strb.push_back(1'b1);
        end

    endfunction

    //----------------------------------------------------------------------
    // Helper: write burst
    //----------------------------------------------------------------------

    task write_burst
    (
        input bit [31:0] addr,
        input int unsigned beats
    );

        axi4_seq_item item;
        item = axi4_seq_item::type_id::create("wr");
        item.is_write = 1'b1;
        item.addr     = addr;
        item.beats    = beats;
        // Current RTL subset.
        item.burst    = BURST_INCR;
        item.size     = BURST_SIZE;
        fill_random_payload(item);
        start_item(item);
        finish_item(item);

    endtask

    //----------------------------------------------------------------------
    // Helper: read burst
    //----------------------------------------------------------------------


    task read_burst
    (
        input bit [31:0] addr,
        input int unsigned beats
    );
        axi4_seq_item item;
        item = axi4_seq_item::type_id::create("rd");
        item.is_write = 1'b0;
        item.addr     = addr;
        item.beats    = beats;
        item.burst    = BURST_INCR;
        item.size     = BURST_SIZE;
        item.data.delete();
        item.strb.delete();
        start_item(item);
        finish_item(item);

    endtask

endclass


// Write then read back. The scoreboard does the comparison.
//------------------------------------------------------------------------------
// axi4_smoke_seq
//
// Basic sanity sequence.
//
//------------------------------------------------------------------------------
class axi4_smoke_seq extends axi4_base_seq;

    `uvm_object_utils(axi4_smoke_seq)

    function new(string name = "axi4_smoke_seq");
        super.new(name);
    endfunction

    task body();
        `uvm_info(get_type_name(),
                  "Single-beat write/read",
                  UVM_LOW)
        write_burst(32'h0000_0000,1);
        read_burst(32'h0000_0000,1);
        `uvm_info(get_type_name(),
                  "Four-beat write/read",
                  UVM_LOW)
        write_burst(32'h0000_0100,4);
        read_burst(32'h0000_0100,4);
    endtask

endclass



//------------------------------------------------------------------------------
// axi4_burst_seq
//
// Exercises different INCR burst lengths supported by the current RTL.
//
// The DUT currently supports:
//
//   • INCR bursts only
//   • Full-width transfers
//   • 1–16 beats
//
// The sequence also generates back-to-back transactions to stress the AXI
// handshakes without inserting idle cycles.
//
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// axi4_burst_seq
//
// Exercises different INCR burst lengths supported by the current RTL.
//------------------------------------------------------------------------------

class axi4_burst_seq extends axi4_base_seq;

    `uvm_object_utils(axi4_burst_seq)

    function new(string name="axi4_burst_seq");
        super.new(name);
    endfunction

    task body();

        bit [31:0] addr;
        int unsigned burst_lengths[$] = '{1,2,4,8,16};

        addr = 32'h0000_1000;

        //------------------------------------------------------------------
        // Exercise every supported burst length.
        //------------------------------------------------------------------

        foreach (burst_lengths[i]) begin

            `uvm_info(get_type_name(),
                $sformatf("Testing %0d-beat INCR burst",
                          burst_lengths[i]),
                UVM_LOW)

            write_burst(addr, burst_lengths[i]);
            read_burst (addr, burst_lengths[i]);

            addr += 32'h100;

        end

        //------------------------------------------------------------------
        // Back-to-back writes
        //------------------------------------------------------------------

        `uvm_info(get_type_name(),
                  "Back-to-back write bursts",
                  UVM_LOW)

        repeat (5) begin
            write_burst(addr,4);
            addr += 32'h100;
        end

        //------------------------------------------------------------------
        // Back-to-back reads
        //------------------------------------------------------------------

        `uvm_info(get_type_name(),
                  "Back-to-back read bursts",
                  UVM_LOW)

        repeat (5) begin
            read_burst(addr,4);
            addr += 32'h100;
        end

    endtask

endclass

//------------------------------------------------------------------------------
// axi4_narrow_seq
//
// Placeholder.
//
// The current RTL only supports full-width transfers (AWSIZE = BURST_SIZE).
// Once narrow transfers are implemented, this sequence will generate smaller
// transfer sizes together with partial WSTRB patterns.
//------------------------------------------------------------------------------

class axi4_narrow_seq extends axi4_base_seq;

    `uvm_object_utils(axi4_narrow_seq)

    function new(string name = "axi4_narrow_seq");
        super.new(name);
    endfunction

    task body();

        `uvm_info(get_type_name(),
                  "Current RTL supports only full-width accesses",
                  UVM_LOW)

        // Exercise a legal transaction so the infrastructure
        // (driver/monitor/scoreboard/coverage) is still executed.

        write_read_burst(32'h0000_2000,4);

    endtask

endclass


//------------------------------------------------------------------------------
// axi4_error_seq
//
// Placeholder.
//
// The RTL currently returns OKAY for every access. Once address checking is
// implemented, this sequence should disable the address constraint and issue
// accesses beyond MEM_DEPTH, expecting SLVERR responses.
//------------------------------------------------------------------------------

class axi4_error_seq extends axi4_base_seq;

    `uvm_object_utils(axi4_error_seq)

    function new(string name = "axi4_error_seq");
        super.new(name);
    endfunction

    task body();

        `uvm_info(get_type_name(),
                  "Current RTL does not implement SLVERR responses",
                  UVM_LOW)

        write_read_burst(32'h0000_3000,2);

    endtask

endclass


//------------------------------------------------------------------------------
// axi4_random_seq
//
// Generates constrained-random traffic inside the subset currently supported
// by the RTL.
//
//  • aligned addresses
//  • INCR bursts
//  • full-width transfers
//  • 1–16 beats
//------------------------------------------------------------------------------

class axi4_random_seq extends axi4_base_seq;

    `uvm_object_utils(axi4_random_seq)

    function new(string name = "axi4_random_seq");
        super.new(name);
    endfunction

    task body();

        bit [31:0] addr;
        int unsigned beats;

        repeat (100) begin

            beats = $urandom_range(1,16);

            // Generate an aligned address inside the current 64 KB model.

            addr = $urandom_range(0,16'hFFF8);

            addr[2:0] = 3'b000;

            if ($urandom_range(0,1))
                write_burst(addr,beats);
            else
                read_burst(addr,beats);

        end

    endtask

endclass


// TODO(#12): axi4_burst_seq  — INCR of 1/2/16/256 beats, FIXED, back-to-back
// TODO(#12): axi4_narrow_seq — AWSIZE below the bus width, partial WSTRB
// TODO(#12): axi4_error_seq  — addresses past MEM_DEPTH, expecting SLVERR
// TODO(#12): axi4_random_seq — constrained random stimulus
