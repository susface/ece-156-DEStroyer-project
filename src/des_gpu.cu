// ============================================================================
// des_gpu.cu -- DES GPU Brute-Force (Option 6)
//
// Architecture:
//   Phase  : single DES, exhaustive key search over 2^N compact key indices
//   GPU job: each CUDA thread tests one key index
//   SP tables loaded into shared memory at block launch (2 KB / block)
//   IP/FP   are factored out of the hot path entirely:
//     - IP(plaintext)  computed once on host → L0, R0 passed to kernel
//     - IP(ciphertext) computed once on host → expR16, expL16
//     - kernel compares R,L after 16 rounds against (expR16, expL16)
//     - no IP/FP tables needed inside the kernel
//  Done entirerly by Brian
// ============================================================================
#ifdef HAVE_CUDA

#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4819) // character not in current code page
#pragma warning(disable : 4996) // deprecated declarations
// Force CCCL to treat this TU as a system header, suppressing its diagnostics
#define _CCCL_IMPLICIT_SYSTEM_HEADER_MSVC
#endif

#include <algorithm>
#include <atomic>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>
#include <thread>
#include <thrust/device_vector.h>
#include <thrust/execution_policy.h>
#include <thrust/sort.h>
#include <vector>

#ifdef _MSC_VER
#pragma warning(pop)
#endif
#include "ciphers.h"
#include "common.h"
#include "des_cpu.h"
#include "progress.h"

// Color macros must be #defines (not const char* variables) so that nvcc can
// perform compile-time string literal concatenation in printf calls.
#define RESET "\033[0m"
#define DIM "\033[2m"
#define BRED "\033[91m"
#define BGREEN "\033[92m"
#define BYELLOW "\033[93m"
#define BCYAN "\033[96m"
#define BWHITE "\033[97m"

// ============================================================================
// DES reference tables  (used both on host and, via constant mem, on device)
// ============================================================================

// S-boxes: SBOX[s][64], row-major (row 0 first).  row = (b5<<1)|b0, col =
// b4..b1
static const uint8_t SBOX[8][64] = {
    // S1
    {14, 4,  13, 1, 2,  15, 11, 8,  3,  10, 6,  12, 5,  9,  0, 7,
     0,  15, 7,  4, 14, 2,  13, 1,  10, 6,  12, 11, 9,  5,  3, 8,
     4,  1,  14, 8, 13, 6,  2,  11, 15, 12, 9,  7,  3,  10, 5, 0,
     15, 12, 8,  2, 4,  9,  1,  7,  5,  11, 3,  14, 10, 0,  6, 13},
    // S2
    {15, 1,  8,  14, 6,  11, 3,  4,  9,  7, 2,  13, 12, 0, 5,  10,
     3,  13, 4,  7,  15, 2,  8,  14, 12, 0, 1,  10, 6,  9, 11, 5,
     0,  14, 7,  11, 10, 4,  13, 1,  5,  8, 12, 6,  9,  3, 2,  15,
     13, 8,  10, 1,  3,  15, 4,  2,  11, 6, 7,  12, 0,  5, 14, 9},
    // S3
    {10, 0,  9,  14, 6, 3,  15, 5,  1,  13, 12, 7,  11, 4,  2,  8,
     13, 7,  0,  9,  3, 4,  6,  10, 2,  8,  5,  14, 12, 11, 15, 1,
     13, 6,  4,  9,  8, 15, 3,  0,  11, 1,  2,  12, 5,  10, 14, 7,
     1,  10, 13, 0,  6, 9,  8,  7,  4,  15, 14, 3,  11, 5,  2,  12},
    // S4
    {7,  13, 14, 3, 0,  6,  9,  10, 1,  2, 8, 5,  11, 12, 4,  15,
     13, 8,  11, 5, 6,  15, 0,  3,  4,  7, 2, 12, 1,  10, 14, 9,
     10, 6,  9,  0, 12, 11, 7,  13, 15, 1, 3, 14, 5,  2,  8,  4,
     3,  15, 0,  6, 10, 1,  13, 8,  9,  4, 5, 11, 12, 7,  2,  14},
    // S5
    {2,  12, 4,  1,  7,  10, 11, 6,  8,  5,  3,  15, 13, 0, 14, 9,
     14, 11, 2,  12, 4,  7,  13, 1,  5,  0,  15, 10, 3,  9, 8,  6,
     4,  2,  1,  11, 10, 13, 7,  8,  15, 9,  12, 5,  6,  3, 0,  14,
     11, 8,  12, 7,  1,  14, 2,  13, 6,  15, 0,  9,  10, 4, 5,  3},
    // S6
    {12, 1,  10, 15, 9, 2,  6,  8,  0,  13, 3,  4,  14, 7,  5,  11,
     10, 15, 4,  2,  7, 12, 9,  5,  6,  1,  13, 14, 0,  11, 3,  8,
     9,  14, 15, 5,  2, 8,  12, 3,  7,  0,  4,  10, 1,  13, 11, 6,
     4,  3,  2,  12, 9, 5,  15, 10, 11, 14, 1,  7,  6,  0,  8,  13},
    // S7
    {4,  11, 2,  14, 15, 0, 8,  13, 3,  12, 9, 7,  5,  10, 6, 1,
     13, 0,  11, 7,  4,  9, 1,  10, 14, 3,  5, 12, 2,  15, 8, 6,
     1,  4,  11, 13, 12, 3, 7,  14, 10, 15, 6, 8,  0,  5,  9, 2,
     6,  11, 13, 8,  1,  4, 10, 7,  9,  5,  0, 15, 14, 2,  3, 12},
    // S8
    {13, 2,  8,  4, 6,  15, 11, 1,  10, 9,  3,  14, 5,  0,  12, 7,
     1,  15, 13, 8, 10, 3,  7,  4,  12, 5,  6,  11, 0,  14, 9,  2,
     7,  11, 4,  1, 9,  12, 14, 2,  0,  6,  10, 13, 15, 3,  5,  8,
     2,  1,  14, 7, 4,  10, 8,  13, 15, 12, 9,  0,  3,  5,  6,  11}};

// P-box: PBOX[i] = 1-indexed DES output position for P-box input bit (i+1)
static const uint8_t PBOX[32] = {16, 7, 20, 21, 29, 12, 28, 17, 1,  15, 23,
                                 26, 5, 18, 31, 10, 2,  8,  24, 14, 32, 27,
                                 3,  9, 19, 13, 30, 6,  22, 11, 4,  25};

// PC-1: extract C0 (28 bits) from 64-bit key
// Each value is a 1-indexed DES key bit number
static const uint8_t PC1C[28] = {57, 49, 41, 33, 25, 17, 9,  1,  58, 50,
                                 42, 34, 26, 18, 10, 2,  59, 51, 43, 35,
                                 27, 19, 11, 3,  60, 52, 44, 36};

