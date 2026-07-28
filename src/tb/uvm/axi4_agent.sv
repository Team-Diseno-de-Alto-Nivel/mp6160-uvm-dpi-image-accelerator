// axi4_agent — always-active master agent: the DUT is the AXI slave, so the
// testbench is the one generating transactions.
//
// `included from axi4_pkg.sv, after axi4_driver.sv, axi4_monitor.sv and
// axi4_sequencer.sv.

class axi4_agent extends uvm_agent;

    `uvm_component_utils(axi4_agent)

    axi4_sequencer sequencer;
    axi4_driver    driver;
    axi4_monitor   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = axi4_monitor::type_id::create("monitor", this);
        // Always active: the DUT is the slave, the testbench is the master.
        sequencer = axi4_sequencer::type_id::create("sequencer", this);
        driver    = axi4_driver::type_id::create("driver", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
