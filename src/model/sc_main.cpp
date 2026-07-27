#include <systemc>

#include "modules/cpu/cpu.h"
#include "modules/bus/bus.h"
#include "modules/ram/ram.h"
#include "modules/disk/disk.h"
#include "modules/accelerator/accelerator.h"

int sc_main(int argc, char* argv[])
{
    CPU         cpu("cpu");
    Bus         bus("bus");
    RAM         ram("ram");
    Disk        disk("disk");
    Accelerator accelerator("accelerator");

    std::cout << "*** Modules created ***" << std::endl;

    // CPU → Bus (main pipeline path)
    cpu.init_socket.bind(bus.target_socket);

    // Accelerator → Bus (RAM access path during image processing)
    accelerator.init_socket.bind(bus.target_socket_accel);

    // Bus → peripherals
    bus.init_socket_ram.bind(ram.target_socket);
    bus.init_socket_accel.bind(accelerator.target_socket);
    bus.init_socket_disk.bind(disk.target_socket);

    std::cout << "*** Sockets connected ***" << std::endl;

    sc_core::sc_start();

    std::cout << "*** Simulation complete :) ***" << std::endl;
    return 0;
}
