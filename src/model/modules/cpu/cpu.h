#pragma once

#include <systemc>
#include <tlm>
#include <tlm_utils/simple_initiator_socket.h>
#include <vector>
#include "../../config/memory_map.h"
#include "../../config/image_config.h"

class CPU : public sc_core::sc_module {
public:
    tlm_utils::simple_initiator_socket<CPU> init_socket;

    SC_HAS_PROCESS(CPU);

    CPU(sc_core::sc_module_name name,
        uint64_t disk_base_addr = DISK_BASE,
        uint64_t ram_base_addr = RAM_BASE,
        uint64_t accel_base_addr = ACCEL_BASE);

private:
    void run();

    void transport(uint64_t addr, unsigned char* data, unsigned int size, tlm::tlm_command cmd);
    void load_image_from_disk(std::vector<uint8_t>& buffer);
    void store_image_to_ram(const std::vector<uint8_t>& buffer);
    void configure_accelerator(uint64_t src_addr, uint64_t dst_addr, uint64_t pixel_count);
    void wait_accelerator_ready();
    void read_result_from_ram(std::vector<uint8_t>& buffer);
    void save_result_to_disk(const std::vector<uint8_t>& buffer);

    const uint64_t disk_base_addr;
    const uint64_t ram_base_addr;
    const uint64_t accel_base_addr;

    static constexpr uint32_t WIDTH = IMAGE_WIDTH;
    static constexpr uint32_t HEIGHT = IMAGE_HEIGHT;
    static constexpr uint64_t PIXEL_COUNT = IMAGE_PIXEL_COUNT;
    static constexpr uint64_t INPUT_IMAGE_BYTES = IMAGE_BYTES_RGB;
    static constexpr uint64_t OUTPUT_IMAGE_BYTES = IMAGE_BYTES_GRAY;
    static constexpr uint64_t INPUT_IMAGE_RAM_ADDR = RAM_IMG_IN;
    static constexpr uint64_t OUTPUT_IMAGE_RAM_ADDR = RAM_IMG_OUT;
    static constexpr uint64_t ACCEL_CONFIG_ADDR = 0x00000000ULL;
    static constexpr uint64_t ACCEL_STATUS_ADDR = ACCEL_STATUS_OFFSET;
    static constexpr uint64_t DISK_INPUT_ADDR = DISK_IMG_IN;
    static constexpr uint64_t DISK_OUTPUT_ADDR = DISK_IMG_OUT;
};