// PC-1: extract D0 (28 bits)
static const uint8_t PC1D[28] = {63, 55, 47, 39, 31, 23, 15, 7,  62, 54,
                                 46, 38, 30, 22, 14, 6,  61, 53, 45, 37,
                                 29, 21, 13, 5,  28, 20, 12, 4};

// PC-2: 56-bit CD → 48-bit subkey
// Values are 1-indexed positions in the 56-bit CD (C=1..28, D=29..56)
static const uint8_t PC2[48] = {14, 17, 11, 24, 1,  5,  3,  28, 15, 6,  21, 10,
                                23, 19, 12, 4,  26, 8,  16, 7,  27, 20, 13, 2,
                                41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
                                44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32};

// Round shift amounts
static const uint8_t SHIFTS[16] = {1, 1, 2, 2, 2, 2, 2, 2,
                                   1, 2, 2, 2, 2, 2, 2, 1};

// IP table: IP[i] = 1-indexed DES input bit → output bit i+1 (0-indexed from
// MSB)
static const uint8_t IP_TBL[64] = {
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9,  1, 59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7};

// FP table (inverse of IP)
static const uint8_t FP_TBL[64] = {
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9,  49, 17, 57, 25};

// ============================================================================
// CUDA constant memory (uploaded once before kernel launch)
// ============================================================================
__constant__ uint32_t d_sp[8][64]; // 2048 bytes — combined SP tables
__constant__ uint8_t d_pc1c[28];   //   28 bytes
__constant__ uint8_t d_pc1d[28];   //   28 bytes
__constant__ uint8_t d_pc2[48];    //   48 bytes
__constant__ uint8_t d_shifts[16]; //   16 bytes

// ============================================================================
// SP table generation (host side only)
//
// SP[s][in] = 32-bit word with the 4 S-box s output bits placed in their
//             final P-box output positions, ready to XOR directly into
//             the DES round result.
//
// Convention: DES bit n = uint32_t bit (32-n) [bit 31 = DES bit 1 = MSB]
// ============================================================================
static void compute_sp_tables(uint32_t sp[8][64]) {
  for (int s = 0; s < 8; s++) {
    for (int in = 0; in < 64; in++) {
      // S-box indexing: row = bit5,bit0; col = bits4..1
      int row = ((in & 0x20) >> 4) | (in & 0x01);
      int col = (in >> 1) & 0x0F;
      int val = SBOX[s][row * 16 + col]; // 4-bit output 0..15

      // Place 4-bit S-box output at pre-P DES positions (4s+1)..(4s+4),
      // 1-indexed from MSB.  val.bit3 (MSB) lands at DES position (4s+1)
      // and val.bit0 (LSB) lands at DES position (4s+4).
      //
      // Array convention: DES position p (1-indexed) <-> uint32_t bit (32-p).
      uint32_t pre_p = (uint32_t)val << (28 - 4 * s);

      // Apply the standard P-box forward: output_bit[i+1] = input_bit[PBOX[i]]
      // (both 1-indexed from MSB).  Same direction as CPU des_cpu.cpp's
      // permute() in init_sp_boxes(); the previous version of this loop used
      // PBOX in the inverse direction, producing a self-consistent but
      // non-standard f-function that broke the CPU-hybrid MITM lookup.
      uint32_t sp_val = 0;
      for (int i = 0; i < 32; i++) {
        if ((pre_p >> (32 - PBOX[i])) & 1U) {
          sp_val |= 1U << (31 - i);
        }
      }
      sp[s][in] = sp_val;
    }
  }
}

// ============================================================================
// Host-side helpers
// ============================================================================

// 64-bit bit-permutation using a 64-entry table of 1-indexed source positions
static uint64_t apply_perm64(uint64_t x, const uint8_t *tbl) {
  uint64_t result = 0;
  for (int i = 0; i < 64; i++) {
    result |= ((x >> (64 - tbl[i])) & 1ULL) << (63 - i);
  }
  return result;
}

// Map compact N-bit index to a valid 64-bit DES key.
// Non-parity positions (7 per byte × 8 bytes = 56):
//   byte b, slot j → DES bit b*8+j+1   (j = 0..6)
// Parity bits (DES 8,16,24,32,40,48,56,64) are set to 1.
static uint64_t key_index_to_des_key_host(uint64_t idx) {
  uint64_t key = 0x0101010101010101ULL;
  for (int i = 0; i < 56; i++) {
    if ((idx >> i) & 1ULL) {
      int des_bit = (i / 7) * 8 + (i % 7) + 1;
      key |= 1ULL << (64 - des_bit);
    }
  }
  return key;
}

// Host-side f function (same logic as device, uses host SP tables)
static uint32_t des_f_host(uint32_t R, uint64_t K, const uint32_t sp[8][64]) {
  // Group 0: E bits from R DES bits 32,1,2,3,4,5
  uint32_t g0 = ((R & 1U) << 5) | ((R >> 27) & 0x1FU);
  g0 ^= (uint32_t)((K >> 42) & 0x3FU);
  uint32_t result = sp[0][g0];

  // Groups 1–6: (R >> (27-4g)) & 0x3F XOR subkey group g
  for (int g = 1; g <= 6; g++) {
    uint32_t gi = (R >> (27 - 4 * g)) & 0x3FU;
    gi ^= (uint32_t)((K >> (42 - 6 * g)) & 0x3FU);
    result ^= sp[g][gi];
  }

  // Group 7: E bits from R DES bits 28,29,30,31,32,1
  uint32_t g7 = ((R & 0x1FU) << 1) | ((R >> 31) & 1U);
  g7 ^= (uint32_t)(K & 0x3FU);
  result ^= sp[7][g7];

  return result;
}

// Full host-side DES encrypt (used to generate target ciphertext)
static uint64_t des_encrypt_host(uint64_t block, uint64_t key,
                                 const uint32_t sp[8][64]) {
  // IP
  uint64_t ip_out = apply_perm64(block, IP_TBL);
  uint32_t L = (uint32_t)(ip_out >> 32);
  uint32_t R = (uint32_t)(ip_out & 0xFFFFFFFFULL);

  // PC-1
  uint32_t C = 0, D = 0;
  for (int i = 0; i < 28; i++) {
    C |= (uint32_t)((key >> (64 - PC1C[i])) & 1U) << (27 - i);
    D |= (uint32_t)((key >> (64 - PC1D[i])) & 1U) << (27 - i);
  }

  // 16 rounds
  for (int r = 0; r < 16; r++) {
    int s = SHIFTS[r];
    C = ((C << s) | (C >> (28 - s))) & 0x0FFFFFFFU;
    D = ((D << s) | (D >> (28 - s))) & 0x0FFFFFFFU;

    uint64_t CD = ((uint64_t)C << 28) | D;
    uint64_t K = 0;
    for (int i = 0; i < 48; i++) {
      K |= ((CD >> (56 - PC2[i])) & 1ULL) << (47 - i);
    }

    uint32_t tmp = R;
    R = L ^ des_f_host(R, K, sp);
    L = tmp;
  }

  // FP is applied to (R16 || L16)
  uint64_t pre_fp = ((uint64_t)R << 32) | L;
  return apply_perm64(pre_fp, FP_TBL);
}

