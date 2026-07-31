// axi4_pkg — the whole UVM environment for axi4_ram, assembled from the
// per-class files in this directory.
//
// Split out of a single-file skeleton (#9). Each `include below is one class
// (or a couple of tightly related ones); the include order is load-bearing —
// xvlog compiles sequentially and does not resolve forward references, so a
// file may only reference names `included above it:
//   seq_item  -> driver, monitor, scoreboard, sequences (everyone uses it)
//   driver, monitor, sequencer -> agent
//   agent, scoreboard, coverage -> env
//   sequences -> tests
//
// files.f still only lists this one file: `-i src/tb/uvm` already points
// xvlog at this directory for `include resolution, so files.f does not need
// touching when adding a new class file — just add the `include line below,
// in the right position.
//
// What actually works: smoke_test drives a real write and read back, checked
// by the scoreboard. The other four tests are placeholders that emit a
// UVM_WARNING naming what is missing and finish without error — visible in
// the log, but not counted as a failure, since the run scripts only look at
// UVM_ERROR/UVM_FATAL. Verified against Vivado 2024.1 on 2026-07-27 (README
// asks for 2019.2 — not available to test against here).
//
// Targets Vivado XSim, which ships UVM 1.2 (not IEEE 1800.2): no register
// layer, no advanced factory usage.

`timescale 1ns/1ps

`ifndef AXI4_PKG_SV
`define AXI4_PKG_SV

package axi4_pkg;

    import uvm_pkg::*;
`include "uvm_macros.svh"

    localparam BYTES_PER_BEAT = 8;
    localparam BURST_SIZE     = 3;       // log2(BYTES_PER_BEAT)
    localparam BURST_INCR     = 2'b01;

    // Owned by #9 (Epic #24).
    `include "axi4_seq_item.sv"
    `include "axi4_driver.sv"
    `include "axi4_monitor.sv"
    `include "axi4_sequencer.sv"
    `include "axi4_agent.sv"

    // Owned by #10 (Epic #24).
    `include "axi4_scoreboard.sv"

    // Owned by #11 (Epic #27).
    `include "axi4_coverage.sv"

    // Owned by #9 (Epic #24) — ties the pieces above together.
    `include "axi4_env.sv"

    // Owned by #12 (Epic #27).
    `include "axi4_sequences.sv"
    `include "axi4_test.sv"

endpackage

`endif  // AXI4_PKG_SV
