// ============================================================================
// ui.cpp -- DEStroyer console UI implementation
// ============================================================================
#define NOMINMAX
#include <windows.h>
#include <conio.h>
#include <cstdio>
#include <cstring>
#include "ui.h"

// ============================================================================
// Menu data
// ============================================================================
const MenuItem MENU_ITEMS[] = {
    { "CPU MITM",        "multithreaded Phase 1+2",   "-- Meet-in-the-Middle (2DES) --" },
    { "GPU MITM",        "GPU Phase 1, CPU Phase 2",  nullptr },
    { "CPU vs GPU MITM", "side-by-side comparison",   nullptr },
    { "Brute-Force",     "exhaustive K1 x K2",        "-- Reference Attacks --" },
    { "MITM vs BF",      "speedup summary",           nullptr },
    { "DES GPU Brute",   "CUDA key search",           "-- GPU DES Attacks --" },
    { "GPU Throughput",  "peak DES enc/sec + AES",    nullptr },
    { "Complexity",      "time/space breakdown",      "-- Analysis --" },
    { "Settings",        "adjust bits & options",     nullptr },
    { "Exit",            "",                          nullptr },
};
const int MENU_COUNT = 10;

// ============================================================================
// Console setup
// ============================================================================
void ui_init() {
    SetConsoleOutputCP(CP_UTF8);
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD mode  = 0;
    GetConsoleMode(hOut, &mode);
    SetConsoleMode(hOut, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
}

void ui_clear() {
    system("cls");
}

// ============================================================================
// Keypress
// ============================================================================
int ui_read_key() {
    int ch = _getch();
    if (ch == 0 || ch == 224) {
        int ch2 = _getch();
        if (ch2 == 72) return -1;  // up arrow
        if (ch2 == 80) return -2;  // down arrow
        return 0;
    }
    return ch;
}

void ui_press_enter() {
    printf("\n" MENU_INDENT DIM "Press Enter to return to menu..." RESET " ");
    fflush(stdout);
    while (true) {
        int k = ui_read_key();
        if (k == 13 || k == '\n') break;
    }
}

// ============================================================================
//  ___  ___ ___  _
// |   \| __/ __|| |_ _ _ ___ _  _ ___ _ _
// | |) | _|\__ \|  _| '_/ _ \ || / -_) '_|
// |___/|___|___/ \__|_| \___/\_, \___|_|
//                             |__/
// ============================================================================
void ui_print_banner() {
    printf("\n");
    printf(MENU_INDENT GR1 " ___  ___ ___ " GR2 " _                              \n" RESET);
    printf(MENU_INDENT GR1 "|   \\| __/ __|" GR2 "| |_ _ _ ___ _  _ ___ _ _     \n" RESET);
    printf(MENU_INDENT GR2 "| |) | _|\\__ \\" GR3 "|  _| '_/ _ \\ || / -_) '_|    \n" RESET);
    printf(MENU_INDENT GR3 "|___/|___|___/" GR2 " \\__|_| \\___/\\_, \\___|_|       \n" RESET);
    printf(MENU_INDENT GR2 "             " GR1  "              |__/              \n" RESET);
    printf("\n");
    printf(MENU_INDENT DIM "              Meet-in-the-Middle Attack on Double DES\n" RESET);
    printf(MENU_INDENT GR2 "              ECE 156 -- Cryptography  |  Cal State Fresno\n" RESET);
    printf("\n");
}

// ============================================================================
// Menu drawing helpers
//
// All menu lines have the same visible width:
//   MENU_INDENT(2) + "|"(1) + MENU_W(58) + "|"(1) = 62 chars
//
// We NEVER use printf %-Ns for colored strings because ANSI escape bytes
// inflate the byte count without adding visible width. Instead we print the
// colored text, then manually emit the exact number of spaces needed.
// ============================================================================

// Print N spaces
static void spaces(int n) {
    for (int i = 0; i < n; i++) putchar(' ');
}

// Border line:  "  +--...--+"
static void menu_border() {
    printf(MENU_INDENT BCYAN "+");
    for (int i = 0; i < MENU_W; i++) putchar('-');
    printf("+\n" RESET);
}

// Empty line:   "  |        ...        |"
static void menu_empty() {
    printf(MENU_INDENT BCYAN "|");
    spaces(MENU_W);
    printf("|\n" RESET);
}

// Plain padded line -- content is uncolored, padded to MENU_W
static void menu_plain(const char* text, int lpad) {
    int tlen = (int)strlen(text);
    printf(MENU_INDENT BCYAN "|" RESET);
    spaces(lpad);
    printf("%s", text);
    spaces(MENU_W - lpad - tlen);
    printf(BCYAN "|\n" RESET);
}

// Section header:  "  |  -- Section Name --             |"
static void menu_section(const char* text) {
    int tlen = (int)strlen(text);
    printf(MENU_INDENT BCYAN "|" RESET "  " BRED "%s" RESET, text);
    spaces(MENU_W - 2 - tlen);
    printf(BCYAN "|\n" RESET);
}

// Title line (centered):  "  |      DEStroyer ...              |"
static void menu_title(const char* text) {
    int tlen   = (int)strlen(text);
    int lpad   = (MENU_W - tlen) / 2;
    int rpad   = MENU_W - tlen - lpad;
    printf(MENU_INDENT BCYAN "|" RESET);
    spaces(lpad);
    printf(BCYAN "%s" RESET, text);
    spaces(rpad);
    printf(BCYAN "|\n" RESET);
}

// Status bar line (no color on values -- colored inline)
// Manually built to avoid field-width problems
static void menu_status(int mitm, int cmp, int des) {
    // "  MITM=20-bit | Compare=10-bit | DES-GPU=24-bit"
    // Build visible string and count its length
    char buf[128];
    int vlen = snprintf(buf, sizeof(buf),
                        "  MITM=%d-bit | Compare=%d-bit | DES-GPU=%d-bit",
                        mitm, cmp, des);

    printf(MENU_INDENT BCYAN "|" RESET "  "
           "MITM=" BYELLOW "%d-bit" RESET
           " | Compare=" BYELLOW "%d-bit" RESET
           " | DES-GPU=" BYELLOW "%d-bit" RESET,
           mitm, cmp, des);
    spaces(MENU_W - vlen);       // vlen already includes the leading "  "
    printf(BCYAN "|\n" RESET);
}

// Menu item row
// Visible layout (MENU_W = 58):
//   " [N]  <label 18 chars> <desc 28 chars>   " = 1+3+2+18+1+28+5 = 58
static void menu_item(int num, const char* label, const char* desc, bool selected) {
    const int LABEL_W = 18;
    const int DESC_W  = 28;
    // trailing pad: MENU_W - 1 - 3 - 2 - LABEL_W - 1 - DESC_W = 58-1-3-2-18-1-28 = 5
    const int TRAIL   = MENU_W - 1 - 3 - 2 - LABEL_W - 1 - DESC_W;

    int llen  = (int)strlen(label);
    int dlen  = (int)strlen(desc);
    int lpad  = LABEL_W - (llen < LABEL_W ? llen : LABEL_W);
    int dpad  = DESC_W  - (dlen < DESC_W  ? dlen : DESC_W);

    const char* bg  = selected ? BG_BLUE : "";
    const char* nc  = selected ? BWHITE  : DIM;
    const char* lc  = selected ? BWHITE  : BWHITE;
    const char* dc  = selected ? BYELLOW : DIM;
    const char* end = selected ? RESET   : "";

    printf(MENU_INDENT BCYAN "|" RESET "%s ", bg);
    printf("%s[%d]%s%s  ", nc, num, RESET, bg);
    printf("%s%.*s%s", lc, LABEL_W, label, bg);
    spaces(lpad);
    printf(" %s%.*s%s", dc, DESC_W, desc, RESET);
    spaces(dpad);
    spaces(TRAIL);
    printf(BCYAN "|\n" RESET);
}

// ============================================================================
// Full menu
// ============================================================================
extern int g_mitm_bits;
extern int g_compare_bits;
extern int g_des_bits;

void ui_print_menu(int selected) {
    menu_border();
    menu_title("DEStroyer -- CRYPTANALYSIS SUITE");
    menu_border();

    for (int i = 0; i < MENU_COUNT; i++) {
        const MenuItem& item = MENU_ITEMS[i];

        if (item.section) {
            menu_empty();
            menu_section(item.section);
        }

        int num = (i == 9) ? 0 : i + 1;
        menu_item(num, item.label, item.desc, i == selected);
    }

    menu_empty();
    menu_border();
    menu_status(g_mitm_bits, g_compare_bits, g_des_bits);
    menu_border();

    printf("\n" MENU_INDENT DIM
           "Arrow keys to navigate  |  Enter to select  |  Number keys for quick access"
           RESET "\n");
}
