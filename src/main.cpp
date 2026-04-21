// ============================================================================
// main.cpp -- DEStroyer entry point and interactive menu loop
// ============================================================================
#include <windows.h>
#include <cstdio>
#include <cstring>
#include "common.h"
#include "ciphers.h"
#include "ui.h"
#include "des_cpu.h"

// Global bit-width settings (extern'd in ui.cpp for the status bar)
int g_mitm_bits    = 20;
int g_compare_bits = 10;
int g_des_bits     = 24;
int g_multi_pair    = 0;    // 0 = off, 1 = on; toggled in Settings
int g_show_transfer = 1;    // 0 = silent, 1 = log PCIe transfer size

// ============================================================================
// Option name table
// ============================================================================
static const char* OPTION_NAMES[] = {
    "CPU MITM",
    "GPU MITM",
    "CPU vs GPU MITM",
    "Brute-Force",
    "MITM vs Brute-Force",
    "DES GPU Brute-Force",   // index 5 — implemented
    "GPU Throughput + AES",
    "Complexity Analysis",
    "Settings", // done 
};

// ============================================================================
// Stub screen for unimplemented options
// ============================================================================
static void run_stub(int idx) {
    printf("\n");
    printf(MENU_INDENT BCYAN "+----------------------------------------------------------+\n" RESET);
    printf(MENU_INDENT BCYAN "|                                                          |\n" RESET);
    printf(MENU_INDENT BCYAN "|  " BWHITE "%-56s" BCYAN "|\n" RESET, OPTION_NAMES[idx]);
    printf(MENU_INDENT BCYAN "|                                                          |\n" RESET);
    printf(MENU_INDENT BCYAN "|  " BYELLOW "%-56s" BCYAN "|\n" RESET, "Not yet implemented.");
    printf(MENU_INDENT BCYAN "|                                                          |\n" RESET);
    printf(MENU_INDENT BCYAN "+----------------------------------------------------------+\n" RESET);
}

// ============================================================================
// Settings sub-menu
//
// Navigation:
//   Up/Down          : move cursor between rows
//                      rows 0-2 = param sliders
//                      row  3   = multi-pair toggle
//                      row  4   = preset buttons
//   Left/Right / -/+ : on param rows  → dec/inc value
//                      on toggle row  → flip multi-pair on/off
//                      on preset row  → move between buttons
//   Enter            : on preset row  → apply that preset
//                      on toggle row  → flip multi-pair on/off
//   Esc              : return to main menu
// ============================================================================

// Background color defines for preset buttons
#define BG_GREEN   "\033[42m"
#define BG_YELLOW  "\033[43m"
#define BG_RED     "\033[41m"
#define BG_PURPLE  "\033[48;5;53m"   // dark purple (256-color)
#define FG_PURPLE  "\033[38;5;93m"   // bright violet foreground

// ── Parameter rows ────────────────────────────────────────────────────────────
struct Setting {
    const char* label;
    const char* hint;
    int*        value;
    int         lo;
    int         hi;
};

static Setting SETTINGS[] = {
    { "MITM Key Bits",    "2^N MITM table entries", &g_mitm_bits,    4,  28 },
    { "Compare Key Bits", "2^N brute-force pairs",  &g_compare_bits, 4,  20 },
    { "DES GPU Bits",     "2^N GPU key search",     &g_des_bits,     8,  36 },
};
static const int SETTINGS_COUNT = 3;

// ── Preset definitions ────────────────────────────────────────────────────────
struct Preset {
    const char* name;       // button label  (padded to 8 chars in render)
    const char* fg;         // foreground color when not focused
    const char* bg_sel;     // background color when focused
    int         mitm_bits;
    int         compare_bits;
    int         des_bits;
    int         multi_pair; // 1 = force on, 0 = force off
};

static const Preset PRESETS[] = {
    { "EASY",      BGREEN,    BG_GREEN,  12,  8,  16, 0 },
    { "MEDIUM",    BYELLOW,   BG_YELLOW, 18, 12,  22, 0 },
    { "HARD",      BRED,      BG_RED,    24, 16,  28, 0 },
    { "NIGHTMARE", FG_PURPLE, BG_PURPLE, 28, 20,  36, 1 },
};
static const int PRESET_COUNT = 4;

