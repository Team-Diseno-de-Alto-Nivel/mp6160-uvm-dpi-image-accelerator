// -----------------------------------------------------------------------------
// DPI-C contract — SystemVerilog side
// -----------------------------------------------------------------------------
// Counterpart of src/dpi/axi_ram_dpi.h. Included from axi_ram_dpi.sv.
// FROZEN CONTRACT: do not change without telling the team.
// -----------------------------------------------------------------------------

`ifndef AXI_RAM_DPI_SVH
`define AXI_RAM_DPI_SVH

// ── Commands ─────────────────────────────────────────────────────────────────
localparam int AXI_DPI_CMD_READ  = 0;
localparam int AXI_DPI_CMD_WRITE = 1;

// ── Response codes ───────────────────────────────────────────────────────────
localparam int AXI_DPI_RESP_OKAY   = 0;
localparam int AXI_DPI_RESP_SLVERR = 2;

localparam int AXI_DPI_MAX_BYTES = 1024 * 1024;

// ── Imported: implemented on the C++ side (src/dpi/axi_ram_dpi.cpp) ──────────
import "DPI-C" function byte unsigned axi_dpi_get_wbyte(input int idx);
import "DPI-C" function void          axi_dpi_put_rbyte(input int idx,
                                                        input byte unsigned val);

// ── Exported: called by the C++ side. Defined in axi_ram_dpi.sv ──────────────
// NOTE: these must be `function`, not `task`, and must NOT consume simulation
// time (a Verilator restriction). They only enqueue or query state; the real
// work happens in the AXI master BFM's `always_ff`.
export "DPI-C" function axi_dpi_req;
export "DPI-C" function axi_dpi_done;
export "DPI-C" function axi_dpi_resp;

`endif  // AXI_RAM_DPI_SVH
