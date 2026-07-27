// tb_top — testbench top level: clock, reset, DUT and interface.
//
// MEM_DEPTH is reduced to 64 KB on purpose: XSim cannot hold a 64 MB array.
// The SystemC co-simulation uses the 64 MB default instead.
//
// PLACEHOLDER (#9). Not verified — no Vivado on the machine this was written on.

`timescale 1ns / 1ps

module tb_top;

    import uvm_pkg::*;
    import axi4_pkg::*;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 64;
    localparam ID_WIDTH   = 4;
    localparam MEM_DEPTH  = 65536;

    localparam CLK_PERIOD = 10;

    logic aclk;
    logic aresetn;

    initial begin
        aclk = 1'b0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end

    initial begin
        aresetn = 1'b0;
        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
    end

    axi4_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) vif (
        .aclk    (aclk),
        .aresetn (aresetn)
    );

    axi4_ram #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .ID_WIDTH     (ID_WIDTH),
        .MEM_DEPTH    (MEM_DEPTH),
        .READ_LATENCY (1)
    ) dut (
        .aclk          (aclk),
        .aresetn       (aresetn),

        .s_axi_awid    (vif.awid),
        .s_axi_awaddr  (vif.awaddr),
        .s_axi_awlen   (vif.awlen),
        .s_axi_awsize  (vif.awsize),
        .s_axi_awburst (vif.awburst),
        .s_axi_awvalid (vif.awvalid),
        .s_axi_awready (vif.awready),

        .s_axi_wdata   (vif.wdata),
        .s_axi_wstrb   (vif.wstrb),
        .s_axi_wlast   (vif.wlast),
        .s_axi_wvalid  (vif.wvalid),
        .s_axi_wready  (vif.wready),

        .s_axi_bid     (vif.bid),
        .s_axi_bresp   (vif.bresp),
        .s_axi_bvalid  (vif.bvalid),
        .s_axi_bready  (vif.bready),

        .s_axi_arid    (vif.arid),
        .s_axi_araddr  (vif.araddr),
        .s_axi_arlen   (vif.arlen),
        .s_axi_arsize  (vif.arsize),
        .s_axi_arburst (vif.arburst),
        .s_axi_arvalid (vif.arvalid),
        .s_axi_arready (vif.arready),

        .s_axi_rid     (vif.rid),
        .s_axi_rdata   (vif.rdata),
        .s_axi_rresp   (vif.rresp),
        .s_axi_rlast   (vif.rlast),
        .s_axi_rvalid  (vif.rvalid),
        .s_axi_rready  (vif.rready)
    );

    initial begin
        uvm_config_db #(virtual axi4_if)::set(null, "*", "vif", vif);
        run_test();
    end

    // Cut the simulation short if a test hangs waiting on a handshake.
    initial begin
        #1ms;
        `uvm_fatal("TIMEOUT", "testbench exceeded 1 ms of simulated time")
    end

endmodule
