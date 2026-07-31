// axi4_coverage   functional coverage subscriber.
//
// `included from axi4_pkg.sv, after axi4_seq_item.sv.
//
// Owned by #11 (Epic #27). Only cg_burst (direction + length) exists today;
// see docs/PlanUVM.md for the full covergroup plan (AWSIZE, AWBURST, WSTRB,
// response codes, aligned vs. unaligned, and the length x size cross).
//------------------------------------------------------------------------------
// axi4_coverage   functional coverage subscriber.
//
// Receives completed AXI transactions from the monitor through an analysis
// export and samples functional coverage.
//
// Current implementation covers:
//
//     transaction direction
//     burst length
//     direction   length
//     AXI response
//     WSTRB patterns
//


class axi4_coverage extends uvm_subscriber #(axi4_seq_item);

    `uvm_component_utils(axi4_coverage)

    bit          cp_is_write;
    int unsigned cp_beats;

    bit [1:0]    cp_resp;
    bit [7:0]    cp_wstrb;

    covergroup cg_burst;
        option.per_instance = 1;

        direction: coverpoint cp_is_write {
            bins write = {1};
            bins read  = {0};
        }

        length: coverpoint cp_beats {
            bins single    = {1};
            bins short_len = {[2:15]};
            bins mid_len   = {[16:63]};  // "medium" collides with an XSim reserved word
            bins long_len  = {[64:255]};
            bins maximum   = {256};
        }
        direction_x_length : cross direction,length;
    endgroup


    //------------------------------------------------------------
    // Response coverage
    //------------------------------------------------------------

    covergroup cg_resp;
        option.per_instance = 1;
        response : coverpoint cp_resp {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};

        }

    endgroup;


    // TODO(#11): cross direction x length, plus covergroups for AWSIZE,
    // AWBURST, WSTRB, response codes, and aligned vs unaligned addresses.
    // Targets are in docs/PlanUVM.md.

    //------------------------------------------------------------
    // Write strobe coverage
    //
    // The current RTL only generates full-width writes (8'hFF).
    // Future versions can extend this with partial strobes.
    //------------------------------------------------------------

    covergroup cg_wstrb;

        option.per_instance = 1;
        strobe : coverpoint cp_wstrb {
            bins full = {8'hFF};
            // Future:
            //
            // bins lower_half = {8'h0F};
            // bins upper_half = {8'hF0};
            // bins single[]   = {8'h01,8'h02,...};

        }

    endgroup;


    //------------------------------------------------------------
    // Constructor
    //------------------------------------------------------------

    function new(string name, uvm_component parent);

        super.new(name,parent);
        cg_burst = new();
        cg_resp  = new();
        cg_wstrb = new();

    endfunction

   //------------------------------------------------------------
    // Sample one completed transaction
    //------------------------------------------------------------

    function void write(axi4_seq_item t);

        cp_is_write = t.is_write;
        cp_beats    = t.beats;
        cp_resp     = t.resp;

        //--------------------------------------------------------
        // Burst coverage
        //--------------------------------------------------------

        cg_burst.sample();

        //--------------------------------------------------------
        // Response coverage
        //--------------------------------------------------------

        cg_resp.sample();

        //--------------------------------------------------------
        // WSTRB coverage
        //
        // Only meaningful on write transactions.
        //--------------------------------------------------------

        if (t.is_write) begin

            cp_wstrb = '0;

            for (int lane = 0;
                 lane < BYTES_PER_BEAT && lane < t.strb.size();
                 lane++) begin

                cp_wstrb[lane] = t.strb[lane];

            end

            cg_wstrb.sample();

        end

    endfunction


    //------------------------------------------------------------
    // Coverage summary
    //------------------------------------------------------------

    function void report_phase(uvm_phase phase);

        super.report_phase(phase);

`uvm_info(
        "COV_SUMMARY",
        $sformatf("\n----------------------------------------\nFunctional Coverage Summary\n----------------------------------------\ncg_burst : %0.2f %%\ncg_resp  : %0.2f %%\ncg_wstrb : %0.2f %%\n----------------------------------------",
            cg_burst.get_coverage(),
            cg_resp.get_coverage(),
            cg_wstrb.get_coverage()
        ),
        UVM_LOW
	);
    endfunction

endclass
