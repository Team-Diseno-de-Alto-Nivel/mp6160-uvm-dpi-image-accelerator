// Lado C del contrato DPI-C: implementa las funciones importadas por
// axi_ram_dpi.sv y es dueño del modelo generado por Verilator.

#include "axi_ram_dpi.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <vector>

#include "Vaxi_ram_dpi.h"
#include "svdpi.h"
#include "verilated.h"

namespace {

// Verilator registra el scope como "<nombre del modelo>.<nombre del módulo>",
// donde el nombre del modelo es "TOP" por defecto. Se compone en runtime para
// no depender de ese default.
constexpr const char* SV_MODULE = "axi_ram_dpi";

std::unique_ptr<Vaxi_ram_dpi> g_top;

// Buffer de intercambio con el BFM. Una sola petición está en vuelo a la vez,
// así que alcanza uno compartido entre lecturas y escrituras.
std::vector<uint8_t> g_buffer(AXI_DPI_MAX_BYTES, 0);

bool     g_clk_high = false;
uint64_t g_ticks    = 0;

void require_init(const char* who) {
    if (!g_top) {
        std::fprintf(stderr,
                     "axi_ram_dpi: %s llamado antes de axi_dpi::init()\n", who);
        std::abort();
    }
}

}  // namespace

// ── Funciones importadas por el SystemVerilog ────────────────────────────────

extern "C" unsigned char axi_dpi_get_wbyte(int idx) {
    if (idx < 0 || static_cast<size_t>(idx) >= g_buffer.size()) {
        std::fprintf(stderr, "axi_dpi_get_wbyte: idx %d fuera de rango\n", idx);
        std::abort();
    }
    return g_buffer[static_cast<size_t>(idx)];
}

extern "C" void axi_dpi_put_rbyte(int idx, unsigned char val) {
    if (idx < 0 || static_cast<size_t>(idx) >= g_buffer.size()) {
        std::fprintf(stderr, "axi_dpi_put_rbyte: idx %d fuera de rango\n", idx);
        std::abort();
    }
    g_buffer[static_cast<size_t>(idx)] = val;
}

// ── API que consume el SC_MODULE RamAxi ──────────────────────────────────────

namespace axi_dpi {

void init() {
    if (g_top) return;

    g_top = std::make_unique<Vaxi_ram_dpi>();

    // Sin esto, la primera llamada a una función DPI exportada aborta con
    // "scope wasn't set". Verilator exige fijar el scope SV explícitamente
    // antes de invocar exports desde C++.
    const std::string scope_name =
        std::string(g_top->name()) + "." + SV_MODULE;
    svScope scope = svGetScopeFromName(scope_name.c_str());
    if (!scope) {
        std::fprintf(stderr, "axi_ram_dpi: no existe el scope SV '%s'\n",
                     scope_name.c_str());
        std::abort();
    }
    svSetScope(scope);

    // El BFM sale de reset con la FSM en S_IDLE y ack_seq == req_seq == 0, o
    // sea reportando "done". Unos ciclos con aresetn bajo bastan.
    g_top->aresetn = 0;
    g_top->aclk    = 0;
    for (int i = 0; i < 8; ++i) {
        g_top->aclk = !g_top->aclk;
        g_top->eval();
    }
    g_top->aresetn = 1;
    g_clk_high     = false;
    g_top->eval();
}

void tick() {
    require_init("tick");
    g_clk_high  = !g_clk_high;
    g_top->aclk = g_clk_high ? 1 : 0;
    g_top->eval();
    ++g_ticks;
}

void shutdown() {
    if (!g_top) return;
    g_top->final();
    g_top.reset();
}

void load_write_buffer(const unsigned char* src, int len) {
    if (len < 0 || static_cast<size_t>(len) > g_buffer.size()) {
        std::fprintf(stderr, "load_write_buffer: len %d fuera de rango\n", len);
        std::abort();
    }
    std::copy(src, src + len, g_buffer.begin());
}

void store_read_buffer(unsigned char* dst, int len) {
    if (len < 0 || static_cast<size_t>(len) > g_buffer.size()) {
        std::fprintf(stderr, "store_read_buffer: len %d fuera de rango\n", len);
        std::abort();
    }
    std::copy(g_buffer.begin(), g_buffer.begin() + len, dst);
}

uint64_t tick_count() {
    return g_ticks;
}

}  // namespace axi_dpi
