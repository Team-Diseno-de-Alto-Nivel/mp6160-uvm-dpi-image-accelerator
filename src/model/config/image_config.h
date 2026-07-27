#pragma once
#include <cstdint>

// Expected image format: RAW RGB 1080p, no header, row-major.
// Change here to test with other resolutions.

constexpr uint32_t IMAGE_WIDTH       = 1920;
constexpr uint32_t IMAGE_HEIGHT      = 1080;
constexpr uint64_t IMAGE_PIXEL_COUNT = static_cast<uint64_t>(IMAGE_WIDTH) * IMAGE_HEIGHT;
constexpr uint64_t IMAGE_BYTES_RGB   = IMAGE_PIXEL_COUNT * 3; // input:  3 bytes/pixel RGB
constexpr uint64_t IMAGE_BYTES_GRAY  = IMAGE_PIXEL_COUNT;     // output: 1 byte/pixel grayscale
