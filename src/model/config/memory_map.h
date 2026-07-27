#pragma once
#include <cstdint>

constexpr uint64_t RAM_BASE     = 0x00000000ULL; // start of RAM (64 MB)
constexpr uint64_t RAM_END      = 0x03FFFFFFULL; // end of RAM
constexpr uint64_t RAM_IMG_IN   = 0x00000000ULL; // RGB input image (~5.9 MB)
constexpr uint64_t RAM_IMG_OUT  = 0x00600000ULL; // grayscale output image (~1.9 MB)

constexpr uint64_t ACCEL_BASE          = 0x10000000ULL; // start of Accelerator address space
constexpr uint64_t ACCEL_END           = 0x1FFFFFFFULL; // end of Accelerator address space
constexpr uint64_t ACCEL_STATUS_OFFSET = 0x00000018ULL; // status register offset (+24 bytes after config)

constexpr uint64_t DISK_BASE    = 0x20000000ULL; // start of Disk address space
constexpr uint64_t DISK_END     = 0x2FFFFFFFULL; // end of Disk address space
constexpr uint64_t DISK_IMG_IN  = 0x00000000ULL; // Disk offset: RGB input image
constexpr uint64_t DISK_IMG_OUT = 0x01000000ULL; // Disk offset: grayscale output image
