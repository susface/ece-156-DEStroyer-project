// ============================================================================
// mitm_cpu.cpp -- CPU implementations of MITM and Brute-Force attacks
//
// run_cpu_bruteforce: Double-DES brute-force attack (known-plaintext).
//   Original algorithm by Jose (DESBruteForce.cpp).
//   Integrated into the DEStroyer project framework by the team.
//   Parallelized across cores using std::thread + atomic early-exit.
//
// run_cpu_mitm:       Double-DES Meet-in-the-Middle (Armanjit's MitM_Attack.cpp).
//   Phase 1 (build) and Phase 2 (search) both parallelized; build uses a
//   sorted (mid -> keyA) vector instead of std::unordered_map so concurrent
//   construction is safe.
// ============================================================================
#include "ciphers.h"
#include "des_cpu.h"
#include "progress.h"
#include "common.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

// ----------------------------------------------------------------------------
// Pick a worker count.  hardware_concurrency() can return 0 on weird systems.
// ----------------------------------------------------------------------------
static int pick_thread_count() {
    int n = (int)std::thread::hardware_concurrency();
    return (n > 0) ? n : 4;
}

// ----------------------------------------------------------------------------
// run_cpu_mitm
//
// Phase 1: for every candidate keyA in [0, 2^mitm_bits), compute
//          mid = E_keyA(plaintext) and store {mid, keyA} in a flat vector.
//          Filled in parallel -- each thread owns a contiguous slice of the
//          vector, so there's no synchronization on writes.
//
// Sort:    sort the vector by mid (single-threaded; total_keys * log() is
//          tiny next to the encryption work).
//
// Phase 2: for every candidate keyB, compute mid' = D_keyB(ciphertext),
//          binary-search for it in the sorted table.  Hits are validated
//          against the optional second PT/CT pair, then published via
//          compare_exchange so only the first match wins.
// ----------------------------------------------------------------------------
CrackResult run_cpu_mitm(int mitm_bits, bool multi_pair) {
    CrackResult res;
    res.cipher = "Double DES";
    res.method = "CPU MITM (" + std::to_string(mitm_bits) + " bits)";
    res.found  = false;

    // ── Build known PT/CT pair ───────────────────────────────────────────────
    const uint64_t KEY_MASK = (mitm_bits >= 64)
                              ? UINT64_MAX
                              : ((1ULL << mitm_bits) - 1ULL);

    const uint64_t true_keyA   = 0x00000000000000FEULL & KEY_MASK;
    const uint64_t true_keyB   = 0x0000000000000004ULL & KEY_MASK;
    const uint64_t plaintext1  = 0x1000000000000001ULL;
    const uint64_t ciphertext1 = double_des_encrypt(plaintext1, true_keyA, true_keyB);

    uint64_t plaintext2      = 0ULL;
    uint64_t ciphertext2_ref = 0ULL;
    if (multi_pair) {
        plaintext2      = 0xDEADBEEFCAFEBABEULL;
        ciphertext2_ref = double_des_encrypt(plaintext2, true_keyA, true_keyB);
    }

    const uint64_t total_keys = 1ULL << mitm_bits;
    const int      nthreads   = pick_thread_count();

    printf("\n  Plaintext  : 0x%016llX\n", (unsigned long long)plaintext1);
    printf(  "  Ciphertext : 0x%016llX\n", (unsigned long long)ciphertext1);
    printf(  "  Keyspace   : 2 x 2^%d single-DES ops (vs 2^%d brute force)\n",
             mitm_bits, 2 * mitm_bits);
    printf(  "  Threads    : %d\n", nthreads);
    if (multi_pair)
        printf("  Mode       : Multi-pair (false-positive check enabled)\n");

    Progress prog;
    progress_start(&prog, "Double-DES MITM Attack", total_keys * 2ULL);

    // Shared progress counter ticked by workers; a monitor thread polls it
    // and redraws the bar so only one thread writes to stdout.
    std::atomic<uint64_t> phase_progress(0);
    std::atomic<bool>     monitor_stop(false);
    std::thread monitor([&]() {
        while (!monitor_stop.load(std::memory_order_relaxed)) {
            progress_update(&prog, phase_progress.load(std::memory_order_relaxed));
            std::this_thread::sleep_for(std::chrono::milliseconds(80));
        }
    });

    double t0 = wall_time_sec();

    struct Entry { uint64_t mid; uint64_t keyA; };
    std::vector<Entry> table(total_keys);

    // ── Phase 1: parallel build ──────────────────────────────────────────────
    {
        std::vector<std::thread> pool;
        pool.reserve(nthreads);
        for (int tid = 0; tid < nthreads; tid++) {
            pool.emplace_back([&, tid]() {
                uint64_t chunk = (total_keys + nthreads - 1) / nthreads;
                uint64_t start = (uint64_t)tid * chunk;
                uint64_t end   = std::min(start + chunk, total_keys);

                uint64_t sub[16];
                uint64_t local = 0;
                for (uint64_t ka = start; ka < end; ka++) {
                    generate_subkeys(ka, sub);
                    table[ka].mid  = des_encrypt(plaintext1, sub);
                    table[ka].keyA = ka;

                    if (((++local) & 0xFFFF) == 0)
                        phase_progress.fetch_add(0x10000, std::memory_order_relaxed);
                }
                phase_progress.fetch_add(local & 0xFFFF, std::memory_order_relaxed);
            });
        }
        for (auto& t : pool) t.join();
    }

    // Snap the bar to exactly 50% before the sort phase
    phase_progress.store(total_keys, std::memory_order_relaxed);

    // ── Sort by mid ──────────────────────────────────────────────────────────
    std::sort(table.begin(), table.end(),
              [](const Entry& a, const Entry& b) { return a.mid < b.mid; });

    // ── Phase 2: parallel search ─────────────────────────────────────────────
    std::atomic<uint64_t> found_keyA(UINT64_MAX);
    std::atomic<uint64_t> found_keyB(UINT64_MAX);
    {
        std::vector<std::thread> pool;
        pool.reserve(nthreads);
        for (int tid = 0; tid < nthreads; tid++) {
            pool.emplace_back([&, tid]() {
                uint64_t chunk = (total_keys + nthreads - 1) / nthreads;
                uint64_t start = (uint64_t)tid * chunk;
                uint64_t end   = std::min(start + chunk, total_keys);

                uint64_t sub[16];
                uint64_t local = 0;
                for (uint64_t kb = start; kb < end; kb++) {
                    if (found_keyA.load(std::memory_order_relaxed) != UINT64_MAX)
                        return;

                    generate_subkeys(kb, sub);
                    uint64_t mid = des_decrypt(ciphertext1, sub);

                    auto it = std::lower_bound(
                        table.begin(), table.end(), mid,
                        [](const Entry& e, uint64_t v) { return e.mid < v; });

                    while (it != table.end() && it->mid == mid) {
                        uint64_t ka = it->keyA;
                        if (!multi_pair ||
                            double_des_encrypt(plaintext2, ka, kb) == ciphertext2_ref)
                        {
                            uint64_t expected = UINT64_MAX;
                            if (found_keyA.compare_exchange_strong(expected, ka)) {
                                found_keyB.store(kb, std::memory_order_relaxed);
                            }
                            return;
                        }
                        ++it;
                    }

                    if (((++local) & 0xFFFF) == 0)
                        phase_progress.fetch_add(0x10000, std::memory_order_relaxed);
                }
                phase_progress.fetch_add(local & 0xFFFF, std::memory_order_relaxed);
            });
        }
        for (auto& t : pool) t.join();
    }

    monitor_stop.store(true, std::memory_order_relaxed);
    monitor.join();

    double elapsed = wall_time_sec() - t0;

    bool found = (found_keyA.load() != UINT64_MAX);
    progress_finish(&prog, found);

    res.keys_tested  = phase_progress.load();
    res.elapsed_sec  = elapsed;
    res.keys_per_sec = (elapsed > 0.0) ? (double)res.keys_tested / elapsed : 0.0;

    if (found) {
        res.found = true;
        char buf[64];
        snprintf(buf, sizeof(buf), "KeyA=0x%016llX  KeyB=0x%016llX",
                 (unsigned long long)found_keyA.load(),
                 (unsigned long long)found_keyB.load());
        res.key_str = buf;

        printf("\n  \033[92mKey found!\033[0m\n");
        printf("    Key A : 0x%016llX\n", (unsigned long long)found_keyA.load());
        printf("    Key B : 0x%016llX\n", (unsigned long long)found_keyB.load());
    } else {
        printf("\n  \033[93mKey not found in search space.\033[0m\n");
    }

    printf("  Keys tested : %llu  in %.2fs  (%.1f M/s)\n",
           (unsigned long long)res.keys_tested,
           elapsed,
           res.keys_per_sec / 1e6);

    return res;
}

