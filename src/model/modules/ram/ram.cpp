#include "ram.h"

#include <cstring>
#include <sstream>
#include <iomanip>
#include <string>

#include "infra/logger.h"

RAM::RAM(sc_core::sc_module_name name)
    : sc_module(name),
      target_socket("target_socket"),
      memory(RAM_SIZE, 0)
{
    target_socket.register_b_transport(
        this,
        &RAM::b_transport);

    Logger::info("RAM", std::string("Initialized with ") + std::to_string(RAM_SIZE / (1024 * 1024)) + " MB");
}

void RAM::b_transport(
    tlm::tlm_generic_payload& payload,
    sc_core::sc_time& delay)
{
    uint64_t addr = payload.get_address();

    unsigned char* data = payload.get_data_ptr();
    unsigned int len = payload.get_data_length();
    tlm::tlm_command cmd = payload.get_command();

    if ((addr + len) > memory.size())
    {
        std::ostringstream oss;
        oss << "Address error: addr=0x" << std::hex << addr << std::dec << " len=" << len;
        Logger::info("RAM", oss.str());

        payload.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE);
        return;
    }

    if (cmd == tlm::TLM_WRITE_COMMAND)
    {
        std::memcpy(&memory[addr], data, len);
    }
    else if (cmd == tlm::TLM_READ_COMMAND)
    {
        std::memcpy(data, &memory[addr], len);
    }
    else
    {
        payload.set_response_status(tlm::TLM_COMMAND_ERROR_RESPONSE);
        return;
    }

    delay += sc_core::sc_time(10, sc_core::SC_NS);

    payload.set_response_status(tlm::TLM_OK_RESPONSE);
}