// ============================================================================
// CUDA device functions
// ============================================================================

__device__ __forceinline__ uint64_t key_index_to_des_key_dev(uint64_t idx) {
  uint64_t key = 0x0101010101010101ULL;
  for (int i = 0; i < 56; i++) {
    if ((idx >> i) & 1ULL) {
      int des_bit = (i / 7) * 8 + (i % 7) + 1;
      key |= 1ULL << (64 - des_bit);
    }
  }
  return key;
}

__device__ __forceinline__ uint32_t des_f_dev(uint32_t R, uint64_t K,
                                              const uint32_t sp[8][64]) {
  // Group 0
  uint32_t g0 = ((R & 1U) << 5) | ((R >> 27) & 0x1FU);
  g0 ^= (uint32_t)((K >> 42) & 0x3FU);
  uint32_t result = sp[0][g0];

  // Groups 1-6
  for (int g = 1; g <= 6; g++) {
    uint32_t gi = (R >> (27 - 4 * g)) & 0x3FU;
    gi ^= (uint32_t)((K >> (42 - 6 * g)) & 0x3FU);
    result ^= sp[g][gi];
  }

  // Group 7
  uint32_t g7 = ((R & 0x1FU) << 1) | ((R >> 31) & 1U);
  g7 ^= (uint32_t)(K & 0x3FU);
  result ^= sp[7][g7];

  return result;
}

// ============================================================================
// CUDA kernel
//
// Each thread tests one key index within the slice [key_offset, key_offset+N).
// key_offset allows the host to launch the kernel in chunks so it can update
// the progress bar between each chunk without sacrificing GPU utilisation.
//
// Pair 1 (L0/R0/expR16/expL16): primary known PT/CT, always checked.
// Pair 2 (L0b/R0b/expR16b/expL16b): secondary PT/CT for false-positive
//   elimination.  When multi_pair=false the host passes identical values so
//   the second check is always trivially true (one redundant DES, no branch).
// ============================================================================
__global__ void des_bruteforce_kernel(uint64_t key_offset, uint32_t L0,
                                      uint32_t R0, uint32_t expR16,
                                      uint32_t expL16, uint32_t L0b,
                                      uint32_t R0b, uint32_t expR16b,
                                      uint32_t expL16b, uint64_t total_keys,
                                      uint64_t *d_found_key) {
  // ── Load SP tables into shared memory (2 KB per block) ──────────────────
  __shared__ uint32_t sp[8][64];
  for (int i = threadIdx.x; i < 512; i += blockDim.x) {
    sp[i >> 6][i & 63] = d_sp[i >> 6][i & 63];
  }
  __syncthreads();

  // ── Absolute key index for this thread ───────────────────────────────────
  uint64_t kid = key_offset + (uint64_t)blockIdx.x * (uint64_t)blockDim.x +
                 (uint64_t)threadIdx.x;
  if (kid >= total_keys)
    return;

  // ── Convert compact index → 64-bit DES key ───────────────────────────────
  uint64_t key = key_index_to_des_key_dev(kid);

  // ── PC-1: key → C0, D0 (28 bits each) ───────────────────────────────────
  uint32_t C = 0, D = 0;
  for (int i = 0; i < 28; i++) {
    C |= (uint32_t)((key >> (64 - d_pc1c[i])) & 1U) << (27 - i);
    D |= (uint32_t)((key >> (64 - d_pc1d[i])) & 1U) << (27 - i);
  }

  // Snapshot initial C/D so we can reuse for pair 2 without re-running PC-1
  uint32_t C0snap = C, D0snap = D;

  // ── Pair 1: 16 DES rounds ─────────────────────────────────────────────────
  uint32_t L = L0, R = R0;
  for (int r = 0; r < 16; r++) {
    int s = (int)d_shifts[r];
    C = ((C << s) | (C >> (28 - s))) & 0x0FFFFFFFU;
    D = ((D << s) | (D >> (28 - s))) & 0x0FFFFFFFU;

    uint64_t CD = ((uint64_t)C << 28) | D;
    uint64_t K = 0;
    for (int i = 0; i < 48; i++)
      K |= ((CD >> (56 - d_pc2[i])) & 1ULL) << (47 - i);

    uint32_t tmp = R;
    R = L ^ des_f_dev(R, K, sp);
    L = tmp;
  }

  if (R != expR16 || L != expL16)
    return;

  // ── Pair 2: reset key schedule, run again on second PT ────────────────────
  C = C0snap;
  D = D0snap;
  L = L0b;
  R = R0b;
  for (int r = 0; r < 16; r++) {
    int s = (int)d_shifts[r];
    C = ((C << s) | (C >> (28 - s))) & 0x0FFFFFFFU;
    D = ((D << s) | (D >> (28 - s))) & 0x0FFFFFFFU;

    uint64_t CD = ((uint64_t)C << 28) | D;
    uint64_t K = 0;
    for (int i = 0; i < 48; i++)
      K |= ((CD >> (56 - d_pc2[i])) & 1ULL) << (47 - i);

    uint32_t tmp = R;
    R = L ^ des_f_dev(R, K, sp);
    L = tmp;
  }

  if (R != expR16b || L != expL16b)
    return;

  // ── Both pairs matched ────────────────────────────────────────────────────
  atomicCAS((unsigned long long *)d_found_key, (unsigned long long)UINT64_MAX,
            (unsigned long long)kid);
}

// ============================================================================
// Host wrapper:  run_des_gpu_bruteforce
// ============================================================================

// xorshift64 — fast PRNG seeded from the Windows tick counter.
// Used to place the target key at a random position so timing is
// nondeterministic and the GPU always has to work for it.
static uint64_t xorshift64(uint64_t &state) {
  state ^= state << 13;
  state ^= state >> 7;
  state ^= state << 17;
  return state;
}