// Row indices
static const int TOGGLE_ROW   = SETTINGS_COUNT;          // 3
static const int LOG_TRANSFER_ROW = SETTINGS_COUNT + 1;  // 4
static const int PRESET_ROW   = SETTINGS_COUNT + 2;      // 5
static const int TOTAL_ROWS   = SETTINGS_COUNT + 3;      // 6

static void apply_preset(int p) {
    g_mitm_bits    = PRESETS[p].mitm_bits;
    g_compare_bits = PRESETS[p].compare_bits;
    g_des_bits     = PRESETS[p].des_bits;
    g_multi_pair   = PRESETS[p].multi_pair;
}

// ── draw_settings ──────────────────────────────────────────────────────────────
static void draw_settings(int sel, int preset_cursor) {
    const int W = 58;
    auto sp = [](int n){ for (int i = 0; i < n; i++) putchar(' '); };

    // ── Top border + title ───────────────────────────────────────────────────
    printf("\n");
    printf(MENU_INDENT BCYAN "+");
    for (int i = 0; i < W; i++) putchar('-');
    printf("+\n" RESET);

    const char* title = "DEStroyer -- SETTINGS";
    int tlen  = (int)strlen(title);
    int tlpad = (W - tlen) / 2;
    printf(MENU_INDENT BCYAN "|" RESET);
    sp(tlpad);
    printf(BCYAN "%s" RESET, title);
    sp(W - tlen - tlpad);
    printf(BCYAN "|\n" RESET);

    printf(MENU_INDENT BCYAN "+");
    for (int i = 0; i < W; i++) putchar('-');
    printf("+\n" RESET);

    // ── Attack Parameters section ────────────────────────────────────────────
    printf(MENU_INDENT BCYAN "|"); sp(W); printf("|\n" RESET);
    const char* sec1 = "  -- Attack Parameters";
    printf(MENU_INDENT BCYAN "|" RESET BRED "%s" RESET, sec1);
    sp(W - (int)strlen(sec1));
    printf(BCYAN "|\n" RESET);
    printf(MENU_INDENT BCYAN "|"); sp(W); printf("|\n" RESET);

    // ── Parameter rows ───────────────────────────────────────────────────────
    for (int i = 0; i < SETTINGS_COUNT; i++) {
        const Setting& s  = SETTINGS[i];
        bool           hi = (sel == i);

        const char* bg = hi ? BG_BLUE : "";
        const char* nc = hi ? BWHITE  : DIM;
        const char* lc = hi ? BWHITE  : BWHITE;
        const char* vc = hi ? BYELLOW : BYELLOW;
        const char* dc = hi ? DIM     : DIM;

        const int label_w = 18;
        int llen = (int)strlen(s.label);
        int lpad = (llen < label_w) ? label_w - llen : 0;

        char vblock[16];
        snprintf(vblock, sizeof(vblock), "< %3d >", *s.value);

        char range_str[32];
        snprintf(range_str, sizeof(range_str), "  [%d..%d]", s.lo, s.hi);

        int used  = 1 + 3 + 2 + label_w + 2 + 7 + 2
                  + (int)strlen(s.hint) + (int)strlen(range_str);
        int trail = W - used;
        if (trail < 0) trail = 0;

        printf(MENU_INDENT BCYAN "|" RESET "%s ", bg);
        printf("%s[%d]%s%s  ", nc, i + 1, RESET, bg);
        printf("%s%.*s%s", lc, label_w, s.label, bg);
        sp(lpad);
        printf("  %s%s%s", vc, vblock, bg);
        printf("  %s%s%s%s", dc, s.hint, range_str, RESET);
        sp(trail);
        printf(BCYAN "|\n" RESET);
    }

    // ── Multi-pair toggle row ─────────────────────────────────────────────────
    printf(MENU_INDENT BCYAN "|"); sp(W); printf("|\n" RESET);
    {
        const char* sec2 = "  -- Options";
        printf(MENU_INDENT BCYAN "|" RESET BRED "%s" RESET, sec2);
        sp(W - (int)strlen(sec2));
        printf(BCYAN "|\n" RESET);
        printf(MENU_INDENT BCYAN "|"); sp(W); printf("|\n" RESET);

        bool hi = (sel == TOGGLE_ROW);
        const char* bg = hi ? BG_BLUE : "";

        const char* state_col = g_multi_pair ? BGREEN : DIM;
        const char* state_str = g_multi_pair ? "[ ON  ]" : "[ OFF ]";
        const char* lc        = hi ? BWHITE : BWHITE;

        const char* label  = "Multi-Pair Verify";
        const char* hint   = "2nd PT/CT eliminates false positives";
        const int   label_w = 18;
        int llen  = (int)strlen(label);
        int lpad  = (llen < label_w) ? label_w - llen : 0;
        int hlen  = (int)strlen(hint);

        int used  = 1 + 3 + 2 + label_w + 2 + 7 + 2 + hlen;
        int trail = W - used;
        if (trail < 0) trail = 0;

        printf(MENU_INDENT BCYAN "|" RESET "%s ", bg);
        printf("%s[4]%s%s  ", hi ? BWHITE : DIM, RESET, bg);
        printf("%s%.*s%s", lc, label_w, label, bg);
        sp(lpad);
        printf("  %s%s%s", state_col, state_str, bg);
        printf("  %s%s%s", DIM, hint, RESET);
        sp(trail);
        printf(BCYAN "|\n" RESET);
    }
    {
        bool hi = (sel == LOG_TRANSFER_ROW);
        const char* bg = hi ? BG_BLUE : "";

        const char* state_col = g_show_transfer ? BGREEN : DIM;
        const char* state_str = g_show_transfer ? "[ ON  ]" : "[ OFF ]";
        const char* lc        = hi ? BWHITE : BWHITE;

        const char* label  = "Log CPU Transfers";
        const char* hint   = "Print download sizes for Hybrid ops";
        const int   label_w = 18;
        int llen  = (int)strlen(label);
        int lpad  = (llen < label_w) ? label_w - llen : 0;
        int hlen  = (int)strlen(hint);

        int used  = 1 + 3 + 2 + label_w + 2 + 7 + 2 + hlen;
        int trail = W - used;
        if (trail < 0) trail = 0;

        printf(MENU_INDENT BCYAN "|" RESET "%s ", bg);
        printf("%s[5]%s%s  ", hi ? BWHITE : DIM, RESET, bg);
        printf("%s%.*s%s", lc, label_w, label, bg);
        sp(lpad);
        printf("  %s%s%s", state_col, state_str, bg);
        printf("  %s%s%s", DIM, hint, RESET);
        sp(trail);
        printf(BCYAN "|\n" RESET);
    }

    // ── Presets section ──────────────────────────────────────────────────────
    printf(MENU_INDENT BCYAN "|"); sp(W); printf("|\n" RESET);
    const char* sec3 = "  -- Presets";
    printf(MENU_INDENT BCYAN "|" RESET BRED "%s" RESET, sec3);
    sp(W - (int)strlen(sec3));
    printf(BCYAN "|\n" RESET);
    printf(MENU_INDENT BCYAN "|"); sp(W); printf("|\n" RESET);

    // ── Preset button row ─────────────────────────────────────────────────────
    // 4 buttons: "[ LABEL    ]" — label padded to 8 = 12 visible chars each
    // 3 gaps of 2 chars: 4*12 + 3*2 = 54. Left/right pad = (58-54)/2 = 2.
    bool preset_row_active = (sel == PRESET_ROW);

    printf(MENU_INDENT BCYAN "|" RESET);
    sp(2);

    for (int p = 0; p < PRESET_COUNT; p++) {
        bool focused = preset_row_active && (p == preset_cursor);

        char label_padded[12];
        snprintf(label_padded, sizeof(label_padded), "%-8s", PRESETS[p].name);

        if (focused) {
            printf("%s" BWHITE "[ %s ]" RESET, PRESETS[p].bg_sel, label_padded);
        } else if (preset_row_active) {
            printf(DIM "[ %s%s" RESET DIM " ]" RESET, PRESETS[p].fg, label_padded);
        } else {
            printf("%s[ %s ]" RESET, PRESETS[p].fg, label_padded);
        }

        if (p < PRESET_COUNT - 1) sp(2);
    }

    sp(2);
    printf(BCYAN "|\n" RESET);

    // ── Hint / help line ─────────────────────────────────────────────────────
    printf(MENU_INDENT BCYAN "|"); sp(W); printf("|\n" RESET);
    {
        const char* hint;
        const char* hcol;
        if (sel == PRESET_ROW) {
            hint = "Left/Right to select  |  Enter to apply preset";
            hcol = BYELLOW;
        } else if (sel == TOGGLE_ROW || sel == LOG_TRANSFER_ROW) {
            hint = "Left/Right or Enter  to toggle  |  Esc  to return";
            hcol = BWHITE;
        } else {
            hint = "Left/Right or -/+  to change  |  Esc  to return";
            hcol = DIM;
        }
        int hlen  = (int)strlen(hint);
        int hlpad = (W - hlen) / 2;
        printf(MENU_INDENT BCYAN "|" RESET);
        sp(hlpad);
        printf("%s%s" RESET, hcol, hint);
        sp(W - hlen - hlpad);
        printf(BCYAN "|\n" RESET);
    }

    // ── Bottom border ────────────────────────────────────────────────────────
    printf(MENU_INDENT BCYAN "+");
    for (int i = 0; i < W; i++) putchar('-');
    printf("+\n\n" RESET);
    fflush(stdout);
}

