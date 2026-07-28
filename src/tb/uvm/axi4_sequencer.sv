// axi4_sequencer — sequencer for axi4_seq_item. A typedef is enough; UVM's
// built-in uvm_sequencer needs no AXI-specific behaviour.
//
// `included from axi4_pkg.sv, after axi4_seq_item.sv and before axi4_agent.sv.

typedef uvm_sequencer #(axi4_seq_item) axi4_sequencer;
