#include "accelerator.h"
#include "../../utils/conversion.h"
#include "../../infra/logger.h"
#include <iomanip>
#include <sstream>

Accelerator::Accelerator(sc_core::sc_module_name name)
    : sc_module(name) {
    target_socket.register_b_transport(this, &Accelerator::b_transport);
    SC_REPORT_INFO("Accelerator", "Initialized RGB→Grayscale accelerator");
}

uint8_t Accelerator::rgb_to_gray(uint8_t r, uint8_t g, uint8_t b) {
    return ::rgb_to_gray(r, g, b);
}

void Accelerator::b_transport(tlm::tlm_generic_payload& payload, sc_core::sc_time& delay) {
    uint64_t addr = payload.get_address();
    tlm::tlm_command cmd = payload.get_command();

    if (cmd == tlm::TLM_READ_COMMAND && addr == STATUS_ADDR) {
        // Read status register
        if (payload.get_data_length() < sizeof(uint32_t)) {
            SC_REPORT_ERROR("Accelerator", "Invalid status read size");
            payload.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
            return;
        }
        unsigned char* data = payload.get_data_ptr();
        *reinterpret_cast<uint32_t*>(data) = status_register;
        payload.set_response_status(tlm::TLM_OK_RESPONSE);
        delay += sc_core::sc_time(10, sc_core::SC_NS);
        return;
    }

    if (cmd != tlm::TLM_WRITE_COMMAND) {
        SC_REPORT_ERROR("Accelerator", "Only WRITE commands accepted for configuration");
        payload.set_response_status(tlm::TLM_COMMAND_ERROR_RESPONSE);
        return;
    }

    if (payload.get_data_length() != 24) {
        std::ostringstream oss;
        oss << "Invalid config size: " << payload.get_data_length() << " (expected 24 bytes)";
        SC_REPORT_ERROR("Accelerator", oss.str().c_str());
        payload.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
        return;
    }

    unsigned char* data = payload.get_data_ptr();
    uint64_t src_addr = *reinterpret_cast<uint64_t*>(&data[0]);
    uint64_t dst_addr = *reinterpret_cast<uint64_t*>(&data[8]);
    uint64_t pixel_count = *reinterpret_cast<uint64_t*>(&data[16]);

    std::ostringstream oss;
    oss << "Config received — src=0x" << std::hex << std::setw(8) << std::setfill('0') << src_addr
        << ", dst=0x" << std::setw(8) << dst_addr
        << ", pixels=" << std::dec << pixel_count;
    SC_REPORT_INFO("Accelerator", oss.str().c_str());

    status_register = 0;  // Clear status at the beginning of new job
    sc_core::sc_spawn(
        sc_bind(&Accelerator::process_image, this, src_addr, dst_addr, pixel_count)
    );

    payload.set_response_status(tlm::TLM_OK_RESPONSE);
    delay += sc_core::sc_time(10, sc_core::SC_NS);
}

void Accelerator::write_status_register(uint32_t status) {
    status_register = status;
}

void Accelerator::process_image(uint64_t src_addr, uint64_t dst_addr, uint64_t pixel_count) {
    const uint64_t report_every = (pixel_count >= 100) ? pixel_count / 100 : 1;

    for (uint64_t i = 0; i < pixel_count; ++i) {
        if (i % report_every == 0 || i == pixel_count - 1)
            Logger::progress(i, pixel_count);

        uint64_t src_offset = src_addr + (i * 3);
        uint64_t dst_offset = dst_addr + i;

        unsigned char rgb_data[3];
        tlm::tlm_generic_payload read_payload;
        read_payload.set_command(tlm::TLM_READ_COMMAND);
        read_payload.set_address(src_offset);
        read_payload.set_data_ptr(rgb_data);
        read_payload.set_data_length(3);
        sc_core::sc_time delay = sc_core::SC_ZERO_TIME;
        init_socket->b_transport(read_payload, delay);

        uint8_t r = rgb_data[0];
        uint8_t g = rgb_data[1];
        uint8_t b = rgb_data[2];
        uint8_t gray = rgb_to_gray(r, g, b);

        unsigned char gray_data[1] = {gray};
        tlm::tlm_generic_payload write_payload;
        write_payload.set_command(tlm::TLM_WRITE_COMMAND);
        write_payload.set_address(dst_offset);
        write_payload.set_data_ptr(gray_data);
        write_payload.set_data_length(1);
        init_socket->b_transport(write_payload, delay);
    }
    Logger::progress_done();
    write_status_register(1);
}