#pragma once

#include <cstdint>
#include <iostream>
#include <iomanip>
#include <string>

namespace Logger {

inline void phase(int n, int total, const std::string& msg) {
    std::cout << "\n[" << n << "/" << total << "] " << msg << "...\n" << std::flush;
}

inline void progress(uint64_t current, uint64_t total) {
    if (total == 0) return;
    uint64_t pct    = (current + 1) * 100 / total;
    uint64_t filled = pct / 5;
    std::cout << "      [";
    for (int j = 0; j < 20; ++j) std::cout << (j < static_cast<int>(filled) ? '#' : ' ');
    std::cout << "] " << std::setw(3) << pct << "%  "
              << (current + 1) << " / " << total << " px\r" << std::flush;
}

inline void progress_done() {
    std::cout << "\n" << std::flush;
}

inline void info(const std::string& module, const std::string& msg) {
    std::cout << "[" << module << "] " << msg << "\n" << std::flush;
}

} // namespace Logger
