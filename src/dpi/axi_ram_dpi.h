#pragma once

// -----------------------------------------------------------------------------
// Contrato DPI-C entre el modelo SystemC y la RAM AXI4-Full en Verilog (T3.1)
// -----------------------------------------------------------------------------
// CONTRATO CONGELADO. Los integrantes 1 (RTL), 2 (UVM) y 3 (DPI) trabajan
// contra estas cinco funciones. No cambiarlas sin avisar al equipo.
//
// Dirección de las llamadas:
//
//   SystemC (C++)                          SystemVerilog (src/dpi/axi_ram_dpi.sv)
//   ─────────────                          ──────────────────────────────────────
//   axi_dpi_req()      ──── export ────►   encola la petición
//   axi_dpi_done()     ──── export ────►   ¿terminó?
//   axi_dpi_resp()     ──── export ────►   respuesta AXI (BRESP/RRESP)
//   axi_dpi_get_wbyte()◄─── import ────    el BFM pide el byte a escribir
//   axi_dpi_put_rbyte()◄─── import ────    el BFM entrega el byte leído
//
// Por qué este patrón request/poll y no una tarea DPI bloqueante:
// Verilator NO permite que una función DPI exportada consuma tiempo de
// simulación. Entonces `axi_dpi_req` solo encola y retorna; el AXI master BFM
// avanza en un `always_ff` a medida que el lado C++ hace tick del reloj, y el
// lado C++ sondea `axi_dpi_done()`. Este patrón también funciona en Vivado
// XSim y en Questa, así que el wrapper es portable.
// -----------------------------------------------------------------------------

#include <cstdint>

// ── Comandos aceptados por axi_dpi_req ───────────────────────────────────────
#define AXI_DPI_CMD_READ  0
#define AXI_DPI_CMD_WRITE 1

// ── Códigos de respuesta devueltos por axi_dpi_resp ──────────────────────────
#define AXI_DPI_RESP_OKAY   0
#define AXI_DPI_RESP_SLVERR 2

// Tamaño máximo de una petición. El BFM parte lo que exceda un burst AXI
// (256 beats) en ráfagas sucesivas, pero el buffer de intercambio es finito.
#define AXI_DPI_MAX_BYTES (1024 * 1024)

extern "C" {

// ── Exportadas desde SystemVerilog, las llama el C++ ─────────────────────────

/// Encola una petición. No consume tiempo de simulación: retorna de inmediato.
/// @param cmd   AXI_DPI_CMD_READ o AXI_DPI_CMD_WRITE
/// @param addr  dirección byte, relativa a la base de la RAM (0-based)
/// @param len   cantidad de bytes; debe ser 1..AXI_DPI_MAX_BYTES
void axi_dpi_req(int cmd, long long addr, int len);

/// @return 1 cuando la última petición encolada terminó, 0 mientras corre.
int axi_dpi_done();

/// @return AXI_DPI_RESP_OKAY o AXI_DPI_RESP_SLVERR de la última petición.
///         Solo es válido cuando axi_dpi_done() devuelve 1.
int axi_dpi_resp();

// ── Importadas por SystemVerilog, las implementa el C++ ──────────────────────
// (definidas en src/dpi/axi_ram_dpi.cpp — T3.3)

/// El BFM pide el byte número `idx` del buffer de escritura.
unsigned char axi_dpi_get_wbyte(int idx);

/// El BFM entrega el byte número `idx` leído de la RAM.
void axi_dpi_put_rbyte(int idx, unsigned char val);

}  // extern "C"

// -----------------------------------------------------------------------------
// API que consume el SC_MODULE RamAxi (src/model/modules/ram_axi/) — T3.4
// -----------------------------------------------------------------------------
namespace axi_dpi {

/// Instancia el modelo Verilated y lo mantiene en reset unos ciclos.
/// Debe llamarse una sola vez, antes de la primera transacción.
void init();

/// Avanza el reloj del modelo Verilated medio período (un flanco).
/// El SC_MODULE la llama en bucle intercalando `wait()` para que el tiempo
/// simulado de SystemC avance junto con el del RTL.
void tick();

/// Libera el modelo Verilated. Llamar al final de la simulación.
void shutdown();

/// Copia `len` bytes al buffer de escritura antes de lanzar un WRITE.
void load_write_buffer(const unsigned char* src, int len);

/// Copia `len` bytes del buffer de lectura después de que un READ terminó.
void store_read_buffer(unsigned char* dst, int len);

}  // namespace axi_dpi
