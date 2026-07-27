#include "disk.h"

#include <fstream>
#include <iostream>
#include <cstring>
#include <filesystem>

Disk::Disk(sc_core::sc_module_name name)
    : sc_module(name) {
    target_socket.register_b_transport(this, &Disk::b_transport);
}

void Disk::b_transport(tlm::tlm_generic_payload& payload, sc_core::sc_time& delay) {
    
    const uint64_t     addr = payload.get_address();
    unsigned char*     ptr  = payload.get_data_ptr();
    const unsigned int len  = payload.get_data_length();
 
    if (payload.get_command() == tlm::TLM_READ_COMMAND) {

        // CPU requests input image read from disk
        if (addr == DISK_INPUT_ADDR) {
            std::ifstream file(INPUT_PATH, std::ios::binary);

            if (!file.is_open()) {
                SC_REPORT_ERROR("Disk", ("Failed to open: " + std::string(INPUT_PATH)).c_str());
                payload.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
                return;
            }

            file.read(reinterpret_cast<char*>(ptr), len);

            if (!file) {
                SC_REPORT_ERROR("Disk", "Error reading input image");
                payload.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
                return;
            }

            std::cout << sc_core::sc_time_stamp()
                      << " Disk: read " << len
                      << " bytes from " << INPUT_PATH << std::endl;
        }
        else {
            SC_REPORT_ERROR("Disk", "Unknown read address");
            payload.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE);
            return;
        }
    }
    else if (payload.get_command() == tlm::TLM_WRITE_COMMAND) {
        
        // CPU requests processed image write to disk
        if (addr == DISK_OUTPUT_ADDR) {
            // Create output directory if it does not exist
            std::filesystem::create_directories("images/output");

            std::ofstream file(OUTPUT_PATH, std::ios::binary);

            if (!file.is_open()) {
                SC_REPORT_ERROR("Disk", ("Failed to create: " + std::string(OUTPUT_PATH)).c_str());
                payload.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
                return;
            }

            file.write(reinterpret_cast<char*>(ptr), len);

            if (!file) {
                SC_REPORT_ERROR("Disk", "Error writing output image");
                payload.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
                return;
            }

            std::cout << sc_core::sc_time_stamp()
                      << " Disk: wrote " << len
                      << " bytes to " << OUTPUT_PATH << std::endl;
        }
        else {
            SC_REPORT_ERROR("Disk", "Unknown write address");
            payload.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE);
            return;
        }
    }
 
    // Simulated disk latency: higher than RAM
    delay += sc_core::sc_time(100, sc_core::SC_NS);
    payload.set_response_status(tlm::TLM_OK_RESPONSE);
    
}
