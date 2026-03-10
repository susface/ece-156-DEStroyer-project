#pragma once
// ============================================================================
// ciphers.h -- Forward declarations for all attack / benchmark functions
// ============================================================================
#include "common.h"

// ----------------------------------------------------------------------------
// GPU DES attacks (compiled only when CUDA is available)
// ----------------------------------------------------------------------------
#ifdef HAVE_CUDA

CrackResult run_des_gpu_bruteforce(int bits, bool multi_pair);

CrackResult run_gpu_throughput(uint64_t n_keys);

#endif // HAVE_CUDA

// ----------------------------------------------------------------------------
// Benchmark bookkeeping
// ----------------------------------------------------------------------------
namespace Benchmark {
    void record(const CrackResult& r);          // append result to list
    void print_summary();                        // print all results to console
    void export_json(const char* path);          // write mitm_results.json
    void print_aes_extrapolation(double gpu_des_keys_per_sec);
}
