// -----------------------------------------------------------------------------
// Contrato DPI-C — lado SystemVerilog (T3.1)
// -----------------------------------------------------------------------------
// Contraparte de src/dpi/axi_ram_dpi.h. Se incluye desde axi_ram_dpi.sv.
// CONTRATO CONGELADO: no cambiar sin avisar a los integrantes 1 y 3.
// -----------------------------------------------------------------------------

`ifndef AXI_RAM_DPI_SVH
`define AXI_RAM_DPI_SVH

// ── Comandos ─────────────────────────────────────────────────────────────────
localparam int AXI_DPI_CMD_READ  = 0;
localparam int AXI_DPI_CMD_WRITE = 1;

// ── Códigos de respuesta ─────────────────────────────────────────────────────
localparam int AXI_DPI_RESP_OKAY   = 0;
localparam int AXI_DPI_RESP_SLVERR = 2;

localparam int AXI_DPI_MAX_BYTES = 1024 * 1024;

// ── Importadas: las implementa el C++ (src/dpi/axi_ram_dpi.cpp) ──────────────
import "DPI-C" function byte unsigned axi_dpi_get_wbyte(input int idx);
import "DPI-C" function void          axi_dpi_put_rbyte(input int idx,
                                                        input byte unsigned val);

// ── Exportadas: las llama el C++. Definirlas en axi_ram_dpi.sv ───────────────
// NOTA: deben ser `function`, no `task`, y NO pueden consumir tiempo de
// simulación (restricción de Verilator). Solo encolan/consultan estado; el
// trabajo real lo hace el AXI master BFM en su `always_ff`.
export "DPI-C" function axi_dpi_req;
export "DPI-C" function axi_dpi_done;
export "DPI-C" function axi_dpi_resp;

`endif  // AXI_RAM_DPI_SVH
