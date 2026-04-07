#pragma once
// ============================================================================
// des_cpu.h -- CPU-side DES/Double-DES engine
//
// Implementation by Jose (see src/des_cpu.cpp).
// Provides single DES encrypt/decrypt and Double-DES encrypt.
//
// MUST call des_cpu_init() once before any other function here.
// main() already does this via ui_init().
// ============================================================================
#include <cstdint>

// Must be called once at program start to pre-compute the SP-box table.
void des_cpu_init();

// Generate the 16 48-bit subkeys from a 64-bit DES key.
void generate_subkeys(uint64_t key, uint64_t subkeys[16]);

// Single DES encrypt/decrypt using a pre-generated subkey schedule.
uint64_t des_encrypt(uint64_t block, uint64_t subkeys[16]);
uint64_t des_decrypt(uint64_t block, uint64_t subkeys[16]);

// Double DES: encrypt(key1) then encrypt(key2).
// Convenience wrapper — generates both subkey schedules internally.
uint64_t double_des_encrypt(uint64_t plaintext, uint64_t key1, uint64_t key2);
