#pragma once

#include <systemc>
#include <tlm>
#include <tlm_utils/simple_target_socket.h>

// RAM respaldada por el RTL Verilog: traduce cada b_transport en transacciones
// AXI4-Full contra src/rtl/axi4_ram.v, a través del puente DPI-C.
//
// Interfaz idéntica a RAM (src/model/modules/ram/ram.h) para que el Bus pueda
// enlazar cualquiera de las dos sin cambios.
SC_MODULE(RamAxi)
{
public:
    tlm_utils::simple_target_socket<RamAxi> target_socket;

    SC_CTOR(RamAxi);
    ~RamAxi();

    void b_transport(tlm::tlm_generic_payload& payload,
                     sc_core::sc_time& delay);

private:
    // Medio período: cada tick() del RTL avanza el tiempo simulado de SystemC
    // en esta cantidad, de modo que sc_time_stamp() refleje transferencia real.
    static const sc_core::sc_time HALF_PERIOD;

    // Cota de seguridad: si una transacción no termina en esta cantidad de
    // flancos, algo se colgó (típicamente un handshake AXI mal implementado).
    static constexpr uint64_t MAX_TICKS_PER_TRANSACTION = 10000000;

    void run_transaction(int cmd, uint64_t addr, unsigned int len);
};