// ── run_settings ──────────────────────────────────────────────────────────────
static void run_settings() {
    int sel           = 0;
    int preset_cursor = 0;

    while (true) {
        ui_clear();
        ui_print_banner();
        draw_settings(sel, preset_cursor);

        int key = ui_read_key();

        if (key == -1) {                                        // up
            sel = (sel - 1 + TOTAL_ROWS) % TOTAL_ROWS;

        } else if (key == -2) {                                 // down
            sel = (sel + 1) % TOTAL_ROWS;

        } else if (key == -3 || key == '-') {                   // left / minus
            if (sel < SETTINGS_COUNT) {
                Setting& s = SETTINGS[sel];
                if (*s.value > s.lo) (*s.value)--;
            } else if (sel == TOGGLE_ROW) {
                g_multi_pair ^= 1;
            } else if (sel == LOG_TRANSFER_ROW) {
                g_show_transfer ^= 1;
            } else {
                preset_cursor = (preset_cursor - 1 + PRESET_COUNT) % PRESET_COUNT;
            }

        } else if (key == -4 || key == '+') {                   // right / plus
            if (sel < SETTINGS_COUNT) {
                Setting& s = SETTINGS[sel];
                if (*s.value < s.hi) (*s.value)++;
            } else if (sel == TOGGLE_ROW) {
                g_multi_pair ^= 1;
            } else if (sel == LOG_TRANSFER_ROW) {
                g_show_transfer ^= 1;
            } else {
                preset_cursor = (preset_cursor + 1) % PRESET_COUNT;
            }

        } else if (key >= '1' && key <= '5') {
            sel = key - '1';                                    // jump to row

        } else if (key == 13) {                                 // Enter
            if (sel == PRESET_ROW) {
                apply_preset(preset_cursor);
            } else if (sel == TOGGLE_ROW) {
                g_multi_pair ^= 1;
            } else if (sel == LOG_TRANSFER_ROW) {
                g_show_transfer ^= 1;
            }

        } else if (key == 27) {                                 // Esc: exit
            return;
        }
    }
}

