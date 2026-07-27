#include <cstring>
#include <memory>
#include <systemc>

#include "modules/cpu/cpu.h"
#include "modules/bus/bus.h"
#include "modules/ram/ram.h"
#include "modules/disk/disk.h"
#include "modules/accelerator/accelerator.h"

#ifdef HAVE_RTL_RAM
#include "modules/ram_axi/ram_axi.h"
#endif

int sc_main(int argc, char* argv[])
{
    bool use_rtl_ram = false;
    for (int i = 1; i < argc; ++i)
    {
        if (std::strcmp(argv[i], "--rtl-ram") == 0)
        {
            use_rtl_ram = true;
        }
        else
        {
            std::cerr << "Unknown option: " << argv[i] << "\n"
                      << "Usage: sim [--rtl-ram]\n";
            return 1;
        }
    }

#ifndef HAVE_RTL_RAM
    if (use_rtl_ram)
    {
        std::cerr << "This build has no RTL backend — CMake disabled it at "
                     "configure time.\n"
                     "Re-run `make` and read the STATUS/WARNING lines for the "
                     "reason (usually Verilator missing, or a project path "
                     "containing spaces). See the README.\n";
        return 1;
    }
#endif

    CPU         cpu("cpu");
    Bus         bus("bus");
    Disk        disk("disk");
    Accelerator accelerator("accelerator");

    // Sólo se instancia el backend elegido. Ambos exponen el mismo
    // simple_target_socket, así que el Bus enlaza igual en los dos casos.
    std::unique_ptr<RAM> ram;
#ifdef HAVE_RTL_RAM
    std::unique_ptr<RamAxi> ram_rtl;
#endif

    if (use_rtl_ram)
    {
#ifdef HAVE_RTL_RAM
        ram_rtl = std::make_unique<RamAxi>("ram_rtl");
        bus.init_socket_ram.bind(ram_rtl->target_socket);
        std::cout << "*** RAM backend: Verilog AXI4-Full RTL (via DPI) ***"
                  << std::endl;
#endif
    }
    else
    {
        ram = std::make_unique<RAM>("ram");
        bus.init_socket_ram.bind(ram->target_socket);
        std::cout << "*** RAM backend: C++ behavioural model ***" << std::endl;
    }

    std::cout << "*** Modules created ***" << std::endl;

    // CPU → Bus (main pipeline path)
    cpu.init_socket.bind(bus.target_socket);

    // Accelerator → Bus (RAM access path during image processing)
    accelerator.init_socket.bind(bus.target_socket_accel);

    // Bus → peripherals
    bus.init_socket_accel.bind(accelerator.target_socket);
    bus.init_socket_disk.bind(disk.target_socket);

    std::cout << "*** Sockets connected ***" << std::endl;

    sc_core::sc_start();

    std::cout << "*** Simulation complete :) ***" << std::endl;
    return 0;
}
