// axi4_coverage — functional coverage subscriber.
//
// `included from axi4_pkg.sv, after axi4_seq_item.sv.
//
// Owned by #11 (Epic #27). Only cg_burst (direction + length) exists today;
// see docs/PlanUVM.md for the full covergroup plan (AWSIZE, AWBURST, WSTRB,
// response codes, aligned vs. unaligned, and the length x size cross).

class axi4_coverage extends uvm_subscriber #(axi4_seq_item);

    `uvm_component_utils(axi4_coverage)

    bit          cp_is_write;
    int unsigned cp_beats;

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
    endgroup

    // TODO(#11): cross direction x length, plus covergroups for AWSIZE,
    // AWBURST, WSTRB, response codes, and aligned vs unaligned addresses.
    // Targets are in docs/PlanUVM.md.

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_burst = new();
    endfunction

    function void write(axi4_seq_item t);
        cp_is_write = t.is_write;
        cp_beats    = t.beats;
        cg_burst.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COV_SUMMARY",
            $sformatf("cg_burst coverage: %0.2f%%", cg_burst.get_coverage()),
            UVM_LOW)
    endfunction

endclass
