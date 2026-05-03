#pragma once
// ============================================================================
// ciphers.h -- Forward declarations for all attack / benchmark functions
// ============================================================================
#include "common.h"

// ----------------------------------------------------------------------------
// CPU DES attacks
// ----------------------------------------------------------------------------
CrackResult run_cpu_mitm(int mitm_bits, bool multi_pair);
CrackResult run_cpu_bruteforce(int compare_bits, bool multi_pair);

// ----------------------------------------------------------------------------
// GPU DES attacks (compiled only when CUDA is available)
// ----------------------------------------------------------------------------
#ifdef HAVE_CUDA

// Option 2: GPU Meet-in-the-Middle using Thrust
CrackResult run_gpu_mitm(int mitm_bits, bool multi_pair, bool show_transfer);


// Option 6: single DES, exhaustive GPU key search over 2^bits keys.
// multi_pair=true: verify candidate against a second independent PT/CT pair,
// eliminating false positives caused by key collisions in reduced keyspaces.
CrackResult run_des_gpu_bruteforce(int bits, bool multi_pair);

// Option 7: peak DES throughput + AES brute-force extrapolation
CrackResult run_gpu_throughput(uint64_t n_keys);

#endif // HAVE_CUDA

// ----------------------------------------------------------------------------
// Comparison / analysis modes (orchestrate the routines above)
// ----------------------------------------------------------------------------
void run_cpu_vs_gpu_mitm(int mitm_bits, bool multi_pair, bool show_transfer);
void run_mitm_vs_bruteforce(int mitm_bits, int compare_bits, bool multi_pair);
void run_complexity_analysis(bool multi_pair);

// ----------------------------------------------------------------------------
// Benchmark bookkeeping
// ----------------------------------------------------------------------------
namespace Benchmark {
    void record(const CrackResult& r);          // append result to list
    void print_summary();                        // print all results to console
    void export_json(const char* path);          // write mitm_results.json
    void print_aes_extrapolation(double gpu_des_keys_per_sec);
}
