#pragma once
// ============================================================================
// common.h -- Shared types and timing helper
// ============================================================================
// NOMINMAX and _CRT_SECURE_NO_WARNINGS are injected by CMakeLists.txt via
// add_compile_definitions — do NOT redefine here to avoid nvcc macro warnings.
#include <windows.h>
#include <intrin.h>   // __popcnt (Windows-only; no platform guards needed)
#include <cstdint>
#include <string>

// ----------------------------------------------------------------------------
// Result record filled by every attack function
// ----------------------------------------------------------------------------
struct CrackResult {
    std::string cipher;
    std::string method;
    bool        found        = false;
    std::string key_str;
    uint64_t    keys_tested  = 0;
    double      elapsed_sec  = 0.0;
    double      keys_per_sec = 0.0;
};

// ----------------------------------------------------------------------------
// High-resolution wall clock (returns seconds as double)
// ----------------------------------------------------------------------------
inline double wall_time_sec() {
    LARGE_INTEGER freq, cnt;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&cnt);
    return static_cast<double>(cnt.QuadPart) /
           static_cast<double>(freq.QuadPart);
}

// ----------------------------------------------------------------------------
// POPCOUNT -- Windows intrinsic, unconditional (project is Windows-only)
// ----------------------------------------------------------------------------
#define POPCOUNT(x) __popcnt(x)
