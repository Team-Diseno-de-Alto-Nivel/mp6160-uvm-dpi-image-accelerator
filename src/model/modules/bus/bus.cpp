#include "bus.h"
#include "../../config/memory_map.h"

Bus::Bus(sc_core::sc_module_name name)
    : sc_module(name) {
    target_socket.register_b_transport(this, &Bus::b_transport);
    target_socket_accel.register_b_transport(this, &Bus::b_transport_accel);
}

void Bus::b_transport(
    tlm::tlm_generic_payload& payload,
    sc_core::sc_time& delay)
{
    uint64_t addr = payload.get_address();

    if (addr <= RAM_END)
    {
        init_socket_ram->b_transport(payload, delay);
    }
    else if (addr >= ACCEL_BASE && addr <= ACCEL_END)
    {
        init_socket_accel->b_transport(payload, delay);
    }
    else if (addr >= DISK_BASE && addr <= DISK_END)
    {
        init_socket_disk->b_transport(payload, delay);
    }
    else
    {
        payload.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE);
    }

    delay += sc_core::sc_time(
        5,
        sc_core::SC_NS
    );
}


void Bus::b_transport_accel(
    tlm::tlm_generic_payload& payload,
    sc_core::sc_time& delay)
{
    uint64_t addr = payload.get_address();

    if (addr <= RAM_END)
    {
        init_socket_ram->b_transport(payload, delay);
    }
    else
    {
        payload.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE);
    }

    delay += sc_core::sc_time(
        5,
        sc_core::SC_NS
    );
}
