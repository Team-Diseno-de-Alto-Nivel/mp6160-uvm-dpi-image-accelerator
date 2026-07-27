// -----------------------------------------------------------------------------
// axi4_ram — byte-addressable RAM with an AXI4-Full slave port
// -----------------------------------------------------------------------------
// FROZEN INTERFACE. The UVM testbench (src/tb/uvm/) and the DPI wrapper
// (src/dpi/axi_ram_dpi.sv) are both written against this port list, so do not
// change it without telling the team.
//
// Synthesizable Verilog-2001 on purpose: this must elaborate in both Verilator
// (SystemC co-simulation) and Vivado XSim (UVM testbench), and the two do not
// accept the same SystemVerilog subset.
//
// See docs/ArquitecturaDPI.md for the port map and the DPI contract.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module axi4_ram #(
    parameter ADDR_WIDTH   = 32,          // address bus width
    parameter DATA_WIDTH   = 64,          // data bus width, multiple of 8
    parameter ID_WIDTH     = 4,           // transaction ID width
    parameter MEM_DEPTH    = 67108864,    // size in BYTES. 64 MB for co-simulation;
                                          // drop to 65536 in the UVM testbench,
                                          // XSim cannot hold 64 MB
    parameter READ_LATENCY = 1            // read latency in cycles (>= 1)
) (
    input  wire                      aclk,
    input  wire                      aresetn,   // active-low reset

    // ── Write address channel (AW) ───────────────────────────────────────────
    input  wire [ID_WIDTH-1:0]       s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [7:0]                s_axi_awlen,     // beats - 1 (0..255)
    input  wire [2:0]                s_axi_awsize,    // log2(bytes per beat)
    input  wire [1:0]                s_axi_awburst,   // 00=FIXED 01=INCR 10=WRAP
    input  wire                      s_axi_awvalid,
    output wire                      s_axi_awready,

    // ── Write data channel (W) ───────────────────────────────────────────────
    input  wire [DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,     // byte enables
    input  wire                      s_axi_wlast,
    input  wire                      s_axi_wvalid,
    output wire                      s_axi_wready,

    // ── Write response channel (B) ───────────────────────────────────────────
    output wire [ID_WIDTH-1:0]       s_axi_bid,
    output wire [1:0]                s_axi_bresp,     // 00=OKAY 10=SLVERR
    output wire                      s_axi_bvalid,
    input  wire                      s_axi_bready,

    // ── Read address channel (AR) ────────────────────────────────────────────
    input  wire [ID_WIDTH-1:0]       s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [7:0]                s_axi_arlen,
    input  wire [2:0]                s_axi_arsize,
    input  wire [1:0]                s_axi_arburst,
    input  wire                      s_axi_arvalid,
    output wire                      s_axi_arready,

    // ── Read data channel (R) ────────────────────────────────────────────────
    output wire [ID_WIDTH-1:0]       s_axi_rid,
    output wire [DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                s_axi_rresp,
    output wire                      s_axi_rlast,
    output wire                      s_axi_rvalid,
    input  wire                      s_axi_rready
);

    // AXI4 sidebands a simple memory slave accepts but ignores: awlock/arlock,
    // awcache/arcache, awprot/arprot, awqos/arqos. They are not declared here;
    // add them if a master ever needs them, and tell the team first.

    // ── AXI response codes ───────────────────────────────────────────────────
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // ── Burst type encoding ──────────────────────────────────────────────────
    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;


    localparam BYTES_PER_BEAT = DATA_WIDTH / 8;

    // =========================================================================
    // PARTIAL IMPLEMENTATION — see #6 and #7
    // =========================================================================
    // Covers exactly the AXI4 subset the BFM in src/dpi/axi_ram_dpi.sv drives,
    // so that the SystemC co-simulation runs and the rtl-equivalence CI job can
    // validate the DPI integration end to end.
    //
    // Implemented: INCR bursts, full-width beats, per-byte WSTRB, WLAST/RLAST,
    //              up to 256 beats per burst, and independent VALID/READY
    //              handshakes on every channel.
    //
    // TODO(#6): FIXED and WRAP bursts — the address always increments today.
    // TODO(#6): narrow transfers — AWSIZE/ARSIZE are ignored and full width is
    //           assumed. A master requesting narrow beats would read or write
    //           the wrong lanes.
    // TODO(#6): answer SLVERR when the address falls outside MEM_DEPTH. Today an
    //           out-of-range access is silently dropped and answered OKAY.
    // TODO(#7): make READ_LATENCY configurable — latency is fixed at one cycle.
    //
    // The UVM testbench (#9-#12) is what should catch these gaps: they are
    // precisely what burst_test, narrow_test and error_test are meant to cover.
    // =========================================================================

    reg [7:0] mem [0:MEM_DEPTH-1];

    integer i;

    // ── Write path ───────────────────────────────────────────────────────────
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [8:0]            wr_beats;
    reg [ID_WIDTH-1:0]   wr_id;
    reg                  wr_busy;
    reg                  bvalid_r;

    // AWREADY only when no burst is in flight and no response is pending. It
    // does not depend on AWVALID in the same cycle, which is the classic source
    // of deadlock here.
    assign s_axi_awready = ~wr_busy & ~bvalid_r;
    assign s_axi_wready  = wr_busy;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bid     = wr_id;
    assign s_axi_bresp   = RESP_OKAY;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_busy  <= 1'b0;
            bvalid_r <= 1'b0;
            wr_addr  <= {ADDR_WIDTH{1'b0}};
            wr_beats <= 9'd0;
            wr_id    <= {ID_WIDTH{1'b0}};
        end else begin
            // Accept the address of a new burst.
            if (s_axi_awvalid && s_axi_awready) begin
                wr_addr  <= s_axi_awaddr & ~(BYTES_PER_BEAT - 1);
                wr_beats <= {1'b0, s_axi_awlen} + 9'd1;
                wr_id    <= s_axi_awid;
                wr_busy  <= 1'b1;
            end

            // One data beat.
            if (wr_busy && s_axi_wvalid && s_axi_wready) begin
                for (i = 0; i < BYTES_PER_BEAT; i = i + 1) begin
                    if (s_axi_wstrb[i] && ((wr_addr + i) < MEM_DEPTH))
                        mem[wr_addr + i] <= s_axi_wdata[i*8 +: 8];
                end

                if (s_axi_wlast || wr_beats == 9'd1) begin
                    wr_busy  <= 1'b0;
                    bvalid_r <= 1'b1;
                end else begin
                    wr_addr  <= wr_addr + BYTES_PER_BEAT;
                    wr_beats <= wr_beats - 9'd1;
                end
            end

            // Retire the response once the master accepts it.
            if (bvalid_r && s_axi_bready)
                bvalid_r <= 1'b0;
        end
    end

    // ── Read path ────────────────────────────────────────────────────────────
    reg [ADDR_WIDTH-1:0]  rd_addr;
    reg [8:0]             rd_beats;
    reg [ID_WIDTH-1:0]    rd_id;
    reg                   rvalid_r;
    reg                   rlast_r;
    reg [DATA_WIDTH-1:0]  rdata_r;

    assign s_axi_arready = ~rvalid_r;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rlast   = rlast_r;
    assign s_axi_rid     = rd_id;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = RESP_OKAY;

    // Reads one full beat from memory starting at `base`. Out-of-range bytes
    // read back as zero.
    task automatic load_beat;
        input [ADDR_WIDTH-1:0] base;
        integer k;
        begin
            for (k = 0; k < BYTES_PER_BEAT; k = k + 1) begin
                if ((base + k) < MEM_DEPTH)
                    rdata_r[k*8 +: 8] <= mem[base + k];
                else
                    rdata_r[k*8 +: 8] <= 8'h00;
            end
        end
    endtask

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rvalid_r <= 1'b0;
            rlast_r  <= 1'b0;
            rd_addr  <= {ADDR_WIDTH{1'b0}};
            rd_beats <= 9'd0;
            rd_id    <= {ID_WIDTH{1'b0}};
            rdata_r  <= {DATA_WIDTH{1'b0}};
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                // First beat available on the next cycle: READ_LATENCY = 1.
                load_beat(s_axi_araddr & ~(BYTES_PER_BEAT - 1));
                rd_addr  <= (s_axi_araddr & ~(BYTES_PER_BEAT - 1)) + BYTES_PER_BEAT;
                rd_beats <= {1'b0, s_axi_arlen} + 9'd1;
                rd_id    <= s_axi_arid;
                rvalid_r <= 1'b1;
                rlast_r  <= (s_axi_arlen == 8'd0);
            end else if (rvalid_r && s_axi_rready) begin
                if (rd_beats <= 9'd1) begin
                    rvalid_r <= 1'b0;
                    rlast_r  <= 1'b0;
                end else begin
                    load_beat(rd_addr);
                    rd_addr  <= rd_addr + BYTES_PER_BEAT;
                    rd_beats <= rd_beats - 9'd1;
                    rlast_r  <= (rd_beats == 9'd2);
                end
            end
        end
    end

    // Signals and parameters this implementation accepts but does not interpret
    // yet. As the TODOs above get closed, drop whatever starts being used from
    // this list.
    wire _unused_ok = &{1'b0,
                        s_axi_awsize, s_axi_awburst,
                        s_axi_arsize, s_axi_arburst,
                        RESP_SLVERR, BURST_FIXED, BURST_INCR, BURST_WRAP,
                        READ_LATENCY[0],
                        1'b0};

endmodule
