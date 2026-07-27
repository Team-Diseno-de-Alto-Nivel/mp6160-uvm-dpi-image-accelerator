#include "ram_axi.h"

#include <algorithm>
#include <sstream>

#include "dpi/axi_ram_dpi.h"
#include "infra/logger.h"

const sc_core::sc_time RamAxi::HALF_PERIOD(5, sc_core::SC_NS);

RamAxi::RamAxi(sc_core::sc_module_name name)
    : sc_module(name),
      target_socket("target_socket")
{
    target_socket.register_b_transport(this, &RamAxi::b_transport);
    axi_dpi::init();
    Logger::info("RamAxi", "Verilog AXI4-Full RAM ready (via DPI)");
}

RamAxi::~RamAxi()
{
    std::ostringstream oss;
    oss << "Shutting down after " << axi_dpi::tick_count() << " clock edges";
    Logger::info("RamAxi", oss.str());
    axi_dpi::shutdown();
}

// Encola la petición y hace avanzar el reloj del RTL hasta que el BFM la marca
// terminada. Cada flanco consume tiempo simulado, así que a diferencia del
// modelo puramente C++ acá sc_time_stamp() sí es significativo.
void RamAxi::run_transaction(int cmd, uint64_t addr, unsigned int len)
{
    axi_dpi_req(cmd, static_cast<long long>(addr), static_cast<int>(len));

    uint64_t ticks = 0;
    while (axi_dpi_done() == 0)
    {
        axi_dpi::tick();
        wait(HALF_PERIOD);

        if (++ticks > MAX_TICKS_PER_TRANSACTION)
        {
            std::ostringstream oss;
            oss << "Transaction stalled after " << ticks << " clock edges"
                << " (addr=0x" << std::hex << addr << std::dec
                << " len=" << len << "). Check the AXI handshakes in the RTL.";
            SC_REPORT_ERROR("RamAxi", oss.str().c_str());
            return;
        }
    }
}

void RamAxi::b_transport(tlm::tlm_generic_payload& payload,
                         sc_core::sc_time& delay)
{
    const uint64_t addr = payload.get_address();
    unsigned char* data = payload.get_data_ptr();
    const unsigned int len = payload.get_data_length();
    const tlm::tlm_command cmd = payload.get_command();

    if (len == 0)
    {
        payload.set_response_status(tlm::TLM_BURST_ERROR_RESPONSE);
        return;
    }

    if (cmd != tlm::TLM_WRITE_COMMAND && cmd != tlm::TLM_READ_COMMAND)
    {
        payload.set_response_status(tlm::TLM_COMMAND_ERROR_RESPONSE);
        return;
    }

    // El buffer de intercambio del puente es acotado, pero el CPU transfiere la
    // imagen completa de un tiro (6,220,800 B de entrada y 2,073,600 B de
    // salida). Se parte acá, no en el contrato DPI, para no atar el tamaño del
    // buffer al de la imagen.
    const int dpi_cmd = (cmd == tlm::TLM_WRITE_COMMAND) ? AXI_DPI_CMD_WRITE
                                                        : AXI_DPI_CMD_READ;

    for (unsigned int done = 0; done < len; )
    {
        const unsigned int chunk =
            std::min<unsigned int>(len - done, AXI_DPI_MAX_BYTES);

        if (dpi_cmd == AXI_DPI_CMD_WRITE)
        {
            axi_dpi::load_write_buffer(data + done, static_cast<int>(chunk));
            run_transaction(dpi_cmd, addr + done, chunk);
        }
        else
        {
            run_transaction(dpi_cmd, addr + done, chunk);
            axi_dpi::store_read_buffer(data + done, static_cast<int>(chunk));
        }

        if (axi_dpi_resp() != AXI_DPI_RESP_OKAY)
        {
            payload.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE);
            return;
        }

        done += chunk;
    }

    delay += HALF_PERIOD;
    payload.set_response_status(tlm::TLM_OK_RESPONSE);
}
