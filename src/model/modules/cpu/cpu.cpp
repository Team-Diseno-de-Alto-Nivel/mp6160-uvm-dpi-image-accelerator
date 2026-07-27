#include "cpu.h"
#include "../../infra/logger.h"

CPU::CPU(sc_core::sc_module_name name,
         uint64_t disk_base_addr,
         uint64_t ram_base_addr,
         uint64_t accel_base_addr)
    : sc_core::sc_module(name)
    , init_socket("init_socket")
    , disk_base_addr(disk_base_addr)
    , ram_base_addr(ram_base_addr)
    , accel_base_addr(accel_base_addr) {
    SC_THREAD(run);
}

void CPU::run() {
    std::vector<uint8_t> input_image(INPUT_IMAGE_BYTES);
    std::vector<uint8_t> output_image(OUTPUT_IMAGE_BYTES);

    Logger::phase(1, 5, "Loading image from disk");
    load_image_from_disk(input_image);

    Logger::phase(2, 5, "Storing image in RAM");
    store_image_to_ram(input_image);

    Logger::phase(3, 5, "Configuring accelerator");
    configure_accelerator(ram_base_addr + INPUT_IMAGE_RAM_ADDR,
                          ram_base_addr + OUTPUT_IMAGE_RAM_ADDR,
                          PIXEL_COUNT);

    Logger::phase(4, 5, "Processing image");
    wait_accelerator_ready();

    Logger::phase(5, 5, "Saving result to disk");
    read_result_from_ram(output_image);
    save_result_to_disk(output_image);

    sc_core::sc_stop();
}

void CPU::transport(uint64_t addr, unsigned char* data, unsigned int size, tlm::tlm_command cmd) {
    tlm::tlm_generic_payload trans;
    sc_core::sc_time delay = sc_core::sc_time(10, sc_core::SC_NS);

    trans.set_command(cmd);
    trans.set_address(addr);
    trans.set_data_ptr(data);
    trans.set_data_length(size);
    trans.set_streaming_width(size);
    trans.set_byte_enable_ptr(nullptr);
    trans.set_dmi_allowed(false);
    trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);

    init_socket->b_transport(trans, delay);

    if (trans.is_response_error()) {
        SC_REPORT_ERROR("CPU", "TLM transaction returned error response");
    }
}

void CPU::load_image_from_disk(std::vector<uint8_t>& buffer) {
    transport(disk_base_addr + DISK_INPUT_ADDR,
              buffer.data(),
              static_cast<unsigned int>(buffer.size()),
              tlm::TLM_READ_COMMAND);
}

void CPU::store_image_to_ram(const std::vector<uint8_t>& buffer) {
    transport(ram_base_addr + INPUT_IMAGE_RAM_ADDR,
              const_cast<unsigned char*>(buffer.data()),
              static_cast<unsigned int>(buffer.size()),
              tlm::TLM_WRITE_COMMAND);
}

void CPU::configure_accelerator(uint64_t src_addr, uint64_t dst_addr, uint64_t pixel_count) {
    uint64_t config[3];
    config[0] = src_addr;
    config[1] = dst_addr;
    config[2] = pixel_count;

    transport(accel_base_addr + ACCEL_CONFIG_ADDR,
              reinterpret_cast<unsigned char*>(config),
              static_cast<unsigned int>(sizeof(config)),
              tlm::TLM_WRITE_COMMAND);
}

void CPU::wait_accelerator_ready() {
    uint32_t status = 0;
    const sc_core::sc_time poll_interval = sc_core::sc_time(100, sc_core::SC_NS);

    while (status == 0) {
        transport(accel_base_addr + ACCEL_STATUS_ADDR,
                  reinterpret_cast<unsigned char*>(&status),
                  sizeof(uint32_t),
                  tlm::TLM_READ_COMMAND);

        if (status == 0) {
            sc_core::wait(poll_interval);
        }
    }
}

void CPU::read_result_from_ram(std::vector<uint8_t>& buffer) {
    transport(ram_base_addr + OUTPUT_IMAGE_RAM_ADDR,
              buffer.data(),
              static_cast<unsigned int>(buffer.size()),
              tlm::TLM_READ_COMMAND);
}

void CPU::save_result_to_disk(const std::vector<uint8_t>& buffer) {
    transport(disk_base_addr + DISK_OUTPUT_ADDR,
              const_cast<unsigned char*>(buffer.data()),
              static_cast<unsigned int>(buffer.size()),
              tlm::TLM_WRITE_COMMAND);
}
