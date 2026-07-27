// -----------------------------------------------------------------------------
// files.f — filelist para xvlog (Vivado XSim)
// -----------------------------------------------------------------------------
// El ORDEN IMPORTA: xvlog compila secuencialmente y no resuelve dependencias
// hacia adelante. Las clases UVM se incluyen desde axi4_pkg.sv, no se listan
// aquí una por una.
//
// Uso:  xvlog -sv -L uvm -f src/tb/files.f
// -----------------------------------------------------------------------------

-i ../../src/tb/uvm

// ── DUT ──────────────────────────────────────────────────────────────────────
../../src/rtl/axi4_ram.v

// ── Interface (fuera del package: contiene señales, no puede ir adentro) ─────
../../src/tb/uvm/axi4_if.sv

// ── Paquete UVM: hace `include de seq_item, driver, monitor, sequencer,
//    agent, scoreboard, coverage, env, sequences y tests, en ese orden ────────
../../src/tb/uvm/axi4_pkg.sv

// ── Top del testbench ────────────────────────────────────────────────────────
../../src/tb/uvm/tb_top.sv
