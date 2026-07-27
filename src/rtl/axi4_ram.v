// -----------------------------------------------------------------------------
// axi4_ram — RAM byte-addressable con puerto AXI4-Full (esclavo)
// -----------------------------------------------------------------------------
// INTERFAZ CONGELADA (T1.1). El testbench UVM (src/tb/uvm/) y el wrapper DPI
// (src/dpi/axi_ram_dpi.sv) se escriben contra esta lista de puertos, así que
// NO cambiarla sin avisar a los integrantes 2 y 3.
//
// La implementación del cuerpo es T1.2–T1.4 (integrante 1). Ver el plan y
// docs/ArquitecturaDPI.md.
//
// Verilog-2001 sintetizable a propósito: debe elaborar tanto en Verilator
// (co-simulación con SystemC) como en Vivado XSim (testbench UVM), y los dos
// no aceptan el mismo subconjunto de SystemVerilog.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module axi4_ram #(
    parameter ADDR_WIDTH   = 32,          // ancho del bus de direcciones
    parameter DATA_WIDTH   = 64,          // ancho del bus de datos (múltiplo de 8)
    parameter ID_WIDTH     = 4,           // ancho de los IDs de transacción
    parameter MEM_DEPTH    = 67108864,    // tamaño en BYTES. 64 MB en co-simulación,
                                          // bajarlo a 65536 en el TB UVM (XSim no
                                          // aguanta 64 MB)
    parameter READ_LATENCY = 1            // ciclos de latencia de lectura (≥ 1)
) (
    input  wire                      aclk,
    input  wire                      aresetn,   // reset activo en bajo

    // ── Canal de dirección de escritura (AW) ─────────────────────────────────
    input  wire [ID_WIDTH-1:0]       s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [7:0]                s_axi_awlen,     // beats - 1 (0..255)
    input  wire [2:0]                s_axi_awsize,    // log2(bytes por beat)
    input  wire [1:0]                s_axi_awburst,   // 00=FIXED 01=INCR 10=WRAP
    input  wire                      s_axi_awvalid,
    output wire                      s_axi_awready,

    // ── Canal de datos de escritura (W) ──────────────────────────────────────
    input  wire [DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,     // byte enables
    input  wire                      s_axi_wlast,
    input  wire                      s_axi_wvalid,
    output wire                      s_axi_wready,

    // ── Canal de respuesta de escritura (B) ──────────────────────────────────
    output wire [ID_WIDTH-1:0]       s_axi_bid,
    output wire [1:0]                s_axi_bresp,     // 00=OKAY 10=SLVERR
    output wire                      s_axi_bvalid,
    input  wire                      s_axi_bready,

    // ── Canal de dirección de lectura (AR) ───────────────────────────────────
    input  wire [ID_WIDTH-1:0]       s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [7:0]                s_axi_arlen,
    input  wire [2:0]                s_axi_arsize,
    input  wire [1:0]                s_axi_arburst,
    input  wire                      s_axi_arvalid,
    output wire                      s_axi_arready,

    // ── Canal de datos de lectura (R) ────────────────────────────────────────
    output wire [ID_WIDTH-1:0]       s_axi_rid,
    output wire [DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                s_axi_rresp,
    output wire                      s_axi_rlast,
    output wire                      s_axi_rvalid,
    input  wire                      s_axi_rready
);

    // Señales AXI4 que un esclavo de memoria simple acepta pero ignora.
    // Se declaran para que la interfaz sea AXI4-Full compliant y el TB pueda
    // manejarlas, pero no afectan el comportamiento.
    //   awlock/arlock, awcache/arcache, awprot/arprot, awqos/arqos
    // Si el integrante 1 las necesita, agregarlas aquí y avisar a 2 y 3.

    // ── Constantes de respuesta AXI ──────────────────────────────────────────
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // ── Constantes de tipo de ráfaga ─────────────────────────────────────────
    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;

    // -------------------------------------------------------------------------
    // TODO(integrante 1) — T1.2 a T1.4
    //
    //   T1.2  Memoria byte-addressable `reg [7:0] mem [0:MEM_DEPTH-1]`,
    //         escritura respetando WSTRB, ráfagas INCR y FIXED (WRAP si da
    //         tiempo), AWLEN/ARLEN hasta 256 beats, AWSIZE/ARSIZE para
    //         transferencias angostas, RLAST en el último beat, y SLVERR
    //         cuando la dirección se sale de MEM_DEPTH.
    //   T1.3  Handshakes VALID/READY independientes por canal. Cuidado con
    //         generar READY combinacionalmente a partir de VALID en el mismo
    //         ciclo: es la fuente clásica de deadlock aquí.
    //   T1.4  Aplicar READ_LATENCY en el camino de lectura.
    //
    // Criterio de aceptación (T1.5):
    //   $ verilator --lint-only -Wall src/rtl/axi4_ram.v   → sin warnings
    //   $ xvlog src/rtl/axi4_ram.v                         → elabora limpio
    //
    // OJO: ninguna línea de comentario puede EMPEZAR con la palabra que nombra
    // a la herramienta de lint. Cuando esa palabra es el primer token después
    // de `//`, se interpreta como metacomentario (una directiva), y el parseo
    // aborta si la directiva no existe. Por eso el `$` de las dos líneas de
    // arriba.
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // BORRAR AL IMPLEMENTAR (T1.2)
    // -------------------------------------------------------------------------
    // Este bloque existe únicamente para que el lint pase mientras el cuerpo
    // del módulo está vacío: fija las salidas a un valor definido y declara de
    // forma explícita que las entradas todavía no se usan. Sin esto, -Wall
    // reporta cada puerto como no usado y el check de CI queda en rojo.
    //
    // Al implementar el módulo, borrar TODO lo que sigue hasta `endmodule`.
    // -------------------------------------------------------------------------
    assign s_axi_awready = 1'b0;
    assign s_axi_wready  = 1'b0;
    assign s_axi_bid     = {ID_WIDTH{1'b0}};
    assign s_axi_bresp   = RESP_OKAY;
    assign s_axi_bvalid  = 1'b0;
    assign s_axi_arready = 1'b0;
    assign s_axi_rid     = {ID_WIDTH{1'b0}};
    assign s_axi_rdata   = {DATA_WIDTH{1'b0}};
    assign s_axi_rresp   = RESP_OKAY;
    assign s_axi_rlast   = 1'b0;
    assign s_axi_rvalid  = 1'b0;

    // Idioma estándar para "estas señales están conectadas a propósito pero
    // todavía no se leen". El resultado no se usa; sólo silencia UNUSEDSIGNAL.
    wire _unused_ok = &{1'b0,
                        aclk, aresetn,
                        s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize,
                        s_axi_awburst, s_axi_awvalid,
                        s_axi_wdata, s_axi_wstrb, s_axi_wlast, s_axi_wvalid,
                        s_axi_bready,
                        s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize,
                        s_axi_arburst, s_axi_arvalid,
                        s_axi_rready,
                        RESP_SLVERR, BURST_FIXED, BURST_INCR, BURST_WRAP,
                        MEM_DEPTH[0], READ_LATENCY[0],
                        1'b0};

endmodule
