#pragma once

#include <systemc>
#include <tlm>
#include <tlm_utils/simple_target_socket.h>
#include <tlm_utils/simple_initiator_socket.h>

SC_MODULE(Bus) {
public:
    tlm_utils::simple_target_socket<Bus> target_socket;
    tlm_utils::simple_target_socket<Bus> target_socket_accel;

    tlm_utils::simple_initiator_socket<Bus> init_socket_ram;
    tlm_utils::simple_initiator_socket<Bus> init_socket_accel;
    tlm_utils::simple_initiator_socket<Bus> init_socket_disk;

    SC_CTOR(Bus);

private:
    void b_transport(tlm::tlm_generic_payload& payload, sc_core::sc_time& delay);
    void b_transport_accel(tlm::tlm_generic_payload& payload, sc_core::sc_time& delay);
};
