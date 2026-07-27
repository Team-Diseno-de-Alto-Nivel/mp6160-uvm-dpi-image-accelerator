#pragma once

#include <systemc>
#include <tlm>
#include <tlm_utils/simple_target_socket.h>

// RAM backed by the Verilog RTL: turns every b_transport into AXI4-Full
// transactions against src/rtl/axi4_ram.v, through the DPI-C bridge.
//
// Interface identical to RAM (src/model/modules/ram/ram.h) so the Bus can bind
// either one without changes.
SC_MODULE(RamAxi)
{
public:
    tlm_utils::simple_target_socket<RamAxi> target_socket;

    SC_CTOR(RamAxi);
    ~RamAxi();

    void b_transport(tlm::tlm_generic_payload& payload,
                     sc_core::sc_time& delay);

private:
    // Half a clock period: every RTL tick() advances SystemC's simulated time by
    // this much, so sc_time_stamp() reflects real transfer cost.
    static const sc_core::sc_time HALF_PERIOD;

    // Safety bound: if a transaction does not finish within this many clock
    // edges something has hung, typically a mis-implemented AXI handshake.
    static constexpr uint64_t MAX_TICKS_PER_TRANSACTION = 10000000;

    void run_transaction(int cmd, uint64_t addr, unsigned int len);
};
