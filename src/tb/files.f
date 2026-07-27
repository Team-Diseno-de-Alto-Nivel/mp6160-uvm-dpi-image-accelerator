// -----------------------------------------------------------------------------
// files.f — filelist for xvlog (Vivado XSim)
// -----------------------------------------------------------------------------
// ORDER MATTERS: xvlog compiles sequentially and does not resolve forward
// dependencies. The interface has to come before the package that references it,
// and the package before the top that imports it.
//
// Usage:  xvlog -sv -L uvm -f src/tb/files.f
// -----------------------------------------------------------------------------

-i ../../src/tb/uvm

// ── DUT ──────────────────────────────────────────────────────────────────────
../../src/rtl/axi4_ram.v

// ── Interface. Outside the package: it holds signals, so it cannot live in one.
../../src/tb/uvm/axi4_if.sv

// ── UVM package: sequence item, driver, monitor, agent, scoreboard, coverage,
//    environment, sequences and tests, all in one file.
../../src/tb/uvm/axi4_pkg.sv

// ── Testbench top ────────────────────────────────────────────────────────────
../../src/tb/uvm/tb_top.sv