// ============================================================================
// Attack dispatcher
// ============================================================================
static void run_attack(int idx) {
    switch (idx) {
        case 0: {   // Option 1: CPU MITM
            CrackResult r = run_cpu_mitm(g_mitm_bits, g_multi_pair != 0);
            Benchmark::record(r);
            break;
        }

        case 1: {   // Option 2: GPU MITM
#ifdef HAVE_CUDA
            CrackResult r = run_gpu_mitm(g_mitm_bits, g_multi_pair != 0, g_show_transfer != 0);
            Benchmark::record(r);
#else
            printf("\n" MENU_INDENT BRED
                   "  CUDA not available - GPU attacks disabled.\n" RESET);
            printf(MENU_INDENT DIM
                   "  Rebuild with a CUDA toolkit installed.\n\n" RESET);
#endif
            break;
        }

        case 3: {   // Option 4: CPU Brute-Force (Double-DES)
            CrackResult r = run_cpu_bruteforce(g_compare_bits, g_multi_pair != 0);
            Benchmark::record(r);
            break;
        }

        case 5: {   // Option 6: DES GPU Brute-Force
#ifdef HAVE_CUDA
            CrackResult r = run_des_gpu_bruteforce(g_des_bits, g_multi_pair != 0);
            Benchmark::record(r);
#else
            printf("\n" MENU_INDENT BRED
                   "  CUDA not available - GPU attacks disabled.\n" RESET);
            printf(MENU_INDENT DIM
                   "  Rebuild with a CUDA toolkit installed.\n\n" RESET);
#endif
            break;
        }

        case 6: {   // Option 7: GPU Throughput + AES
#ifdef HAVE_CUDA
            // Use 2^g_des_bits keys for throughput test
            uint64_t keys = 1ULL << g_des_bits;
            CrackResult r = run_gpu_throughput(keys);
            Benchmark::record(r);
            Benchmark::print_aes_extrapolation(r.keys_per_sec);
#else
            printf("\n" MENU_INDENT BRED
                   "  CUDA not available - GPU attacks disabled.\n" RESET);
            printf(MENU_INDENT DIM
                   "  Rebuild with a CUDA toolkit installed.\n\n" RESET);
#endif
            break;
        }

        default:
            run_stub(idx);
            break;
    }
}

