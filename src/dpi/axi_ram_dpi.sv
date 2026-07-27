// axi_ram_dpi — expone la RAM AXI4-Full al modelo SystemC vía DPI-C.
//
// Patrón request/poll: `axi_dpi_req()` sólo encola y retorna, porque Verilator
// no permite que una función DPI exportada consuma tiempo de simulación. El BFM
// avanza en el `always_ff` a medida que el C++ hace tick del reloj, y el C++
// sondea `axi_dpi_done()`.
//
// Todos los beats son de ancho completo; la cobertura parcial en los extremos
// se resuelve con WSTRB en vez de emitir beats angostos.

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

    // Duplicados en longint: sin esto la aritmética de direcciones mezcla
    // 32 y 64 bits y el lint se llena de WIDTHEXPAND.
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

    // Handshake por número de secuencia: el DPI incrementa `req_seq`, la FSM
    // copia a `ack_seq` al terminar. Así ninguna variable tiene dos escritores,
    // que es lo que Verilator reporta como MULTIDRIVEN.
    int     req_seq = 0;
    int     req_cmd = 0;
    longint req_addr = 0;
    int     req_len = 0;

    int     ack_seq;
    int     ack_pending;
    int     req_resp;

    longint next_byte;    // primer byte todavía no transferido
    longint end_byte;     // último byte de la petición, inclusive
    longint beat_base;    // dirección alineada del beat en curso
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

    // Beats que caben desde `from` sin pasar el final de la petición, sin cruzar
    // el límite de 4 KB y sin exceder 256 beats.
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

    // Un carril del beat participa si su byte cae dentro de la petición. Los
    // extremos no alineados quedan cubiertos por WSTRB.
    function automatic bit lane_in_range(input int lane);
        longint byte_addr;
        begin
            byte_addr = beat_base + longint'(lane);
            return (byte_addr >= next_byte && byte_addr <= end_byte);
        end
    endfunction

    // Estas dos devuelven valores en vez de escribir wdata/wstrb directamente:
    // así el always_ff asigna sólo con `<=` y no se mezcla bloqueante con no
    // bloqueante sobre señales secuenciales (Verilator lo reporta como BLKSEQ).
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
                            // Fuera del rango que el contrato permite: se
                            // rechaza sin tocar el bus.
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
                            // write_beat_data/strb leen next_byte y beat_base,
                            // que son NBA y todavía no se actualizaron: el beat
                            // siguiente se arma un ciclo después.
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
