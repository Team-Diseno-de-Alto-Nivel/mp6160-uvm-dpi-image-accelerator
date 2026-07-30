// axi4_test — UVM tests.
//
// `included from axi4_pkg.sv, after axi4_env.sv and axi4_sequences.sv.
//
// These names are hardcoded in scripts/run_uvm.sh and
// scripts/run_uvm_windows.ps1. Do not rename without updating both.
//
// Owned by #12 (Epic #27). smoke_test is the only one with real stimulus;
// the rest are placeholders that emit a UVM_WARNING and finish without
// error — visible in the log, but not counted as a failure, since the run
// scripts only look at UVM_ERROR/UVM_FATAL.

class axi4_base_test extends uvm_test;

    `uvm_component_utils(axi4_base_test)

    axi4_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi4_env::type_id::create("env", this);
    endfunction

    function void report_phase(uvm_phase phase);
        uvm_report_server svr = uvm_report_server::get_server();
        super.report_phase(phase);
        if (svr.get_severity_count(UVM_ERROR) == 0 &&
            svr.get_severity_count(UVM_FATAL) == 0)
            `uvm_info("RESULT", "TEST PASSED", UVM_NONE)
        else
            `uvm_info("RESULT", "TEST FAILED", UVM_NONE)
    endfunction

endclass

// The only test with real stimulus.
class smoke_test extends axi4_base_test;

    `uvm_component_utils(smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi4_smoke_seq seq;
        phase.raise_objection(this);
        seq = axi4_smoke_seq::type_id::create("seq");
        seq.start(env.agent.sequencer);
        #200ns;
        phase.drop_objection(this);
    endtask

endclass

// Placeholders. Each says exactly what it is missing. When implementing,
// drop the UVM_WARNING and start the corresponding sequence.

class burst_test extends axi4_base_test;
    `uvm_component_utils(burst_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        axi4_burst_seq seq;
        phase.raise_objection(this);
        seq = axi4_burst_seq::type_id::create("seq");
        seq.start(env.agent.sequencer);
        #200ns;
        phase.drop_objection(this);
    endtask
endclass

class narrow_test extends axi4_base_test;
    `uvm_component_utils(narrow_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        axi4_narrow_seq seq;
        phase.raise_objection(this);
        seq = axi4_narrow_seq::type_id::create("seq");
        seq.start(env.agent.sequencer);
        #200ns;
        phase.drop_objection(this);
    endtask
endclass

class error_test extends axi4_base_test;
    `uvm_component_utils(error_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        axi4_error_seq seq;
        phase.raise_objection(this);
        seq = axi4_error_seq::type_id::create("seq");
        seq.start(env.agent.sequencer);
        #200ns;
        phase.drop_objection(this);
    endtask
endclass

class random_test extends axi4_base_test;
    `uvm_component_utils(random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        axi4_random_seq seq;
        phase.raise_objection(this);
        seq = axi4_random_seq::type_id::create("seq");
        seq.start(env.agent.sequencer);
        #500ns;
        phase.drop_objection(this);
    endtask
endclass