// ============================================================================
// Save results and exit
// ============================================================================
static void do_save_and_exit() {
    ui_clear();
    ui_print_banner();

    Benchmark::print_summary();

    // Write JSON next to the executable
    char exe_path[MAX_PATH] = {};
    GetModuleFileNameA(nullptr, exe_path, MAX_PATH);
    char* last_sep = strrchr(exe_path, '\\');
    if (!last_sep) last_sep = strrchr(exe_path, '/');
    if (last_sep) {
        *(last_sep + 1) = '\0';
        strncat(exe_path, "mitm_results.json", MAX_PATH - (int)strlen(exe_path) - 1);
    } else {
        strncpy(exe_path, "mitm_results.json", MAX_PATH);
    }

    Benchmark::export_json(exe_path);
    ui_press_enter();
}

// ============================================================================
// Main interactive loop
// ============================================================================
static void run_loop() {
    int selected = 0;

    while (true) {
        ui_clear();
        ui_print_banner();
        ui_print_menu(selected);

        int key = ui_read_key();

        if (key == -1) {
            selected = (selected - 1 + MENU_COUNT) % MENU_COUNT;
        } else if (key == -2) {
            selected = (selected + 1) % MENU_COUNT;
        } else if (key == 13) {
            if (selected == 9) { ui_clear(); do_save_and_exit(); return; }
            if (selected == 8) { run_settings(); ui_clear(); continue; }
            ui_clear();
            ui_print_banner();
            run_attack(selected);
            ui_press_enter();
        } else if (key >= '0' && key <= '9') {
            int idx = (key == '0') ? 9 : (key - '1');
            if (idx == 9) { ui_clear(); do_save_and_exit(); return; }
            if (idx == 8) { run_settings(); ui_clear(); continue; }
            selected = idx;
            ui_clear();
            ui_print_banner();
            run_attack(selected);
            ui_press_enter();
        }
    }
}

// ============================================================================
int main() {
    ui_init();
    des_cpu_init();   // pre-compute SP-box table for CPU DES engine
    run_loop();
    return 0;
}
