// axi_ram_dpi — exposes the AXI4-Full RAM to the SystemC model over DPI-C.
//
// Request/poll pattern: `axi_dpi_req()` only enqueues and returns, because an
// exported DPI function cannot consume simulation time — a Verilator
// restriction this split works around.
// The BFM advances inside the `always_ff` as the C++ side ticks the clock, and
// the C++ side polls `axi_dpi_done()`.
//
// Every beat is full width; partial coverage at the ends of a request is handled
// with WSTRB rather than by issuing narrow beats.

`timescale 1ns / 1ps

module axi_ram_dpi #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 64,
    parameter ID_WIDTH     = 4,
    parameter MEM_DEPTH    = 67108864,
    parameter READ_LATENCY = 1
) (
    input wire aclk,
    input wire aresetn
);

    `include "axi_ram_dpi.svh"

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int LANE_BITS      = $clog2(BYTES_PER_BEAT);

    // Duplicated as longint: without these, address arithmetic mixes 32- and
    // 64-bit operands and the lint fills up with WIDTHEXPAND.
    localparam longint BPB       = longint'(DATA_WIDTH / 8);
    localparam longint MAX_BEATS = 256;
    localparam longint BOUNDARY  = 4096;

    localparam [2:0] BURST_SIZE = LANE_BITS[2:0];
    localparam [1:0] BURST_INCR = 2'b01;

    logic [ID_WIDTH-1:0]       awid;
    logic [ADDR_WIDTH-1:0]     awaddr;
    logic [7:0]                awlen;
    logic [2:0]                awsize;
    logic [1:0]                awburst;
    logic                      awvalid;
    wire                       awready;

    logic [DATA_WIDTH-1:0]     wdata;
    logic [BYTES_PER_BEAT-1:0] wstrb;
    logic                      wlast;
    logic                      wvalid;
    wire                       wready;

    wire  [ID_WIDTH-1:0]       bid;
    wire  [1:0]                bresp;
    wire                       bvalid;
    logic                      bready;

    logic [ID_WIDTH-1:0]       arid;
    logic [ADDR_WIDTH-1:0]     araddr;
    logic [7:0]                arlen;
    logic [2:0]                arsize;
    logic [1:0]                arburst;
    logic                      arvalid;
    wire                       arready;

    wire  [ID_WIDTH-1:0]       rid;
    wire  [DATA_WIDTH-1:0]     rdata;
    wire  [1:0]                rresp;
    wire                       rlast;
    wire                       rvalid;
    logic                      rready;

    // Sequence-number handshake: DPI increments `req_seq`, the FSM copies it to
    // `ack_seq` when done. This way no variable has two writers, which the lint
    // would otherwise report as MULTIDRIVEN.
    int     req_seq = 0;
    int     req_cmd = 0;
    longint req_addr = 0;
    int     req_len = 0;

    int     ack_seq;
    int     ack_pending;
    int     req_resp;

    longint next_byte;    // first byte not transferred yet
    longint end_byte;     // last byte of the request, inclusive
    longint beat_base;    // aligned address of the beat in flight
    longint beats_left;

    function void axi_dpi_req(input int cmd, input longint addr, input int len);
        req_cmd  = cmd;
        req_addr = addr;
        req_len  = len;
        req_seq  = req_seq + 1;
    endfunction

    function int axi_dpi_done();
        return (req_seq == ack_seq) ? 1 : 0;
    endfunction

    function int axi_dpi_resp();
        return req_resp;
    endfunction

    // How many beats fit from `from` without running past the end of the
    // request, without crossing the 4 KB boundary, and without exceeding 256.
    function automatic longint beats_for_burst(input longint from, input longint last);
        longint aligned;
        longint boundary_end;
        longint burst_last;
        longint n;
        begin
            aligned      = from & ~(BPB - 1);
            boundary_end = (aligned & ~(BOUNDARY - 1)) + BOUNDARY - 1;
            burst_last   = (last < boundary_end) ? last : boundary_end;
            n            = (burst_last >> LANE_BITS) - (aligned >> LANE_BITS) + 1;
            return (n > MAX_BEATS) ? MAX_BEATS : n;
        end
    endfunction

    typedef enum logic [2:0] {
        S_IDLE, S_WR_ADDR, S_WR_DATA, S_WR_DATA_NEXT, S_WR_RESP,
        S_RD_ADDR, S_RD_DATA
    } state_t;

    state_t state;

    // A lane takes part when its byte falls inside the request. Unaligned ends
    // are covered by WSTRB.
    function automatic bit lane_in_range(input int lane);
        longint byte_addr;
        begin
            byte_addr = beat_base + longint'(lane);
            return (byte_addr >= next_byte && byte_addr <= end_byte);
        end
    endfunction

    // These two return values instead of writing wdata/wstrb directly, so the
    // always_ff assigns with `<=` only and blocking assignments never mix with
    // non-blocking ones on sequential signals (Verilator reports that as
    // BLKSEQ).
    function automatic logic [DATA_WIDTH-1:0] write_beat_data();
        logic [DATA_WIDTH-1:0] d;
        longint                byte_addr;
        begin
            d = '0;
            for (int lane = 0; lane < BYTES_PER_BEAT; lane++) begin
                if (lane_in_range(lane)) begin
                    byte_addr          = beat_base + longint'(lane);
                    d[lane*8 +: 8]     = axi_dpi_get_wbyte(int'(byte_addr - req_addr));
                end
            end
            return d;
        end
    endfunction

    function automatic logic [BYTES_PER_BEAT-1:0] write_beat_strb();
        logic [BYTES_PER_BEAT-1:0] s;
        begin
            s = '0;
            for (int lane = 0; lane < BYTES_PER_BEAT; lane++)
                s[lane] = lane_in_range(lane);
            return s;
        end
    endfunction

    function automatic void consume_read_beat(input logic [DATA_WIDTH-1:0] data);
        longint byte_addr;
        begin
            for (int lane = 0; lane < BYTES_PER_BEAT; lane++) begin
                if (lane_in_range(lane)) begin
                    byte_addr = beat_base + longint'(lane);
                    axi_dpi_put_rbyte(int'(byte_addr - req_addr), data[lane*8 +: 8]);
                end
            end
        end
    endfunction

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state       <= S_IDLE;
            awvalid     <= 1'b0;
            wvalid      <= 1'b0;
            bready      <= 1'b0;
            arvalid     <= 1'b0;
            rready      <= 1'b0;
            wlast       <= 1'b0;
            beats_left  <= 0;
            ack_seq     <= 0;
            ack_pending <= 0;
            req_resp    <= AXI_DPI_RESP_OKAY;
        end else begin
            case (state)

                S_IDLE: begin
                    if (req_seq != ack_seq) begin
                        ack_pending <= req_seq;
                        next_byte   <= req_addr;
                        end_byte    <= req_addr + longint'(req_len) - 1;
                        beat_base   <= req_addr & ~(BPB - 1);

                        if (req_len < 1 || req_len > AXI_DPI_MAX_BYTES) begin
                            // Outside the range the contract allows: reject it
                            // without touching the bus.
                            req_resp <= AXI_DPI_RESP_SLVERR;
                            ack_seq  <= req_seq;
                        end else if (req_cmd == AXI_DPI_CMD_WRITE) begin
                            req_resp <= AXI_DPI_RESP_OKAY;
                            state    <= S_WR_ADDR;
                        end else if (req_cmd == AXI_DPI_CMD_READ) begin
                            req_resp <= AXI_DPI_RESP_OKAY;
                            state    <= S_RD_ADDR;
                        end else begin
                            req_resp <= AXI_DPI_RESP_SLVERR;
                            ack_seq  <= req_seq;
                        end
                    end
                end

                S_WR_ADDR: begin
                    if (!awvalid) begin
                        beats_left <= beats_for_burst(next_byte, end_byte);
                        awid       <= '0;
                        awaddr     <= ADDR_WIDTH'(beat_base);
                        awlen      <= 8'(beats_for_burst(next_byte, end_byte) - 1);
                        awsize     <= BURST_SIZE;
                        awburst    <= BURST_INCR;
                        awvalid    <= 1'b1;
                    end else if (awready) begin
                        awvalid <= 1'b0;
                        wdata   <= write_beat_data();
                        wstrb   <= write_beat_strb();
                        wlast   <= (beats_left == 1);
                        wvalid  <= 1'b1;
                        state   <= S_WR_DATA;
                    end
                end

                S_WR_DATA: begin
                    if (wvalid && wready) begin
                        next_byte <= beat_base + BPB;
                        beat_base <= beat_base + BPB;

                        if (beats_left == 1) begin
                            wvalid <= 1'b0;
                            wlast  <= 1'b0;
                            bready <= 1'b1;
                            state  <= S_WR_RESP;
                        end else begin
                            beats_left <= beats_left - 1;
                            wlast      <= (beats_left == 2);
                            // write_beat_data/strb read next_byte and beat_base,
                            // which are non-blocking and have not updated yet,
                            // so the next beat is assembled one cycle later.
                            //
                            // wvalid MUST drop while it is assembled. Held high,
                            // the slave accepts another beat with stale wdata and
                            // consumes the burst faster than the master thinks:
                            // the slave drops wready when it finishes and the
                            // master waits forever.
                            wvalid     <= 1'b0;
                            state      <= S_WR_DATA_NEXT;
                        end
                    end
                end

                S_WR_DATA_NEXT: begin
                    wdata  <= write_beat_data();
                    wstrb  <= write_beat_strb();
                    wvalid <= 1'b1;
                    state  <= S_WR_DATA;
                end

                S_WR_RESP: begin
                    if (bvalid) begin
                        bready <= 1'b0;
                        if (bresp != 2'b00) req_resp <= AXI_DPI_RESP_SLVERR;

                        if (next_byte > end_byte) begin
                            ack_seq <= ack_pending;
                            state   <= S_IDLE;
                        end else begin
                            state <= S_WR_ADDR;
                        end
                    end
                end

                S_RD_ADDR: begin
                    if (!arvalid) begin
                        beats_left <= beats_for_burst(next_byte, end_byte);
                        arid       <= '0;
                        araddr     <= ADDR_WIDTH'(beat_base);
                        arlen      <= 8'(beats_for_burst(next_byte, end_byte) - 1);
                        arsize     <= BURST_SIZE;
                        arburst    <= BURST_INCR;
                        arvalid    <= 1'b1;
                    end else if (arready) begin
                        arvalid <= 1'b0;
                        rready  <= 1'b1;
                        state   <= S_RD_DATA;
                    end
                end

                S_RD_DATA: begin
                    if (rvalid && rready) begin
                        consume_read_beat(rdata);
                        if (rresp != 2'b00) req_resp <= AXI_DPI_RESP_SLVERR;

                        next_byte <= beat_base + BPB;
                        beat_base <= beat_base + BPB;

                        if (rlast) begin
                            rready <= 1'b0;
                            if (beat_base + BPB > end_byte) begin
                                ack_seq <= ack_pending;
                                state   <= S_IDLE;
                            end else begin
                                state <= S_RD_ADDR;
                            end
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    axi4_ram #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .ID_WIDTH     (ID_WIDTH),
        .MEM_DEPTH    (MEM_DEPTH),
        .READ_LATENCY (READ_LATENCY)
    ) u_ram (
        .aclk          (aclk),
        .aresetn       (aresetn),

        .s_axi_awid    (awid),
        .s_axi_awaddr  (awaddr),
        .s_axi_awlen   (awlen),
        .s_axi_awsize  (awsize),
        .s_axi_awburst (awburst),
        .s_axi_awvalid (awvalid),
        .s_axi_awready (awready),

        .s_axi_wdata   (wdata),
        .s_axi_wstrb   (wstrb),
        .s_axi_wlast   (wlast),
        .s_axi_wvalid  (wvalid),
        .s_axi_wready  (wready),

        .s_axi_bid     (bid),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid),
        .s_axi_bready  (bready),

        .s_axi_arid    (arid),
        .s_axi_araddr  (araddr),
        .s_axi_arlen   (arlen),
        .s_axi_arsize  (arsize),
        .s_axi_arburst (arburst),
        .s_axi_arvalid (arvalid),
        .s_axi_arready (arready),

        .s_axi_rid     (rid),
        .s_axi_rdata   (rdata),
        .s_axi_rresp   (rresp),
        .s_axi_rlast   (rlast),
        .s_axi_rvalid  (rvalid),
        .s_axi_rready  (rready)
    );

    wire _unused_ok = &{1'b0, bid, rid, 1'b0};

endmodule
