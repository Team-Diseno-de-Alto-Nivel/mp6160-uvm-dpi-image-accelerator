// axi4_if — AXI4-Full interface connecting the testbench to axi4_ram.
//
// Signal names match the DUT's without the `s_axi_` prefix, which is added when
// instantiating in tb_top.
//
// PLACEHOLDER (#9). Written in full but NOT verified: nobody has run this
// through Vivado yet. Run scripts/run_uvm.sh before trusting it.

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

    // TODO(#9): add clocking blocks and modports (driver/monitor/DUT). Left out
    // deliberately: XSim is picky about clocking blocks in parameterised
    // interfaces, and this skeleton has not been elaborated yet.

endinterface

`endif  // AXI4_IF_SV
