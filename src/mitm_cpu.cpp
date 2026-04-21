// ============================================================================
// mitm_cpu.cpp -- CPU implementations of MITM and Brute-Force attacks
//
// run_cpu_bruteforce: Double-DES brute-force attack (known-plaintext).
//   Original algorithm by Jose (DESBruteForce.cpp).
//   Integrated into the DEStroyer project framework by the team.
// ============================================================================
#include "ciphers.h"
#include "des_cpu.h"
#include "progress.h"
#include "common.h"
#include <cstdio>
#include <cstring>
#include <string>

// ----------------------------------------------------------------------------
// run_cpu_mitm  (stub — not yet implemented)
// ----------------------------------------------------------------------------
CrackResult run_cpu_mitm(int mitm_bits, bool multi_pair) {
    CrackResult res;
    res.cipher = "Double DES";
    res.method = "CPU MITM (" + std::to_string(mitm_bits) + " bits)";
    res.found  = false;
    return res;
}

// ----------------------------------------------------------------------------
// run_cpu_bruteforce
//
// Performs an exhaustive Double-DES brute-force key search over a reduced
// keyspace:  keyA in [0, 2^compare_bits)  x  keyB in [0, 2^compare_bits).
//
// A known plaintext/ciphertext pair is generated internally:
//   plaintext  = 0x1000000000000001
//   key A      = 0x00000000000000FE  (masked to compare_bits)
//   key B      = 0x0000000000000001  (masked to compare_bits)
//
// If multi_pair is true a second independent PT/CT pair is used to confirm
// any candidate, eliminating false positives in small keyspaces.
// ----------------------------------------------------------------------------
CrackResult run_cpu_bruteforce(int compare_bits, bool multi_pair) {
    CrackResult res;
    res.cipher = "Double DES";
    res.method = "CPU Brute-Force (" + std::to_string(compare_bits) + " bits)";
    res.found  = false;

    // ── Build known PT/CT pair ───────────────────────────────────────────────
    const uint64_t KEY_MASK = (compare_bits >= 64)
                              ? UINT64_MAX
                              : ((1ULL << compare_bits) - 1ULL);

    const uint64_t true_keyA  = 0x00000000000000FE & KEY_MASK;
    const uint64_t true_keyB  = 0x0000000000000001 & KEY_MASK;
    const uint64_t plaintext1 = 0x1000000000000001ULL;
    const uint64_t ciphertext1 = double_des_encrypt(plaintext1, true_keyA, true_keyB);

    // Optional second pair for false-positive elimination
    uint64_t plaintext2  = 0ULL;
    uint64_t ciphertext2_ref = 0ULL;
    if (multi_pair) {
        plaintext2      = 0xDEADBEEFCAFEBABEULL;
        ciphertext2_ref = double_des_encrypt(plaintext2, true_keyA, true_keyB);
    }

    // ── Search setup ─────────────────────────────────────────────────────────
    const uint64_t total_keyA = 1ULL << compare_bits;
    const uint64_t total_keyB = 1ULL << compare_bits;
    const uint64_t total_keys = total_keyA * total_keyB;

    printf("\n  Plaintext  : 0x%016llX\n", (unsigned long long)plaintext1);
    printf(  "  Ciphertext : 0x%016llX\n", (unsigned long long)ciphertext1);
    printf(  "  Keyspace   : 2^%d x 2^%d = 2^%d combinations\n",
             compare_bits, compare_bits, 2 * compare_bits);
    if (multi_pair)
        printf("  Mode       : Multi-pair (false-positive check enabled)\n");

    Progress prog;
    progress_start(&prog, "Double-DES Brute-Force", total_keys);

    double t0 = wall_time_sec();
    uint64_t keys_tested = 0;
    bool found = false;
    uint64_t found_keyA = 0, found_keyB = 0;

    // Precompute subkeys for inner keyB loop reuse is not possible here
    // (each outer iteration changes keyA), so we generate both sets inline.
    for (uint64_t ka = 0; ka < total_keyA && !found; ka++) {
        uint64_t sub1[16];
        generate_subkeys(ka, sub1);

        for (uint64_t kb = 0; kb < total_keyB && !found; kb++) {
            uint64_t sub2[16];
            generate_subkeys(kb, sub2);

            // Encrypt with keyA then keyB
            uint64_t ct_try = des_encrypt(des_encrypt(plaintext1, sub1), sub2);

            if (ct_try == ciphertext1) {
                // Optional second-pair verification
                if (!multi_pair ||
                    double_des_encrypt(plaintext2, ka, kb) == ciphertext2_ref)
                {
                    found      = true;
                    found_keyA = ka;
                    found_keyB = kb;
                }
            }

            keys_tested++;

            // Redraw progress bar roughly every 64K iterations
            if ((keys_tested & 0xFFFF) == 0)
                progress_update(&prog, keys_tested);
        }
    }

    progress_finish(&prog, found);

    double elapsed = wall_time_sec() - t0;

    // ── Fill result ──────────────────────────────────────────────────────────
    res.keys_tested  = keys_tested;
    res.elapsed_sec  = elapsed;
    res.keys_per_sec = (elapsed > 0.0) ? (double)keys_tested / elapsed : 0.0;

    if (found) {
        res.found = true;
        char buf[64];
        snprintf(buf, sizeof(buf), "KeyA=0x%016llX  KeyB=0x%016llX",
                 (unsigned long long)found_keyA,
                 (unsigned long long)found_keyB);
        res.key_str = buf;

        printf("\n  \033[92mKey found!\033[0m\n");
        printf("    Key A : 0x%016llX\n", (unsigned long long)found_keyA);
        printf("    Key B : 0x%016llX\n", (unsigned long long)found_keyB);
    } else {
        printf("\n  \033[93mKey not found in search space.\033[0m\n");
    }

    printf("  Keys tested : %llu  in %.2fs  (%.1f M/s)\n",
           (unsigned long long)keys_tested,
           elapsed,
           res.keys_per_sec / 1e6);

    return res;
}