CrackResult run_des_gpu_bruteforce(int bits, bool multi_pair) {
  CrackResult result;
  result.cipher = "DES";
  result.method = "gpu";

  // ── Build SP tables (host) and upload to constant memory ─────────────────
  static uint32_t h_sp[8][64];
  static bool sp_ready = false;
  if (!sp_ready) {
    compute_sp_tables(h_sp);
    sp_ready = true;
  }
  cudaMemcpyToSymbol(d_sp, h_sp, sizeof(h_sp));
  cudaMemcpyToSymbol(d_pc1c, PC1C, sizeof(PC1C));
  cudaMemcpyToSymbol(d_pc1d, PC1D, sizeof(PC1D));
  cudaMemcpyToSymbol(d_pc2, PC2, sizeof(PC2));
  cudaMemcpyToSymbol(d_shifts, SHIFTS, sizeof(SHIFTS));

  // ── Random target key ─────────────────────────────────────────────────────
  // Seed from the Windows performance counter for per-run randomness.
  // Mask to [1, total_keys-1] so it's never trivially the first key.
  const uint64_t total_keys = 1ULL << bits;
  uint64_t rng_state = GetTickCount64();
  if (rng_state == 0)
    rng_state = 0xDEADBEEFCAFEULL; // fallback if tick=0
  uint64_t target_idx = (xorshift64(rng_state) % (total_keys - 1)) + 1;

  uint64_t target_key = key_index_to_des_key_host(target_idx);

  // ── Known PT/CT pair 1 ────────────────────────────────────────────────────
  const uint64_t PLAINTEXT = 0x0123456789ABCDEFULL;
  uint64_t ciphertext = des_encrypt_host(PLAINTEXT, target_key, h_sp);

  uint64_t ip_pt = apply_perm64(PLAINTEXT, IP_TBL);
  uint32_t L0 = (uint32_t)(ip_pt >> 32);
  uint32_t R0 = (uint32_t)(ip_pt & 0xFFFFFFFFULL);
  uint64_t ip_ct = apply_perm64(ciphertext, IP_TBL);
  uint32_t expR16 = (uint32_t)(ip_ct >> 32);
  uint32_t expL16 = (uint32_t)(ip_ct & 0xFFFFFFFFULL);

  // ── Known PT/CT pair 2 (for multi_pair false-positive elimination) ────────
  // When multi_pair=false, pass identical values so the second check in the
  // kernel is always trivially true — one extra DES per candidate, no branch.
  uint32_t L0b, R0b, expR16b, expL16b;
  const uint64_t PLAINTEXT2 = 0xFEDCBA9876543210ULL;
  uint64_t ciphertext2 = 0;
  if (multi_pair) {
    ciphertext2 = des_encrypt_host(PLAINTEXT2, target_key, h_sp);
    uint64_t ip_pt2 = apply_perm64(PLAINTEXT2, IP_TBL);
    L0b = (uint32_t)(ip_pt2 >> 32);
    R0b = (uint32_t)(ip_pt2 & 0xFFFFFFFFULL);
    uint64_t ip_ct2 = apply_perm64(ciphertext2, IP_TBL);
    expR16b = (uint32_t)(ip_ct2 >> 32);
    expL16b = (uint32_t)(ip_ct2 & 0xFFFFFFFFULL);
  } else {
    L0b = L0;
    R0b = R0;
    expR16b = expR16;
    expL16b = expL16;
  }

  // ── Launch parameters ─────────────────────────────────────────────────────
  const int THREADS = 256;

  printf("\n");
  printf(
      "  " BCYAN
      "+----------------------------------------------------------+\n" RESET);
  printf("  " BCYAN "|" BWHITE "  DES GPU Brute-Force Attack" BCYAN
         "                               |\n" RESET);
  printf(
      "  " BCYAN
      "+----------------------------------------------------------+\n" RESET);
  printf("  " BCYAN "|" RESET "  Keyspace   : " BYELLOW
         "2^%d = %llu keys\n" RESET,
         bits, (unsigned long long)total_keys);
  printf("  " BCYAN "|" RESET "  Plaintext  : " BYELLOW "0x%016llX\n" RESET,
         (unsigned long long)PLAINTEXT);
  printf("  " BCYAN "|" RESET "  Target idx : " BYELLOW "%llu" DIM
         " (random)\n" RESET,
         (unsigned long long)target_idx);
  printf("  " BCYAN "|" RESET "  Ciphertext : " BYELLOW "0x%016llX\n" RESET,
         (unsigned long long)ciphertext);
  printf("  " BCYAN "|" RESET "  Multi-pair : " BYELLOW "%s\n" RESET,
         multi_pair ? "ENABLED (2 PT/CT pairs)" : "disabled");
  if (multi_pair) {
    printf("  " BCYAN "|" RESET "  Plaintext2 : " BYELLOW "0x%016llX\n" RESET,
           (unsigned long long)PLAINTEXT2);
    printf("  " BCYAN "|" RESET "  Ciphertxt2 : " BYELLOW "0x%016llX\n" RESET,
           (unsigned long long)ciphertext2);
  }
  printf(
      "  " BCYAN
      "+----------------------------------------------------------+\n" RESET);
  fflush(stdout);

  // ── Allocate device memory for found-key output ───────────────────────────
  uint64_t *d_found = nullptr;
  cudaMalloc(&d_found, sizeof(uint64_t));
  uint64_t sentinel = UINT64_MAX;
  cudaMemcpy(d_found, &sentinel, sizeof(uint64_t), cudaMemcpyHostToDevice);

  // ── Chunked kernel launch with live progress bar ──────────────────────────
  // The full keyspace is split into CHUNKS equal slices. After each slice the
  // host syncs, checks if the key was already found (early exit), then calls
  // progress_update so the bar redraws.  Chunk size is always a multiple of
  // THREADS so block boundaries stay aligned.
  //
  // Adding progress to a future CPU/other-GPU attack is the same 3 calls:
  //   progress_start → progress_update (in your loop) → progress_finish

  const int CHUNKS = 64;
  const uint64_t CHUNK_KEYS =
      ((total_keys + CHUNKS - 1) / CHUNKS + THREADS - 1) / THREADS * THREADS;

  Progress prog;
  progress_start(&prog, "DES GPU Brute-Force", total_keys);

  cudaDeviceSynchronize();
  double t0 = wall_time_sec();

  uint64_t keys_done = 0;
  for (int chunk = 0; chunk < CHUNKS && keys_done < total_keys; chunk++) {
    uint64_t offset = (uint64_t)chunk * CHUNK_KEYS;
    uint64_t this_batch = CHUNK_KEYS;
    if (offset + this_batch > total_keys)
      this_batch = total_keys - offset;

    uint64_t chunk_blocks = (this_batch + THREADS - 1) / THREADS;

    des_bruteforce_kernel<<<(uint32_t)chunk_blocks, THREADS>>>(
        offset, L0, R0, expR16, expL16, L0b, R0b, expR16b, expL16b, total_keys,
        d_found);

    cudaDeviceSynchronize();

    keys_done += this_batch;
    progress_update(&prog, keys_done);

    // Early exit: if a key was already found, stop searching
    uint64_t peek = UINT64_MAX;
    cudaMemcpy(&peek, d_found, sizeof(uint64_t), cudaMemcpyDeviceToHost);
    if (peek != UINT64_MAX)
      break;
  }

  double elapsed = wall_time_sec() - t0;

  // ── Retrieve result ───────────────────────────────────────────────────────
  uint64_t found_idx = UINT64_MAX;
  cudaMemcpy(&found_idx, d_found, sizeof(uint64_t), cudaMemcpyDeviceToHost);
  cudaFree(d_found);

  cudaError_t err = cudaGetLastError();
  if (err != cudaSuccess) {
    progress_finish(&prog, false);
    printf("  " BRED "CUDA error: %s\n" RESET, cudaGetErrorString(err));
    return result;
  }

  bool found = (found_idx != UINT64_MAX);
  progress_finish(&prog, found);

  result.keys_tested = keys_done;
  result.elapsed_sec = elapsed;
  result.keys_per_sec = (elapsed > 0.0) ? (double)keys_done / elapsed : 0.0;

  if (found) {
    result.found = true;
    uint64_t found_key = key_index_to_des_key_host(found_idx);
    char buf[64];
    snprintf(buf, sizeof(buf), "0x%016llX  (idx %llu)",
             (unsigned long long)found_key, (unsigned long long)found_idx);
    result.key_str = buf;

    printf("\n");
    printf(
        "  " BGREEN
        "+----------------------------------------------------------+\n" RESET);
    printf("  " BGREEN "|" BWHITE "  KEY FOUND!" BGREEN
           "                                                |\n" RESET);
    printf(
        "  " BGREEN
        "+----------------------------------------------------------+\n" RESET);
    printf("  " BGREEN "|" RESET "  Key index : " BYELLOW "%llu\n" RESET,
           (unsigned long long)found_idx);
    printf("  " BGREEN "|" RESET "  DES key   : " BYELLOW "0x%016llX\n" RESET,
           (unsigned long long)found_key);
    printf("  " BGREEN "|" RESET "  Time      : " BYELLOW "%.4f s\n" RESET,
           elapsed);
    printf("  " BGREEN "|" RESET "  Rate      : " BYELLOW
           "%.3e keys/sec\n" RESET,
           result.keys_per_sec);
    printf("  " BGREEN "+------------------------------------------------------"
           "----+\n\n" RESET);
  } else {
    result.found = false;
    result.key_str = "(not found)";
    printf("\n  " BRED
           "  Key NOT found in 2^%d keyspace (elapsed %.4f s)\n\n" RESET,
           bits, elapsed);
  }

  return result;
}

