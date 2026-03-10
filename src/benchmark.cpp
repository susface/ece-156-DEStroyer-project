// ============================================================================
// benchmark.cpp -- Result recording, summary display, and JSON export
// ============================================================================
#include <windows.h>
#include <cstdio>
#include <cmath>
#include <vector>
#include "common.h"
#include "ciphers.h"

// Color macros as #defines for compile-time string literal concatenation
#define RESET   "\033[0m"
#define DIM     "\033[2m"
#define BRED    "\033[91m"
#define BGREEN  "\033[92m"
#define BYELLOW "\033[93m"
#define BCYAN   "\033[96m"
#define BWHITE  "\033[97m"

static std::vector<CrackResult> g_results;

// ----------------------------------------------------------------------------
void Benchmark::record(const CrackResult& r) {
    g_results.push_back(r);
}

// ----------------------------------------------------------------------------
void Benchmark::print_summary() {
    if (g_results.empty()) {
        printf("\n" "  " DIM "No benchmark results recorded this session.\n" RESET);
        return;
    }

    printf("\n");
    printf("  " BCYAN "+---------------------------------------------------------------------+\n" RESET);
    printf("  " BCYAN "|" BWHITE "  %-69s" BCYAN "|\n" RESET, "  SESSION RESULTS");
    printf("  " BCYAN "+---------------------------------------------------------------------+\n" RESET);

    for (size_t i = 0; i < g_results.size(); i++) {
        const CrackResult& r = g_results[i];
        const char* found_color = r.found ? BGREEN : BRED;
        const char* found_str   = r.found ? "FOUND  " : "MISSED ";

        printf("  " BCYAN "|" RESET "  " BWHITE "%-30s" RESET "  "
               "%s%-7s" RESET "  %s\n",
               r.method.c_str(), found_color, found_str, r.key_str.c_str());

        printf("  " BCYAN "|" RESET "  " DIM
               "Keys: %-14llu  Time: %8.4f s  Rate: %.3e keys/s\n" RESET,
               (unsigned long long)r.keys_tested,
               r.elapsed_sec,
               r.keys_per_sec);

        if (i + 1 < g_results.size())
            printf("  " BCYAN "|" RESET "\n");
    }

    printf("  " BCYAN "+---------------------------------------------------------------------+\n\n" RESET);
}

// ----------------------------------------------------------------------------
void Benchmark::export_json(const char* path) {
    FILE* f = fopen(path, "w");
    if (!f) {
        fprintf(stderr, BRED "  [ERROR] Cannot write %s\n" RESET, path);
        return;
    }

    fprintf(f, "{\n  \"benchmark_results\": [\n");
    for (size_t i = 0; i < g_results.size(); i++) {
        const CrackResult& r = g_results[i];
        fprintf(f, "    {\n");
        fprintf(f, "      \"cipher\"      : \"%s\",\n", r.cipher.c_str());
        fprintf(f, "      \"method\"      : \"%s\",\n", r.method.c_str());
        fprintf(f, "      \"found\"       : %s,\n",     r.found ? "true" : "false");
        fprintf(f, "      \"key\"         : \"%s\",\n", r.key_str.c_str());
        fprintf(f, "      \"keys_tested\" : %llu,\n",   (unsigned long long)r.keys_tested);
        fprintf(f, "      \"elapsed_sec\" : %.6f,\n",   r.elapsed_sec);
        fprintf(f, "      \"keys_per_sec\": %.2f\n",    r.keys_per_sec);
        fprintf(f, "    }%s\n", (i + 1 < g_results.size()) ? "," : "");
    }
    fprintf(f, "  ]\n}\n");
    fclose(f);

    printf("  " DIM "Results exported to: " BWHITE "%s\n\n" RESET, path);
}

// ----------------------------------------------------------------------------
void Benchmark::print_aes_extrapolation(double gpu_des_keys_per_sec) {
    const double SECS_PER_YEAR = 365.25 * 24.0 * 3600.0;

    // At the measured DES key rate, how long to brute-force AES?
    double aes128_years = (pow(2.0, 128.0) / gpu_des_keys_per_sec) / SECS_PER_YEAR;
    double aes192_years = (pow(2.0, 192.0) / gpu_des_keys_per_sec) / SECS_PER_YEAR;
    double aes256_years = (pow(2.0, 256.0) / gpu_des_keys_per_sec) / SECS_PER_YEAR;

    printf("\n");
    printf("  " BCYAN "+------------------------------------------------------------+\n" RESET);
    printf("  " BCYAN "|" BWHITE "  AES Brute-Force Extrapolation                             " BCYAN "|\n" RESET);
    printf("  " BCYAN "|" DIM   "  Assuming %.3e DES keys/sec (GPU)                 " BCYAN "|\n" RESET,
           gpu_des_keys_per_sec);
    printf("  " BCYAN "+------------------------------------------------------------+\n" RESET);
    printf("  " BCYAN "|" RESET "  AES-128:  " BYELLOW "%.3e years\n" RESET, aes128_years);
    printf("  " BCYAN "|" RESET "  AES-192:  " BYELLOW "%.3e years\n" RESET, aes192_years);
    printf("  " BCYAN "|" RESET "  AES-256:  " BYELLOW "%.3e years\n" RESET, aes256_years);
    printf("  " BCYAN "+------------------------------------------------------------+\n\n" RESET);
}
