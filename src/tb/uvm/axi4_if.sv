// axi4_if — AXI4-Full interface connecting the testbench to axi4_ram.
//
// Signal names match the DUT's without the `s_axi_` prefix, which is added when
// instantiating in tb_top.
//
// driver_cb / monitor_cb below drive and sample through clocking blocks,
// direction always from the testbench's point of view. Verified against
// Vivado 2024.1 (2026-07-27): all six tests still pass — the parameterised
// interface did not trip up XSim's clocking block support here.
`timescale 1ns/1ps

`ifndef AXI4_IF_SV
`define AXI4_IF_SV

interface axi4_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 4
) (
    input logic aclk,
    input logic aresetn
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Write address channel
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awvalid;
    logic                  awready;

    // Write data channel
    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wlast;
    logic                  wvalid;
    logic                  wready;

    // Write response channel
    logic [ID_WIDTH-1:0]   bid;
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready;

    // Read address channel
    logic [ID_WIDTH-1:0]   arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arvalid;
    logic                  arready;

    // Read data channel
    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic                  rvalid;
    logic                  rready;

    // Clocking blocks: direction is always from the testbench's point of
    // view. driver_cb drives stimulus and samples handshake responses;
    // monitor_cb only samples — it never drives anything.
    clocking driver_cb @(posedge aclk);
        output awid, awaddr, awlen, awsize, awburst, awvalid;
        input  awready;
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        input  bid, bresp, bvalid;
        output bready;
        output arid, araddr, arlen, arsize, arburst, arvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    clocking monitor_cb @(posedge aclk);
        input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    modport driver_mp  (clocking driver_cb,  input aclk, aresetn);
    modport monitor_mp (clocking monitor_cb, input aclk, aresetn);

endinterface

`endif  // AXI4_IF_SV