// ============================================================================
// Option 7: GPU Throughput + AES extrapolation
// ============================================================================
CrackResult run_gpu_throughput(uint64_t n_keys) {
  CrackResult result;
  result.cipher = "DES";
  result.method = "GPU Throughput Test";
  result.found = false;
  result.key_str = "N/A";

  // ── Build SP tables (host) and upload to constant memory ─────────────────
  static uint32_t h_sp[8][64];
  static bool sp_ready = false;
  if (!sp_ready) {
    compute_sp_tables(h_sp);
    sp_ready = true;
  }
  cudaMemcpyToSymbol(d_sp, h_sp, sizeof(h_sp));
  cudaMemcpyToSymbol(d_pc1c, PC1C, sizeof(PC1C));
  cudaMemcpyToSymbol(d_pc1d, PC1D, sizeof(PC1D));
  cudaMemcpyToSymbol(d_pc2, PC2, sizeof(PC2));
  cudaMemcpyToSymbol(d_shifts, SHIFTS, sizeof(SHIFTS));

  // Garbage target values so the branch never hits
  uint32_t L0 = 0xDEADC0DE, R0 = 0xCAFEFEED;
  uint32_t expR16 = 0x11111111, expL16 = 0x22222222;
  uint32_t L0b = L0, R0b = R0, expR16b = expR16, expL16b = expL16;

  const int THREADS = 256;

  printf("\n");
  printf(
      "  " BCYAN
      "+----------------------------------------------------------+\n" RESET);
  printf("  " BCYAN "|" BWHITE "  GPU Throughput Test (Single DES)" BCYAN
         "                         |\n" RESET);
  printf(
      "  " BCYAN
      "+----------------------------------------------------------+\n" RESET);
  printf("  " BCYAN "|" RESET "  Target keys : " BYELLOW "%llu\n" RESET,
         (unsigned long long)n_keys);
  printf(
      "  " BCYAN
      "+----------------------------------------------------------+\n" RESET);
  fflush(stdout);

  uint64_t *d_found = nullptr;
  cudaMalloc(&d_found, sizeof(uint64_t));
  uint64_t sentinel = UINT64_MAX;
  cudaMemcpy(d_found, &sentinel, sizeof(uint64_t), cudaMemcpyHostToDevice);

  const int CHUNKS = 64;
  const uint64_t CHUNK_KEYS =
      ((n_keys + CHUNKS - 1) / CHUNKS + THREADS - 1) / THREADS * THREADS;

  Progress prog;
  progress_start(&prog, "GPU Throughput", n_keys);

  cudaDeviceSynchronize();
  double t0 = wall_time_sec();

  uint64_t keys_done = 0;
  for (int chunk = 0; chunk < CHUNKS && keys_done < n_keys; chunk++) {
    uint64_t offset = (uint64_t)chunk * CHUNK_KEYS;
    uint64_t this_batch = CHUNK_KEYS;
    if (offset + this_batch > n_keys)
      this_batch = n_keys - offset;

    uint64_t chunk_blocks = (this_batch + THREADS - 1) / THREADS;

    des_bruteforce_kernel<<<(uint32_t)chunk_blocks, THREADS>>>(
        offset, L0, R0, expR16, expL16, L0b, R0b, expR16b, expL16b, n_keys,
        d_found);

    cudaDeviceSynchronize();

    keys_done += this_batch;
    progress_update(&prog, keys_done);
  }

  double elapsed = wall_time_sec() - t0;
  cudaFree(d_found);

  progress_finish(&prog, false); // always "not found"

  result.keys_tested = keys_done;
  result.elapsed_sec = elapsed;
  result.keys_per_sec = (elapsed > 0.0) ? (double)keys_done / elapsed : 0.0;

  printf("\n  " BGREEN "  Completed benchmark: %.4f s\n" RESET, elapsed);
  printf("  " BGREEN "  Peak Rate: %.3e keys/sec\n\n" RESET,
         result.keys_per_sec);

  return result;
}

// ============================================================================
// GPU MITM Attack Kernels
// ============================================================================

