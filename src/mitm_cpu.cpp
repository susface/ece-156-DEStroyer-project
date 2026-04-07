// ============================================================================
// mitm_cpu.cpp -- CPU implementations of MITM and Brute-Force attacks
// ============================================================================
#include "ciphers.h"
#include "des_cpu.h"
#include "progress.h"
#include <string>

// ----------------------------------------------------------------------------
// run_cpu_mitm
// ----------------------------------------------------------------------------
CrackResult run_cpu_mitm(int mitm_bits, bool multi_pair) {
    CrackResult res;
    res.cipher = "Double DES";
    res.method = "CPU MITM (" + std::to_string(mitm_bits) + " bits)";
    res.found = false;

    return res;
}

// ----------------------------------------------------------------------------
// run_cpu_bruteforce
// ----------------------------------------------------------------------------
CrackResult run_cpu_bruteforce(int compare_bits, bool multi_pair) {
    CrackResult res;
    res.cipher = "Double DES";
    res.method = "CPU Brute-Force (" + std::to_string(compare_bits) + " bits)";
    res.found = false;

    return res;
}
