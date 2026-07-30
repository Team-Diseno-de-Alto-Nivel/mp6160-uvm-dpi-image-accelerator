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
    localparam ADDR_LSB       = $clog2(BYTES_PER_BEAT);   // bits needed for a lane index

    // =========================================================================
    // Implemented: FIXED/INCR/WRAP bursts, narrow transfers (AWSIZE/ARSIZE
    // below the bus width) resolved to the correct byte lanes, per-byte WSTRB
    // gating at every width, WLAST/RLAST, SLVERR for out-of-range addresses,
    // configurable READ_LATENCY, up to 256 beats per burst, and independent
    // VALID/READY handshakes on every channel.
    // =========================================================================

    reg [7:0] mem [0:MEM_DEPTH-1];

    reg beat_err;

    // ── Write path ───────────────────────────────────────────────────────────
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [8:0]            wr_beats;
    reg [ID_WIDTH-1:0]   wr_id;
    reg [1:0]            wr_burst;
    reg [2:0]            wr_size;
    reg [ADDR_WIDTH-1:0] wr_wrap_base;
    reg [ADDR_WIDTH-1:0] wr_wrap_len;
    reg                  wr_busy;
    reg                  wr_err;
    reg                  bvalid_r;
    reg [1:0]            bresp_r;

    // AWREADY only when no burst is in flight and no response is pending. It
    // does not depend on AWVALID in the same cycle, which is the classic source
    // of deadlock here.
    assign s_axi_awready = ~wr_busy & ~bvalid_r;
    assign s_axi_wready  = wr_busy;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bid     = wr_id;
    assign s_axi_bresp   = bresp_r;

    // Bytes covered by one beat of the in-flight write burst, and where that
    // window starts inside the DATA_WIDTH bus. Both derived from state that is
    // stable for the whole beat (wr_addr/wr_size only change at beat/burst
    // boundaries), so there is no combinational hazard against the clocked
    // updates below. Kept full ADDR_WIDTH so every downstream use (compared
    // and added against wr_addr / the loop index) is a same-width operation.
    wire [ADDR_WIDTH-1:0] wr_beat_bytes = ({{(ADDR_WIDTH-1){1'b0}}, 1'b1}) <<< wr_size;
    wire [ADDR_WIDTH-1:0] wr_lane_off   = wr_addr & {{(ADDR_WIDTH-ADDR_LSB){1'b0}}, {ADDR_LSB{1'b1}}};
    wire [ADDR_WIDTH-1:0] wr_bus_base   = wr_addr - wr_lane_off;

    // Total bytes and aligned wrap boundary for a WRAP burst, computed from the
    // incoming AW signals directly — the registers below do not hold the new
    // burst's values until the cycle after AWREADY is sampled high.
    wire [ADDR_WIDTH-1:0] aw_burst_bytes =
        ({{(ADDR_WIDTH-9){1'b0}}, ({1'b0, s_axi_awlen} + 9'd1)}) <<< s_axi_awsize;
    wire [ADDR_WIDTH-1:0] aw_wrap_base = s_axi_awaddr & ~(aw_burst_bytes - 1'b1);

    // Next address for the write burst: FIXED (and the reserved 2'b11 code,
    // held defensively like FIXED) never advances; INCR/WRAP advance by one
    // beat's worth of bytes, and WRAP additionally folds back to its aligned
    // base once the next address would leave the burst's wrap window.
    wire [ADDR_WIDTH-1:0] wr_next_addr =
        (wr_burst == BURST_INCR || wr_burst == BURST_WRAP)
            ? ( (wr_burst == BURST_WRAP &&
                 (wr_addr + wr_beat_bytes) >= (wr_wrap_base + wr_wrap_len))
                    ? wr_wrap_base
                    : wr_addr + wr_beat_bytes )
            : wr_addr;

    // Writes one beat's active lanes to memory, gated by WSTRB. Mirrors
    // load_beat below; using a task (instead of an inline loop with a
    // blocking scratch variable) keeps the write-data always-block free of
    // blocking assignments to sequential state.
    task automatic store_beat;
        input  [ADDR_WIDTH-1:0] base;
        input  [ADDR_WIDTH-1:0] lane_off;
        input  [ADDR_WIDTH-1:0] beat_bytes;
        output                  err;
        integer m;
        begin
            err = 1'b0;
            for (m = 0; m < BYTES_PER_BEAT; m = m + 1) begin
                if ((m >= lane_off) && (m < lane_off + beat_bytes) && s_axi_wstrb[m]) begin
                    if ((base + m) < MEM_DEPTH)
                        mem[base + m] <= s_axi_wdata[m*8 +: 8];
                    else
                        err = 1'b1;
                end
            end
        end
    endtask

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_busy      <= 1'b0;
            bvalid_r     <= 1'b0;
            bresp_r      <= RESP_OKAY;
            wr_addr      <= {ADDR_WIDTH{1'b0}};
            wr_beats     <= 9'd0;
            wr_id        <= {ID_WIDTH{1'b0}};
            wr_burst     <= BURST_FIXED;
            wr_size      <= 3'd0;
            wr_wrap_base <= {ADDR_WIDTH{1'b0}};
            wr_wrap_len  <= {ADDR_WIDTH{1'b0}};
            wr_err       <= 1'b0;
        end else begin
            // Accept the address of a new burst.
            if (s_axi_awvalid && s_axi_awready) begin
                wr_addr      <= s_axi_awaddr;
                wr_beats     <= {1'b0, s_axi_awlen} + 9'd1;
                wr_id        <= s_axi_awid;
                wr_burst     <= s_axi_awburst;
                wr_size      <= s_axi_awsize;
                wr_wrap_base <= aw_wrap_base;
                wr_wrap_len  <= aw_burst_bytes;
                wr_busy      <= 1'b1;
                wr_err       <= 1'b0;
            end

            // One data beat.
            if (wr_busy && s_axi_wvalid && s_axi_wready) begin
                store_beat(wr_bus_base, wr_lane_off, wr_beat_bytes, beat_err);

                if (s_axi_wlast || wr_beats == 9'd1) begin
                    wr_busy  <= 1'b0;
                    bvalid_r <= 1'b1;
                    bresp_r  <= (wr_err || beat_err) ? RESP_SLVERR : RESP_OKAY;
                end else begin
                    wr_err   <= wr_err | beat_err;
                    wr_addr  <= wr_next_addr;
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
    reg [1:0]             rd_burst;
    reg [2:0]             rd_size;
    reg [ADDR_WIDTH-1:0]  rd_wrap_base;
    reg [ADDR_WIDTH-1:0]  rd_wrap_len;
    reg                   rvalid_r;
    reg                   rlast_r;
    reg [DATA_WIDTH-1:0]  rdata_r;
    reg [1:0]             rresp_r;
    reg                   rd_pending;   // AR accepted, still waiting out READ_LATENCY
    reg [31:0]            rd_wait_cnt;
    reg                   beat_err_rd;

    assign s_axi_arready = ~rvalid_r & ~rd_pending;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rlast   = rlast_r;
    assign s_axi_rid     = rd_id;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = rresp_r;

    // Lane geometry for the in-flight read burst (registers, valid from the
    // second beat onward and for the first beat whenever READ_LATENCY > 1).
    // Kept full ADDR_WIDTH, same reasoning as wr_beat_bytes/wr_lane_off above.
    wire [ADDR_WIDTH-1:0] rd_beat_bytes = ({{(ADDR_WIDTH-1){1'b0}}, 1'b1}) <<< rd_size;
    wire [ADDR_WIDTH-1:0] rd_lane_off   = rd_addr & {{(ADDR_WIDTH-ADDR_LSB){1'b0}}, {ADDR_LSB{1'b1}}};
    wire [ADDR_WIDTH-1:0] rd_bus_base   = rd_addr - rd_lane_off;

    wire [ADDR_WIDTH-1:0] rd_next_addr =
        (rd_burst == BURST_INCR || rd_burst == BURST_WRAP)
            ? ( (rd_burst == BURST_WRAP &&
                 (rd_addr + rd_beat_bytes) >= (rd_wrap_base + rd_wrap_len))
                    ? rd_wrap_base
                    : rd_addr + rd_beat_bytes )
            : rd_addr;

    // Same geometry, but derived straight from the incoming AR signals — used
    // only for the very first beat when READ_LATENCY <= 1, because the
    // registers above are not updated until the cycle after AR is accepted.
    wire [ADDR_WIDTH-1:0] ar_beat_bytes  = ({{(ADDR_WIDTH-1){1'b0}}, 1'b1}) <<< s_axi_arsize;
    wire [ADDR_WIDTH-1:0] ar_lane_off    = s_axi_araddr & {{(ADDR_WIDTH-ADDR_LSB){1'b0}}, {ADDR_LSB{1'b1}}};
    wire [ADDR_WIDTH-1:0] ar_bus_base    = s_axi_araddr - ar_lane_off;
    wire [ADDR_WIDTH-1:0] ar_burst_bytes =
        ({{(ADDR_WIDTH-9){1'b0}}, ({1'b0, s_axi_arlen} + 9'd1)}) <<< s_axi_arsize;
    wire [ADDR_WIDTH-1:0] ar_wrap_base   = s_axi_araddr & ~(ar_burst_bytes - 1'b1);
    wire [ADDR_WIDTH-1:0] ar_next_addr =
        (s_axi_arburst == BURST_INCR || s_axi_arburst == BURST_WRAP)
            ? ( (s_axi_arburst == BURST_WRAP &&
                 (s_axi_araddr + ar_beat_bytes) >= (ar_wrap_base + ar_burst_bytes))
                    ? ar_wrap_base
                    : s_axi_araddr + ar_beat_bytes )
            : s_axi_araddr;

    // Reads one beat's active lanes from memory. Lanes outside
    // [lane_off, lane_off + beat_bytes) — the ones a narrow transfer does not
    // cover — and any in-range-but-out-of-MEM_DEPTH byte read back as zero;
    // `err` reports whether any accessed byte fell outside MEM_DEPTH.
    task automatic load_beat;
        input  [ADDR_WIDTH-1:0] base;
        input  [ADDR_WIDTH-1:0] lane_off;
        input  [ADDR_WIDTH-1:0] beat_bytes;
        output                  err;
        integer k;
        begin
            err = 1'b0;
            for (k = 0; k < BYTES_PER_BEAT; k = k + 1) begin
                if ((k >= lane_off) && (k < lane_off + beat_bytes)) begin
                    if ((base + k) < MEM_DEPTH) begin
                        rdata_r[k*8 +: 8] <= mem[base + k];
                    end else begin
                        rdata_r[k*8 +: 8] <= 8'h00;
                        err = 1'b1;
                    end
                end else begin
                    rdata_r[k*8 +: 8] <= 8'h00;
                end
            end
        end
    endtask

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rvalid_r     <= 1'b0;
            rlast_r      <= 1'b0;
            rd_addr      <= {ADDR_WIDTH{1'b0}};
            rd_beats     <= 9'd0;
            rd_id        <= {ID_WIDTH{1'b0}};
            rd_burst     <= BURST_FIXED;
            rd_size      <= 3'd0;
            rd_wrap_base <= {ADDR_WIDTH{1'b0}};
            rd_wrap_len  <= {ADDR_WIDTH{1'b0}};
            rdata_r      <= {DATA_WIDTH{1'b0}};
            rresp_r      <= RESP_OKAY;
            rd_pending   <= 1'b0;
            rd_wait_cnt  <= 32'd0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                rd_id        <= s_axi_arid;
                rd_burst     <= s_axi_arburst;
                rd_size      <= s_axi_arsize;
                rd_beats     <= {1'b0, s_axi_arlen} + 9'd1;
                rd_wrap_base <= ar_wrap_base;
                rd_wrap_len  <= ar_burst_bytes;

                if (READ_LATENCY <= 1) begin
                    // First beat available on the next cycle — identical
                    // timing to before READ_LATENCY was configurable.
                    load_beat(ar_bus_base, ar_lane_off, ar_beat_bytes, beat_err_rd);
                    rd_addr    <= ar_next_addr;
                    rvalid_r   <= 1'b1;
                    rlast_r    <= (s_axi_arlen == 8'd0);
                    rresp_r    <= beat_err_rd ? RESP_SLVERR : RESP_OKAY;
                    rd_pending <= 1'b0;
                end else begin
                    rd_addr     <= s_axi_araddr;
                    rd_pending  <= 1'b1;
                    rd_wait_cnt <= READ_LATENCY - 1;
                end
            end else if (rd_pending) begin
                if (rd_wait_cnt == 32'd0) begin
                    load_beat(rd_bus_base, rd_lane_off, rd_beat_bytes, beat_err_rd);
                    rd_addr    <= rd_next_addr;
                    rvalid_r   <= 1'b1;
                    rlast_r    <= (rd_beats == 9'd1);
                    rresp_r    <= beat_err_rd ? RESP_SLVERR : RESP_OKAY;
                    rd_pending <= 1'b0;
                end else begin
                    rd_wait_cnt <= rd_wait_cnt - 32'd1;
                end
            end else if (rvalid_r && s_axi_rready) begin
                if (rd_beats <= 9'd1) begin
                    rvalid_r <= 1'b0;
                    rlast_r  <= 1'b0;
                end else begin
                    load_beat(rd_bus_base, rd_lane_off, rd_beat_bytes, beat_err_rd);
                    rd_addr  <= rd_next_addr;
                    rd_beats <= rd_beats - 9'd1;
                    rlast_r  <= (rd_beats == 9'd2);
                    rresp_r  <= beat_err_rd ? RESP_SLVERR : RESP_OKAY;
                end
            end
        end
    end

endmodule