// ----------------------------------------------------------------------------
// run_cpu_bruteforce
//
// Exhaustive Double-DES key search over keyA in [0, 2^compare_bits) and
// keyB in [0, 2^compare_bits).  The outer keyA range is sliced across worker
// threads; an atomic flag stops everyone the moment any thread finds the key.
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

    const uint64_t true_keyA   = 0x00000000000000FEULL & KEY_MASK;
    const uint64_t true_keyB   = 0x0000000000000001ULL & KEY_MASK;
    const uint64_t plaintext1  = 0x1000000000000001ULL;
    const uint64_t ciphertext1 = double_des_encrypt(plaintext1, true_keyA, true_keyB);

    uint64_t plaintext2      = 0ULL;
    uint64_t ciphertext2_ref = 0ULL;
    if (multi_pair) {
        plaintext2      = 0xDEADBEEFCAFEBABEULL;
        ciphertext2_ref = double_des_encrypt(plaintext2, true_keyA, true_keyB);
    }

    const uint64_t total_keyA = 1ULL << compare_bits;
    const uint64_t total_keyB = 1ULL << compare_bits;
    const uint64_t total_keys = total_keyA * total_keyB;
    const int      nthreads   = pick_thread_count();

    printf("\n  Plaintext  : 0x%016llX\n", (unsigned long long)plaintext1);
    printf(  "  Ciphertext : 0x%016llX\n", (unsigned long long)ciphertext1);
    printf(  "  Keyspace   : 2^%d x 2^%d = 2^%d combinations\n",
             compare_bits, compare_bits, 2 * compare_bits);
    printf(  "  Threads    : %d\n", nthreads);
    if (multi_pair)
        printf("  Mode       : Multi-pair (false-positive check enabled)\n");

    Progress prog;
    progress_start(&prog, "Double-DES Brute-Force", total_keys);

    std::atomic<uint64_t> keys_tested_atom(0);
    std::atomic<bool>     found_flag(false);
    std::atomic<uint64_t> found_keyA_atom(0);
    std::atomic<uint64_t> found_keyB_atom(0);

    std::atomic<bool> monitor_stop(false);
    std::thread monitor([&]() {
        while (!monitor_stop.load(std::memory_order_relaxed)) {
            progress_update(&prog, keys_tested_atom.load(std::memory_order_relaxed));
            std::this_thread::sleep_for(std::chrono::milliseconds(80));
        }
    });

    double t0 = wall_time_sec();

    {
        std::vector<std::thread> pool;
        pool.reserve(nthreads);
        for (int tid = 0; tid < nthreads; tid++) {
            pool.emplace_back([&, tid]() {
                uint64_t chunk    = (total_keyA + nthreads - 1) / nthreads;
                uint64_t ka_start = (uint64_t)tid * chunk;
                uint64_t ka_end   = std::min(ka_start + chunk, total_keyA);

                uint64_t sub1[16], sub2[16];
                uint64_t local = 0;

                for (uint64_t ka = ka_start;
                     ka < ka_end && !found_flag.load(std::memory_order_relaxed);
                     ka++)
                {
                    generate_subkeys(ka, sub1);

                    for (uint64_t kb = 0;
                         kb < total_keyB && !found_flag.load(std::memory_order_relaxed);
                         kb++)
                    {
                        generate_subkeys(kb, sub2);
                        uint64_t ct_try = des_encrypt(des_encrypt(plaintext1, sub1), sub2);

                        if (ct_try == ciphertext1) {
                            if (!multi_pair ||
                                double_des_encrypt(plaintext2, ka, kb) == ciphertext2_ref)
                            {
                                bool expected = false;
                                if (found_flag.compare_exchange_strong(expected, true)) {
                                    found_keyA_atom.store(ka, std::memory_order_relaxed);
                                    found_keyB_atom.store(kb, std::memory_order_relaxed);
                                }
                                keys_tested_atom.fetch_add(local & 0xFFFF,
                                                           std::memory_order_relaxed);
                                return;
                            }
                        }

                        if (((++local) & 0xFFFF) == 0)
                            keys_tested_atom.fetch_add(0x10000,
                                                       std::memory_order_relaxed);
                    }
                }
                keys_tested_atom.fetch_add(local & 0xFFFF,
                                           std::memory_order_relaxed);
            });
        }
        for (auto& t : pool) t.join();
    }

    monitor_stop.store(true, std::memory_order_relaxed);
    monitor.join();

    bool found = found_flag.load();
    progress_finish(&prog, found);

    double elapsed = wall_time_sec() - t0;

    res.keys_tested  = keys_tested_atom.load();
    res.elapsed_sec  = elapsed;
    res.keys_per_sec = (elapsed > 0.0) ? (double)res.keys_tested / elapsed : 0.0;

    if (found) {
        res.found = true;
        uint64_t found_keyA = found_keyA_atom.load();
        uint64_t found_keyB = found_keyB_atom.load();
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
           (unsigned long long)res.keys_tested,
           elapsed,
           res.keys_per_sec / 1e6);

    return res;
}
