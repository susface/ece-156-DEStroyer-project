// ============================================================================
// comparisons.cpp -- Side-by-side comparison and complexity-sweep modes
//
// These functions are pure orchestration: they invoke the underlying
// CPU/GPU attack routines, record each individual run via Benchmark::record,
// and print a summary box highlighting the speedup or scaling behavior.
// ============================================================================
#include "ciphers.h"
#include "common.h"
#include <cstdio>
#include <vector>

#define RESET   "\033[0m"
#define DIM     "\033[2m"
#define BRED    "\033[91m"
#define BGREEN  "\033[92m"
#define BYELLOW "\033[93m"
#define BCYAN   "\033[96m"
#define BWHITE  "\033[97m"

// ----------------------------------------------------------------------------
// Render a two-row "A vs B" comparison box with the speedup ratio.
// speedup is reported as a.elapsed / b.elapsed, so passing the slower
// implementation first gives a ratio >= 1 in the typical case.
// ----------------------------------------------------------------------------
static void print_speedup_box(const char* title,
                              const CrackResult& a,
                              const CrackResult& b)
{
    double speedup = (b.elapsed_sec > 0.0)
                     ? a.elapsed_sec / b.elapsed_sec
                     : 0.0;
    const char* col = (speedup >= 1.0) ? BGREEN : BYELLOW;

    printf("\n");
    printf("  " BCYAN "+----------------------------------------------------------+\n" RESET);
    printf("  " BCYAN "|" BWHITE "  %-56s" BCYAN "|\n" RESET, title);
    printf("  " BCYAN "+----------------------------------------------------------+\n" RESET);
    printf("  " BCYAN "|" RESET "  %-32s  %12.4f s        " BCYAN "\n" RESET,
           a.method.c_str(), a.elapsed_sec);
    printf("  " BCYAN "|" RESET "  %-32s  %12.4f s        " BCYAN "\n" RESET,
           b.method.c_str(), b.elapsed_sec);
    printf("  " BCYAN "|" RESET DIM
           "  --------------------------------------------------" RESET "\n");
    printf("  " BCYAN "|" RESET "  %-32s  %s%11.2fx" RESET "         " BCYAN "\n" RESET,
           "Speedup (slower / faster):", col, speedup);
    printf("  " BCYAN "+----------------------------------------------------------+\n\n" RESET);
}

// ----------------------------------------------------------------------------
// Option 3: CPU vs GPU MITM
// Runs both implementations at the same bit-width and prints the speedup.
// ----------------------------------------------------------------------------
void run_cpu_vs_gpu_mitm(int mitm_bits, bool multi_pair, bool show_transfer) {
#ifndef HAVE_CUDA
    (void)mitm_bits; (void)multi_pair; (void)show_transfer;
    printf("\n  " BRED "CUDA not available -- cannot compare against GPU.\n" RESET);
    printf("  "  DIM  "Rebuild with a CUDA toolkit installed.\n\n" RESET);
#else
    printf("\n  " BCYAN "[1/2] CPU MITM..." RESET "\n");
    CrackResult cpu = run_cpu_mitm(mitm_bits, multi_pair);
    Benchmark::record(cpu);

    printf("\n  " BCYAN "[2/2] GPU MITM..." RESET "\n");
    CrackResult gpu = run_gpu_mitm(mitm_bits, multi_pair, show_transfer);
    Benchmark::record(gpu);

    print_speedup_box("CPU vs GPU MITM", cpu, gpu);
#endif
}

// ----------------------------------------------------------------------------
// Option 5: MITM vs Brute-Force (CPU)
// Runs CPU MITM at mitm_bits and CPU brute-force at compare_bits, then
// prints both side-by-side. Note that mitm_bits and compare_bits are NOT
// directly comparable -- the point is to show the asymptotic difference
// (MITM is ~O(2^N), brute force is ~O(2^(2N))).
// ----------------------------------------------------------------------------
void run_mitm_vs_bruteforce(int mitm_bits, int compare_bits, bool multi_pair) {
    printf("\n  " BCYAN "[1/2] CPU MITM (%d bits)..." RESET "\n", mitm_bits);
    CrackResult mitm = run_cpu_mitm(mitm_bits, multi_pair);
    Benchmark::record(mitm);

    printf("\n  " BCYAN "[2/2] CPU Brute-Force (%d bits)..." RESET "\n", compare_bits);
    CrackResult bf = run_cpu_bruteforce(compare_bits, multi_pair);
    Benchmark::record(bf);

    print_speedup_box("MITM vs Brute-Force (CPU)", bf, mitm);

    printf("  " DIM
           "Note: keyspaces differ (MITM=2^%d, BF=2^%d). The asymptotic\n"
           "        difference is the point: MITM is O(2^N), BF is O(2^(2N)).\n\n"
           RESET,
           mitm_bits, compare_bits);
}

// ----------------------------------------------------------------------------
// Option 8: Complexity Analysis
// Sweeps both CPU MITM and CPU Brute-Force across a range of bit widths
// and prints a measured-time table that should match the theoretical
// 2^N vs 2^(2N) growth curves.
// ----------------------------------------------------------------------------
void run_complexity_analysis(bool multi_pair) {
    static const int BITS[] = { 4, 6, 8, 10, 12 };
    static const int NB     = (int)(sizeof(BITS) / sizeof(BITS[0]));

    std::vector<double> mitm_t(NB, 0.0);
    std::vector<double> bf_t(NB, 0.0);

    printf("\n  " BCYAN "Sweeping MITM and Brute-Force across bit widths..."
           RESET "\n");
    printf("  " DIM
           "(brute-force grows as 2^(2N), so the high end takes a moment)\n"
           RESET);

    for (int i = 0; i < NB; i++) {
        int b = BITS[i];

        printf("\n  " BWHITE "--- bits = %d ---" RESET "\n", b);

        CrackResult m = run_cpu_mitm(b, multi_pair);
        Benchmark::record(m);
        mitm_t[i] = m.elapsed_sec;

        CrackResult bf = run_cpu_bruteforce(b, multi_pair);
        Benchmark::record(bf);
        bf_t[i] = bf.elapsed_sec;
    }

    printf("\n");
    printf("  " BCYAN "+------+----------------+----------------+----------------+\n" RESET);
    printf("  " BCYAN "|" BWHITE " bits " BCYAN "|" BWHITE
           "  MITM (s)      " BCYAN "|" BWHITE
           "  BF (s)        " BCYAN "|" BWHITE
           "  BF / MITM     " BCYAN "|\n" RESET);
    printf("  " BCYAN "+------+----------------+----------------+----------------+\n" RESET);

    for (int i = 0; i < NB; i++) {
        double ratio = (mitm_t[i] > 0.0) ? bf_t[i] / mitm_t[i] : 0.0;
        printf("  " BCYAN "|" RESET " %4d " BCYAN "|" RESET
               " %14.6f " BCYAN "|" RESET
               " %14.6f " BCYAN "|" RESET
               " %13.2fx " BCYAN "|\n" RESET,
               BITS[i], mitm_t[i], bf_t[i], ratio);
    }
    printf("  " BCYAN "+------+----------------+----------------+----------------+\n" RESET);

    printf("\n  " DIM
           "Theoretical: MITM = O(2^N), Brute-Force = O(2^(2N)).\n"
           "  Each +1 bit doubles MITM cost but quadruples brute-force cost,\n"
           "  so the BF/MITM ratio should grow by ~2x per +1 bit.\n\n"
           RESET);
}
