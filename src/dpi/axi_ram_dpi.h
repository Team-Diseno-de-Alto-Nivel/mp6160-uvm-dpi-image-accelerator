#pragma once

// -----------------------------------------------------------------------------
// DPI-C contract between the SystemC model and the Verilog AXI4-Full RAM
// -----------------------------------------------------------------------------
// FROZEN CONTRACT. The RTL, the UVM testbench and the DPI bridge are all written
// against these five functions. Do not change them without telling the team.
//
// Call directions:
//
//   SystemC (C++)                          SystemVerilog (src/dpi/axi_ram_dpi.sv)
//   ─────────────                          ──────────────────────────────────────
//   axi_dpi_req()      ──── export ────►   enqueue the request
//   axi_dpi_done()     ──── export ────►   has it finished?
//   axi_dpi_resp()     ──── export ────►   AXI response (BRESP/RRESP)
//   axi_dpi_get_wbyte()◄─── import ────    BFM asks for a byte to write
//   axi_dpi_put_rbyte()◄─── import ────    BFM hands back a byte it read
//
// Why request/poll instead of a blocking DPI task:
// Verilator does NOT allow an exported DPI function to consume simulation time.
// So `axi_dpi_req` only enqueues and returns; the AXI master BFM advances inside
// an `always_ff` as the C++ side ticks the clock, and the C++ side polls
// `axi_dpi_done()`. The same pattern works in Vivado XSim and Questa, which
// keeps the wrapper portable.
// -----------------------------------------------------------------------------

#include <cstdint>

// ── Commands accepted by axi_dpi_req ─────────────────────────────────────────
#define AXI_DPI_CMD_READ  0
#define AXI_DPI_CMD_WRITE 1

// ── Response codes returned by axi_dpi_resp ──────────────────────────────────
#define AXI_DPI_RESP_OKAY   0
#define AXI_DPI_RESP_SLVERR 2

// Largest request the bridge accepts. The BFM splits anything longer than one
// AXI burst (256 beats) into successive bursts, but the exchange buffer is
// finite, so RamAxi chunks larger TLM payloads above this layer.
#define AXI_DPI_MAX_BYTES (1024 * 1024)

extern "C" {

// ── Exported from SystemVerilog, called by the C++ side ──────────────────────

/// Enqueues a request. Does not consume simulation time: returns immediately.
/// @param cmd   AXI_DPI_CMD_READ or AXI_DPI_CMD_WRITE
/// @param addr  byte address, relative to the RAM base (0-based)
/// @param len   byte count; must be 1..AXI_DPI_MAX_BYTES
void axi_dpi_req(int cmd, long long addr, int len);

/// @return 1 once the enqueued request has finished, 0 while it runs.
int axi_dpi_done();

/// @return AXI_DPI_RESP_OKAY or AXI_DPI_RESP_SLVERR for the last request.
///         Only valid once axi_dpi_done() returns 1.
int axi_dpi_resp();

// ── Imported by SystemVerilog, implemented by the C++ side ───────────────────
// (defined in src/dpi/axi_ram_dpi.cpp)

/// The BFM asks for byte `idx` of the write buffer.
unsigned char axi_dpi_get_wbyte(int idx);

/// The BFM hands back byte `idx` read from the RAM.
void axi_dpi_put_rbyte(int idx, unsigned char val);

}  // extern "C"

// -----------------------------------------------------------------------------
// API consumed by the RamAxi SC_MODULE (src/model/modules/ram_axi/)
// -----------------------------------------------------------------------------
namespace axi_dpi {

/// Instantiates the Verilated model and holds it in reset for a few cycles.
/// Must be called exactly once, before the first transaction.
void init();

/// Advances the Verilated model's clock by half a period (one edge).
/// RamAxi calls this in a loop interleaved with `wait()` so that SystemC's
/// simulated time advances alongside the RTL's.
void tick();

/// Releases the Verilated model. Call at the end of the simulation.
void shutdown();

/// Copies `len` bytes into the write buffer before issuing a WRITE.
void load_write_buffer(const unsigned char* src, int len);

/// Copies `len` bytes out of the read buffer after a READ has finished.
void store_read_buffer(unsigned char* dst, int len);

/// Total clock edges applied to the RTL so far. Logging only.
uint64_t tick_count();

}  // namespace axi_dpi