__global__ void mitm_build_kernel(uint64_t key_offset, uint32_t L0, uint32_t R0,
                                  uint64_t total_keys, uint64_t *d_mids,
                                  uint64_t *d_k1) {
  __shared__ uint32_t sp[8][64];
  for (int i = threadIdx.x; i < 512; i += blockDim.x) {
    sp[i >> 6][i & 63] = d_sp[i >> 6][i & 63];
  }
  __syncthreads();

  uint64_t kid = key_offset + (uint64_t)blockIdx.x * blockDim.x + threadIdx.x;
  if (kid >= total_keys)
    return;

  uint64_t key = key_index_to_des_key_dev(kid);

  uint32_t C = 0, D = 0;
  for (int i = 0; i < 28; i++) {
    C |= (uint32_t)((key >> (64 - d_pc1c[i])) & 1U) << (27 - i);
    D |= (uint32_t)((key >> (64 - d_pc1d[i])) & 1U) << (27 - i);
  }

  uint32_t L = L0, R = R0;
  for (int r = 0; r < 16; r++) {
    int s = (int)d_shifts[r];
    C = ((C << s) | (C >> (28 - s))) & 0x0FFFFFFFU;
    D = ((D << s) | (D >> (28 - s))) & 0x0FFFFFFFU;

    uint64_t CD = ((uint64_t)C << 28) | D;
    uint64_t K = 0;
    for (int i = 0; i < 48; i++)
      K |= ((CD >> (56 - d_pc2[i])) & 1ULL) << (47 - i);

    uint32_t tmp = R;
    R = L ^ des_f_dev(R, K, sp);
    L = tmp;
  }

  uint64_t mid = ((uint64_t)R << 32) | L;
  d_mids[kid] = mid;
  d_k1[kid] = kid;
}

__global__ void
mitm_search_kernel(uint64_t key_offset, uint32_t L0_ct, uint32_t R0_ct,
                   uint32_t L_ct2, uint32_t R_ct2, uint32_t L_pt2,
                   uint32_t R_pt2, bool multi_pair, uint64_t total_keys,
                   const uint64_t *__restrict__ d_mids,
                   const uint64_t *__restrict__ d_k1, uint64_t *d_found_key1,
                   uint64_t *d_found_key2) {
  __shared__ uint32_t sp[8][64];
  for (int i = threadIdx.x; i < 512; i += blockDim.x) {
    sp[i >> 6][i & 63] = d_sp[i >> 6][i & 63];
  }
  __syncthreads();

  uint64_t kid = key_offset + (uint64_t)blockIdx.x * blockDim.x + threadIdx.x;
  if (kid >= total_keys)
    return;

  // Check early exit
  if (*(unsigned long long *)d_found_key1 != UINT64_MAX)
    return;

  uint64_t key = key_index_to_des_key_dev(kid);
  uint32_t C = 0, D = 0;
  for (int i = 0; i < 28; i++) {
    C |= (uint32_t)((key >> (64 - d_pc1c[i])) & 1U) << (27 - i);
    D |= (uint32_t)((key >> (64 - d_pc1d[i])) & 1U) << (27 - i);
  }

  uint64_t subkeys[16];
  for (int r = 0; r < 16; r++) {
    int s = (int)d_shifts[r];
    C = ((C << s) | (C >> (28 - s))) & 0x0FFFFFFFU;
    D = ((D << s) | (D >> (28 - s))) & 0x0FFFFFFFU;

    uint64_t CD = ((uint64_t)C << 28) | D;
    uint64_t K = 0;
    for (int i = 0; i < 48; i++)
      K |= ((CD >> (56 - d_pc2[i])) & 1ULL) << (47 - i);
    subkeys[r] = K;
  }

  uint32_t L = L0_ct, R = R0_ct;
  for (int r = 15; r >= 0; r--) {
    uint32_t tmp = R;
    R = L ^ des_f_dev(R, subkeys[r], sp);
    L = tmp;
  }

  // Extracted exactly matching pre-FP mid
  uint64_t target_mid = ((uint64_t)R << 32) | L;

  long long left = 0, right = total_keys - 1;
  long long match = -1;
  while (left <= right) {
    long long mid_idx = left + (right - left) / 2;
    uint64_t v = d_mids[mid_idx];
    if (v == target_mid) {
      match = mid_idx;
      break;
    } else if (v < target_mid) {
      left = mid_idx + 1;
    } else {
      right = mid_idx - 1;
    }
  }

  if (match != -1) {
    long long start_idx = match;
    while (start_idx > 0 && d_mids[start_idx - 1] == target_mid)
      start_idx--;

    for (long long m = start_idx; m < total_keys && d_mids[m] == target_mid;
         m++) {
      bool valid = true;
      uint64_t found_k1 = d_k1[m];

      if (multi_pair) {
        uint32_t L2 = L_ct2, R2 = R_ct2;
        for (int r = 15; r >= 0; r--) {
          uint32_t tmp = R2;
          R2 = L2 ^ des_f_dev(R2, subkeys[r], sp);
          L2 = tmp;
        }
        uint64_t target_mid2 = ((uint64_t)R2 << 32) | L2;

        uint64_t key1 = key_index_to_des_key_dev(found_k1);
        uint32_t C1 = 0, D1 = 0;
        for (int i = 0; i < 28; i++) {
          C1 |= ((key1 >> (64 - d_pc1c[i])) & 1U) << (27 - i);
          D1 |= ((key1 >> (64 - d_pc1d[i])) & 1U) << (27 - i);
        }
        uint32_t L_p2 = L_pt2, R_p2 = R_pt2;
        for (int r = 0; r < 16; r++) {
          int s = (int)d_shifts[r];
          C1 = ((C1 << s) | (C1 >> (28 - s))) & 0x0FFFFFFFU;
          D1 = ((D1 << s) | (D1 >> (28 - s))) & 0x0FFFFFFFU;
          uint64_t CD1 = ((uint64_t)C1 << 28) | D1;
          uint64_t K1 = 0;
          for (int j = 0; j < 48; j++)
            K1 |= ((CD1 >> (56 - d_pc2[j])) & 1ULL) << (47 - j);
          uint32_t tmp = R_p2;
          R_p2 = L_p2 ^ des_f_dev(R_p2, K1, sp);
          L_p2 = tmp;
        }
        uint64_t calc_mid2 = ((uint64_t)R_p2 << 32) | L_p2;

        if (calc_mid2 != target_mid2)
          valid = false;
      }

      if (valid) {
        atomicCAS((unsigned long long *)d_found_key1, UINT64_MAX,
                  (unsigned long long)found_k1);
        atomicCAS((unsigned long long *)d_found_key2, UINT64_MAX,
                  (unsigned long long)kid);
        break;
      }
    }
  }
}

