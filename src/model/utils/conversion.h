#pragma once

#include <cstdint>
#include <cmath>

inline uint8_t rgb_to_gray(uint8_t r, uint8_t g, uint8_t b) {
    float gray = 0.299f * r + 0.587f * g + 0.114f * b;
    return static_cast<uint8_t>(std::round(gray));
}
