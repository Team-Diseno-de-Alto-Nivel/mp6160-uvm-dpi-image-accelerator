cmake_minimum_required(VERSION 3.16)
project(systemc_image_processor CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(FetchContent)

# ── SystemC setup ─────────────────────────────────────────────────────────────
if(DEFINED ENV{SYSTEMC_HOME})
    message(STATUS "Using SystemC from SYSTEMC_HOME=$ENV{SYSTEMC_HOME}")
    set(SYSTEMC_HOME $ENV{SYSTEMC_HOME})
    include_directories(${SYSTEMC_HOME}/include)
    find_library(SYSTEMC_LIB
        NAMES systemc
        PATHS ${SYSTEMC_HOME}/lib ${SYSTEMC_HOME}/lib-linux64 ${SYSTEMC_HOME}/lib-macosx64
        REQUIRED)
else()
    message(STATUS "SYSTEMC_HOME not set — downloading SystemC 2.3.4 via FetchContent (requires internet)")
    set(DISABLE_ASYNC_UPDATES     ON  CACHE INTERNAL "")
    set(BUILD_SOURCE_DOCUMENTATION OFF CACHE INTERNAL "")
    set(CMAKE_CXX_STANDARD 17 CACHE STRING "C++ standard" FORCE)
    FetchContent_Declare(
        SystemC
        URL https://github.com/accellera-official/systemc/archive/refs/tags/2.3.4.tar.gz
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
    FetchContent_MakeAvailable(SystemC)
    set(SYSTEMC_LIB SystemC::systemc)
endif()

# ── RTL RAM via Verilator + DPI (optional) ────────────────────────────────────
# Without Verilator the project still builds, just without the --rtl-ram mode.
find_package(verilator QUIET HINTS $ENV{VERILATOR_ROOT})

# Verilator does not tolerate spaces in paths: its verilated.mk is a GNU Make
# file, and verilate()'s JSON parser breaks too. Detected here so that `make`
# keeps working instead of failing at configure time.
set(RTL_PATH_OK TRUE)
if(CMAKE_CURRENT_SOURCE_DIR MATCHES "[ \t]" OR CMAKE_BINARY_DIR MATCHES "[ \t]")
    set(RTL_PATH_OK FALSE)
endif()

set(RTL_RAM_SOURCES "")
if(verilator_FOUND AND RTL_PATH_OK)
    message(STATUS "Verilator found (${verilator_VERSION}) — enabling --rtl-ram backend")

    add_library(axi_ram_rtl STATIC src/dpi/axi_ram_dpi.cpp)
    target_include_directories(axi_ram_rtl PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
    set_target_properties(axi_ram_rtl PROPERTIES CXX_STANDARD 17)

    verilate(axi_ram_rtl
        SOURCES src/rtl/axi4_ram.v src/dpi/axi_ram_dpi.sv
        TOP_MODULE axi_ram_dpi
        PREFIX Vaxi_ram_dpi
        INCLUDE_DIRS src/dpi
        VERILATOR_ARGS -O2 --x-assign fast --x-initial fast -Wall
    )

    set(RTL_RAM_SOURCES src/model/modules/ram_axi/ram_axi.cpp)
elseif(NOT verilator_FOUND)
    message(STATUS "Verilator not found — building without the --rtl-ram backend")
else()
    message(WARNING
        "Verilator ${verilator_VERSION} found, but the project path contains "
        "spaces:\n  ${CMAKE_CURRENT_SOURCE_DIR}\n"
        "Verilator cannot build there, so the --rtl-ram backend is disabled. "
        "Clone into a space-free path or use the dev container (/workspace). "
        "The default C++ RAM build is unaffected.")
endif()

# ── Main simulation executable ────────────────────────────────────────────────
add_executable(sim
    src/model/sc_main.cpp
    src/model/modules/cpu/cpu.cpp
    src/model/modules/bus/bus.cpp
    src/model/modules/ram/ram.cpp
    src/model/modules/disk/disk.cpp
    src/model/modules/accelerator/accelerator.cpp
    ${RTL_RAM_SOURCES}
)
target_include_directories(sim PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src/model)
target_link_libraries(sim ${SYSTEMC_LIB})

if(verilator_FOUND AND RTL_PATH_OK)
    target_include_directories(sim PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_link_libraries(sim axi_ram_rtl)
    target_compile_definitions(sim PRIVATE HAVE_RTL_RAM)
endif()