// ============================================================================
// Host wrapper:  run_gpu_mitm
// ============================================================================
CrackResult run_gpu_mitm(int bits, bool multi_pair, bool show_transfer) {
  CrackResult result;
  result.cipher = "Double DES";
  result.method = "GPU MITM (" + std::to_string(bits) + " bits)";

  static uint32_t h_sp[8][64];
  static bool sp_ready = false;
  if (!sp_ready) {
    compute_sp_tables(h_sp);
    sp_ready = true;
  }
  cudaMemcpyToSymbol(d_sp, h_sp, sizeof(h_sp));
  cudaMemcpyToSymbol(d_pc1c, PC1C, sizeof(PC1C));
  cudaMemcpyToSymbol(d_pc1d, PC1D, sizeof(PC1D));
  cudaMemcpyToSymbol(d_pc2, PC2, sizeof(PC2));
  cudaMemcpyToSymbol(d_shifts, SHIFTS, sizeof(SHIFTS));

  const uint64_t total_keys = 1ULL << bits;
  uint64_t rng_state = GetTickCount64();
  if (rng_state == 0)
    rng_state = 0xDEADBEEFCAFEULL;
  uint64_t target_idx1 = (xorshift64(rng_state) % total_keys);
  uint64_t target_idx2 = (xorshift64(rng_state) % total_keys);

  uint64_t target_k1 = key_index_to_des_key_host(target_idx1);
  uint64_t target_k2 = key_index_to_des_key_host(target_idx2);

  const uint64_t PT1 = 0x0123456789ABCDEFULL;
  uint64_t CT_mid = des_encrypt_host(PT1, target_k1, h_sp);
  uint64_t CT1 = des_encrypt_host(CT_mid, target_k2, h_sp);

  const uint64_t PT2 = 0xFEDCBA9876543210ULL;
  uint64_t CT2_mid = des_encrypt_host(PT2, target_k1, h_sp);
  uint64_t CT2 = des_encrypt_host(CT2_mid, target_k2, h_sp);

  uint64_t ip_pt1 = apply_perm64(PT1, IP_TBL);
  uint32_t L0_pt1 = (uint32_t)(ip_pt1 >> 32), R0_pt1 = (uint32_t)ip_pt1;
  uint64_t ip_ct1 = apply_perm64(CT1, IP_TBL);
  uint32_t L0_ct1 = (uint32_t)(ip_ct1 >> 32), R0_ct1 = (uint32_t)ip_ct1;

  uint64_t ip_pt2 = apply_perm64(PT2, IP_TBL);
  uint32_t L0_pt2 = (uint32_t)(ip_pt2 >> 32), R0_pt2 = (uint32_t)ip_pt2;
  uint64_t ip_ct2 = apply_perm64(CT2, IP_TBL);
  uint32_t L0_ct2 = (uint32_t)(ip_ct2 >> 32), R0_ct2 = (uint32_t)ip_ct2;

  printf("\n");
  printf(
      "  " BCYAN
      "+----------------------------------------------------------+\n" RESET);
  printf("  " BCYAN "|" BWHITE "  GPU Meet-in-the-Middle Attack" BCYAN
         "                            |\n" RESET);
  printf(
      "  " BCYAN
      "+----------------------------------------------------------+\n" RESET);
  printf("  " BCYAN "|" RESET "  Keyspace Phase : " BYELLOW
         "2^%d = %llu entries\n" RESET,
         bits, (unsigned long long)total_keys);
  printf("  " BCYAN "|" RESET "  VRAM Requir'd  : " BYELLOW "%.2f MB\n" RESET,
         (double)(total_keys * 16) / 1048576.0);
  printf("  " BCYAN "|" RESET "  Multi-pair     : " BYELLOW "%s\n" RESET,
         multi_pair ? "ENABLED" : "disabled");
  printf(
      "  " BCYAN
      "+----------------------------------------------------------+\n" RESET);
  fflush(stdout);

  uint64_t *d_mids, *d_k1, *d_found1, *d_found2;
  cudaError_t alloc1 = cudaMalloc(&d_mids, total_keys * sizeof(uint64_t));
  cudaError_t alloc2 = cudaMalloc(&d_k1, total_keys * sizeof(uint64_t));
  if (alloc1 != cudaSuccess || alloc2 != cudaSuccess) {
    printf("  " BRED "ERROR: Out of VRAM! Reduce keyspace!\n" RESET);
    if (alloc1 == cudaSuccess)
      cudaFree(d_mids);
    if (alloc2 == cudaSuccess)
      cudaFree(d_k1);
    result.found = false;
    return result;
  }
  cudaMalloc(&d_found1, sizeof(uint64_t));
  cudaMalloc(&d_found2, sizeof(uint64_t));
  uint64_t sentinel = UINT64_MAX;
  cudaMemcpy(d_found1, &sentinel, sizeof(uint64_t), cudaMemcpyHostToDevice);
  cudaMemcpy(d_found2, &sentinel, sizeof(uint64_t), cudaMemcpyHostToDevice);

  Progress prog;
  progress_start(&prog, "GPU MITM (Build+Sort+Meet)", total_keys * 2);

  // Local helper: print a CUDA error, free GPU buffers, mark result, and
  // signal the caller to return.  Mirrors the defensive pattern used in
  // run_des_gpu_bruteforce so a driver/PTX mismatch fails gracefully instead
  // of letting an uncaught thrust::system_error terminate the process.
  auto bail_cuda = [&](const char* phase, const char* errmsg) {
    progress_finish(&prog, false);
    printf("\n  " BRED "CUDA error in %s: %s\n" RESET, phase, errmsg);
    cudaFree(d_mids);
    cudaFree(d_k1);
    cudaFree(d_found1);
    cudaFree(d_found2);
    result.found = false;
    result.key_str = "(CUDA error)";
  };

  double t0 = wall_time_sec();
  const int THREADS = 256;
  const int CHUNKS = 64;
  const uint64_t CHUNK_KEYS =
      ((total_keys + CHUNKS - 1) / CHUNKS + THREADS - 1) / THREADS * THREADS;

  // Phase 1: Build
  uint64_t keys_done = 0;
  for (int chunk = 0; chunk < CHUNKS && keys_done < total_keys; chunk++) {
    uint64_t offset = (uint64_t)chunk * CHUNK_KEYS;
    uint64_t this_batch = min(CHUNK_KEYS, total_keys - offset);
    uint64_t blocks = (this_batch + THREADS - 1) / THREADS;
    mitm_build_kernel<<<(uint32_t)blocks, THREADS>>>(offset, L0_pt1, R0_pt1,
                                                     total_keys, d_mids, d_k1);
    cudaDeviceSynchronize();
    keys_done += this_batch;
    if ((chunk % 4) == 0 || keys_done == total_keys)
      progress_update(&prog, keys_done / 2); // Map build to 25% bar
  }

  {
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
      bail_cuda("MITM build phase", cudaGetErrorString(err));
      return result;
    }
  }

  try {
    thrust::device_ptr<uint64_t> dev_ptr_keys(d_mids);
    thrust::device_ptr<uint64_t> dev_ptr_vals(d_k1);
    thrust::sort_by_key(dev_ptr_keys, dev_ptr_keys + total_keys, dev_ptr_vals);
    cudaDeviceSynchronize();
  } catch (const std::exception& e) {
    bail_cuda("MITM sort phase", e.what());
    return result;
  }
  {
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
      bail_cuda("MITM sort phase", cudaGetErrorString(err));
      return result;
    }
  }
  progress_update(&prog, total_keys); // Map sort to 50% bar

  // Phase 2: Meet
  uint64_t found_idx1 = UINT64_MAX, found_idx2 = UINT64_MAX;

  if (bits >= 28) {
    // Native GPU Phase 2
    keys_done = 0;
    for (int chunk = 0; chunk < CHUNKS && keys_done < total_keys; chunk++) {
      uint64_t offset = (uint64_t)chunk * CHUNK_KEYS;
      uint64_t this_batch = min(CHUNK_KEYS, total_keys - offset);
      uint64_t blocks = (this_batch + THREADS - 1) / THREADS;
      mitm_search_kernel<<<(uint32_t)blocks, THREADS>>>(
          offset, L0_ct1, R0_ct1, L0_ct2, R0_ct2, L0_pt2, R0_pt2, multi_pair,
          total_keys, d_mids, d_k1, d_found1, d_found2);

      cudaDeviceSynchronize();
      keys_done += this_batch;
      if ((chunk % 4) == 0 || keys_done == total_keys)
        progress_update(&prog, total_keys + keys_done);

      uint64_t peek = UINT64_MAX;
      cudaMemcpy(&peek, d_found1, sizeof(uint64_t), cudaMemcpyDeviceToHost);
      if (peek != UINT64_MAX)
        break;
    }

    {
      cudaError_t err = cudaGetLastError();
      if (err != cudaSuccess) {
        bail_cuda("MITM search phase", cudaGetErrorString(err));
        return result;
      }
    }

    cudaMemcpy(&found_idx1, d_found1, sizeof(uint64_t), cudaMemcpyDeviceToHost);
    cudaMemcpy(&found_idx2, d_found2, sizeof(uint64_t), cudaMemcpyDeviceToHost);
  } else {
    // CPU Hybrid Phase 2
    std::vector<uint64_t> h_mids(total_keys);
    std::vector<uint64_t> h_k1(total_keys);

    if (show_transfer) {
      double mb = (double)(total_keys * 16) / 1048576.0;
      printf("\n  " BCYAN
             "  [Hybrid] Downloading %.2f MB to Host System RAM...\n" RESET,
             mb);
      fflush(stdout);
    }

    // PCIe Transfer -- check both copies; if the GPU side errored earlier,
    // these will return the error rather than producing valid host data.
    cudaError_t mc1 = cudaMemcpy(h_mids.data(), d_mids,
                                 total_keys * sizeof(uint64_t),
                                 cudaMemcpyDeviceToHost);
    cudaError_t mc2 = cudaMemcpy(h_k1.data(), d_k1,
                                 total_keys * sizeof(uint64_t),
                                 cudaMemcpyDeviceToHost);
    if (mc1 != cudaSuccess || mc2 != cudaSuccess) {
      cudaError_t e = (mc1 != cudaSuccess) ? mc1 : mc2;
      bail_cuda("MITM hybrid download", cudaGetErrorString(e));
      return result;
    }

    std::atomic<uint64_t> atom_f1(UINT64_MAX);
    std::atomic<uint64_t> atom_f2(UINT64_MAX);

    int num_threads = std::thread::hardware_concurrency();
    if (num_threads == 0)
      num_threads = 4;
    std::vector<std::thread> pool;

    for (int tid = 0; tid < num_threads; tid++) {
      pool.push_back(std::thread([&, tid]() {
        uint64_t chunk = (total_keys + num_threads - 1) / num_threads;
        uint64_t start = (uint64_t)tid * chunk;
        uint64_t end = min(start + chunk, total_keys);

        for (uint64_t kid = start; kid < end; kid++) {
          if (atom_f1.load(std::memory_order_relaxed) != UINT64_MAX)
            break;

          uint64_t key = key_index_to_des_key_host(kid);
          uint64_t subkeys[16];
          generate_subkeys(key, subkeys);

          // Reconstruct internal target state mid
          uint64_t true_mid = des_decrypt(CT1, subkeys);
          uint64_t target_mid = apply_perm64(true_mid, IP_TBL);

          auto lb = std::lower_bound(h_mids.begin(), h_mids.end(), target_mid);
          while (lb != h_mids.end() && *lb == target_mid) {
            size_t idx = std::distance(h_mids.begin(), lb);
            uint64_t candidate_k1 = h_k1[idx];
            bool valid = true;

            if (multi_pair) {
              uint64_t p_k1 = key_index_to_des_key_host(candidate_k1);
              uint64_t calc_ct2 = double_des_encrypt(PT2, p_k1, key);
              if (calc_ct2 != CT2)
                valid = false;
            }

            if (valid) {
              uint64_t exp = UINT64_MAX;
              if (atom_f1.compare_exchange_strong(exp, candidate_k1)) {
                atom_f2.store(kid);
              }
              break;
            }
            lb++;
          }
        }
      }));
    }

    for (auto &t : pool) {
      t.join();
    }

    found_idx1 = atom_f1.load(std::memory_order_relaxed);
    found_idx2 = atom_f2.load(std::memory_order_relaxed);
    keys_done = total_keys;
    progress_update(&prog, total_keys + keys_done);
  }

  double elapsed = wall_time_sec() - t0;

  cudaFree(d_mids);
  cudaFree(d_k1);
  cudaFree(d_found1);
  cudaFree(d_found2);

  bool found = (found_idx1 != UINT64_MAX && found_idx2 != UINT64_MAX);
  progress_finish(&prog, found);

  result.keys_tested =
      total_keys + keys_done; // Evaluated build + search subset
  result.elapsed_sec = elapsed;
  result.keys_per_sec =
      (elapsed > 0.0) ? (double)result.keys_tested / elapsed : 0.0;

  if (found) {
    result.found = true;
    uint64_t found_k1 = key_index_to_des_key_host(found_idx1);
    uint64_t found_k2 = key_index_to_des_key_host(found_idx2);
    char buf[64];
    snprintf(buf, sizeof(buf), "K1:%014llx K2:%014llx",
             (unsigned long long)found_k1, (unsigned long long)found_k2);
    result.key_str = buf;

    printf("\n");
    printf(
        "  " BGREEN
        "+----------------------------------------------------------+\n" RESET);
    printf("  " BGREEN "|" BWHITE "  KEYS FOUND!" BGREEN
           "                                               |\n" RESET);
    printf(
        "  " BGREEN
        "+----------------------------------------------------------+\n" RESET);
    printf("  " BGREEN "|" RESET "  K1        : " BYELLOW "0x%016llX" DIM
           " (idx %llu)\n" RESET,
           (unsigned long long)found_k1, (unsigned long long)found_idx1);
    printf("  " BGREEN "|" RESET "  K2        : " BYELLOW "0x%016llX" DIM
           " (idx %llu)\n" RESET,
           (unsigned long long)found_k2, (unsigned long long)found_idx2);
    printf("  " BGREEN "|" RESET "  Time      : " BYELLOW "%.4f s\n" RESET,
           elapsed);
    printf("  " BGREEN "+------------------------------------------------------"
           "----+\n\n" RESET);
  } else {
    result.found = false;
    result.key_str = "(not found)";
    printf("\n  " BRED "  Keys NOT found. Try KILLING YOUR SELF!.\n\n" RESET);
  }

  return result;
}

#endif // HAVE_CUDA
