#pragma once

#include <systemc>
#include <tlm>
#include <tlm_utils/simple_target_socket.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <cstdint>
#include "../../config/memory_map.h"

SC_MODULE(Accelerator)
{
public:
    tlm_utils::simple_target_socket<Accelerator> target_socket;
    tlm_utils::simple_initiator_socket<Accelerator> init_socket;

    SC_CTOR(Accelerator);

private:
    void b_transport(tlm::tlm_generic_payload & payload, sc_core::sc_time & delay);
    void process_image(uint64_t src_addr, uint64_t dst_addr, uint64_t pixel_count);
    void write_status_register(uint32_t status);
    uint8_t rgb_to_gray(uint8_t r, uint8_t g, uint8_t b);

    uint32_t status_register = 0;
    static constexpr uint64_t STATUS_ADDR = ACCEL_BASE + ACCEL_STATUS_OFFSET;
};
