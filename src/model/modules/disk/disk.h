#pragma once

#include <systemc>
#include <tlm>
#include <tlm_utils/simple_target_socket.h>
#include "../../config/memory_map.h"

SC_MODULE(Disk) {
public:
    tlm_utils::simple_target_socket<Disk> target_socket;

    SC_CTOR(Disk);

private:
    void b_transport(tlm::tlm_generic_payload& payload, sc_core::sc_time& delay);

    static constexpr const char* INPUT_PATH  = "images/input/image.raw";
    static constexpr const char* OUTPUT_PATH = "images/output/output.raw";

    static constexpr uint64_t DISK_INPUT_ADDR  = DISK_BASE + DISK_IMG_IN;
    static constexpr uint64_t DISK_OUTPUT_ADDR = DISK_BASE + DISK_IMG_OUT;
};
