#pragma once

#include <systemc>
#include <tlm>
#include <tlm_utils/simple_target_socket.h>

#include <vector>
#include <cstdint>

SC_MODULE(RAM)
{
public:

    tlm_utils::simple_target_socket<RAM> target_socket;

    SC_CTOR(RAM);

    void b_transport(
        tlm::tlm_generic_payload& payload,
        sc_core::sc_time& delay);

private:

    static constexpr uint32_t RAM_SIZE = 64 * 1024 * 1024; // 64 MB

    std::vector<uint8_t> memory;
};