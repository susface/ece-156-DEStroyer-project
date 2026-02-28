// ============================================================================
// ECE 156 Final Project -- Double DES Meet-in-the-Middle Attack
// California State University, Fresno
//
// SKELETON VERSION -- menu only, implementations not included
// ============================================================================

#define NOMINMAX
#include <windows.h>
#include <conio.h>
#include <cstdio>
#include <cstdlib>
#include <string>

// ============================================================================
// ANSI color codes
// ============================================================================
#define RESET   "\033[0m"
#define BOLD    "\033[1m"
#define DIM     "\033[2m"
#define BWHITE  "\033[97m"
#define BCYAN   "\033[96m"
#define BGREEN  "\033[92m"
#define BYELLOW "\033[93m"
#define BRED    "\033[91m"
#define RED     "\033[31m"
#define WHITE   "\033[37m"
#define BG_BLUE "\033[44m"

// ============================================================================
// Console setup
// ============================================================================
static void init_console() {
    SetConsoleOutputCP(CP_UTF8);
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD mode = 0;
    GetConsoleMode(hOut, &mode);
    SetConsoleMode(hOut, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
}

static void clear_screen() {
    system("cls");
}

// ============================================================================
// Single keypress -- no Enter needed
// Returns: -1 = up arrow, -2 = down arrow, 13 = Enter, else char value
// ============================================================================
static int read_key() {
    int ch = _getch();
    if (ch == 0 || ch == 224) {
        int ch2 = _getch();
        if (ch2 == 72) return -1; // up
        if (ch2 == 80) return -2; // down
        return 0;
    }
    return ch;
}

static void press_enter() {
    printf("\n  %s%sPress Enter to return to menu...%s ", DIM, WHITE, RESET);
    fflush(stdout);
    while (true) {
        int k = read_key();
        if (k == 13 || k == '\n') break;
    }
}

// ============================================================================
// Banner
// ============================================================================
static void print_banner() {
    printf("\n");
    printf("  %s%s", BOLD, BCYAN);
    printf("  +--------------------------------------------------------------+\n");
    printf("  |                                                              |\n");
    printf("  |   %sDOUBLE DES -- MEET-IN-THE-MIDDLE ATTACK%s%s                  |\n", BWHITE, RESET, BCYAN);
    printf("  |                                                              |\n");
    printf("  |   %sC = E_K2( E_K1(P) )     Diffie & Hellman, 1977%s%s          |\n", DIM, RESET, BCYAN);
    printf("  |   %sDES GPU brute-force  |  CUDA-accelerated MITM%s%s           |\n", DIM, RESET, BCYAN);
    printf("  |                                                              |\n");
    printf("  |   %sECE 156 -- Cryptography  |  Cal State Fresno%s%s            |\n", DIM, RESET, BCYAN);
    printf("  |                                                              |\n");
    printf("  +--------------------------------------------------------------+%s\n", RESET);
}

// ============================================================================
// Menu definition
// ============================================================================
struct MenuItem {
    const char* label;
    const char* desc;
    const char* section; // non-null = print a section header before this item
};

static const MenuItem MENU_ITEMS[] = {
    { "CPU MITM",        "multithreaded Phase 1+2",    "-- Meet-in-the-Middle (2DES) --" },
    { "GPU MITM",        "GPU Phase 1, CPU Phase 2",   nullptr },
    { "CPU vs GPU MITM", "side-by-side comparison",    nullptr },
    { "Brute-Force",     "exhaustive K1 x K2",         "-- Reference Attacks --" },
    { "MITM vs BF",      "speedup summary",            nullptr },
    { "DES GPU Brute",   "CUDA key search",            "-- GPU DES Attacks --" },
    { "GPU Throughput",  "peak DES enc/sec + AES",     nullptr },
    { "Complexity",      "time/space breakdown",       "-- Analysis --" },
    { "Settings",        "adjust bits & options",      nullptr },
    { "Exit",            "",                           nullptr },
};
static const int MENU_COUNT = 10;

// current bit settings shown in status bar
static int g_mitm_bits    = 20;
static int g_compare_bits = 10;
static int g_des_bits     = 24;

static void print_menu(int selected) {
    printf("\n  %s%s+----------------------------------------------------+%s\n", BOLD, BCYAN, RESET);
    printf("  %s%s|      DOUBLE DES -- CRYPTANALYSIS SUITE             |%s\n", BOLD, BCYAN, RESET);
    printf("  %s%s+----------------------------------------------------+%s\n", BOLD, BCYAN, RESET);

    for (int i = 0; i < MENU_COUNT; i++) {
        const auto& item = MENU_ITEMS[i];

        if (item.section) {
            printf("  %s%s|%s                                                    %s%s|%s\n",
                   BOLD, BCYAN, RESET, BCYAN, BOLD, RESET);
            printf("  %s%s|%s  %s%-48s%s%s|%s\n",
                   BOLD, BCYAN, RESET, BRED, item.section, RESET, BCYAN, RESET);
        }

        bool is_sel     = (i == selected);
        const char* bg  = is_sel ? BG_BLUE : "";
        const char* nc  = is_sel ? BWHITE  : DIM;
        const char* dc  = is_sel ? BYELLOW : DIM;
        int num         = (i == 9) ? 0 : i + 1;

        printf("  %s%s|%s%s  %s[%d]%s  %-18s%s%-26s%s  %s%s|%s\n",
               BOLD, BCYAN, RESET,
               bg,
               nc, num, RESET,
               item.label,
               dc, item.desc, RESET,
               bg, BCYAN, RESET);
    }

    printf("  %s%s|                                                    |%s\n", BOLD, BCYAN, RESET);
    printf("  %s%s+----------------------------------------------------+%s\n", BOLD, BCYAN, RESET);
    printf("  %s%s|%s  MITM=%s%d-bit%s | Compare=%s%d-bit%s | DES-GPU=%s%d-bit%s              %s%s|%s\n",
           BOLD, BCYAN, RESET,
           BYELLOW, g_mitm_bits,    RESET,
           BYELLOW, g_compare_bits, RESET,
           BYELLOW, g_des_bits,     RESET,
           BCYAN, BOLD, RESET);
    printf("  %s%s+----------------------------------------------------+%s\n", BOLD, BCYAN, RESET);

    printf("\n  %sArrow keys to navigate  |  Enter to select  |  Number keys for quick access%s\n",
           DIM, RESET);
}

// ============================================================================
// Stub for every option
// ============================================================================
static const char* OPTION_NAMES[] = {
    "CPU MITM",
    "GPU MITM",
    "CPU vs GPU MITM",
    "Brute-Force",
    "MITM vs Brute-Force",
    "DES GPU Brute-Force",
    "GPU Throughput + AES",
    "Complexity Analysis",
    "Settings",
};

static void run_stub(int idx) {
    printf("\n");
    printf("  %s%s+----------------------------------------------------+%s\n", BOLD, BCYAN, RESET);
    printf("  %s%s|                                                    |%s\n", BOLD, BCYAN, RESET);
    printf("  %s%s|%s  %s%-48s%s%s|%s\n",
           BOLD, BCYAN, RESET, BWHITE, OPTION_NAMES[idx], RESET, BCYAN, RESET);
    printf("  %s%s|                                                    |%s\n", BOLD, BCYAN, RESET);
    printf("  %s%s|%s  %s%-48s%s%s|%s\n",
           BOLD, BCYAN, RESET, BYELLOW, "Not yet implemented.", RESET, BCYAN, RESET);
    printf("  %s%s|                                                    |%s\n", BOLD, BCYAN, RESET);
    printf("  %s%s+----------------------------------------------------+%s\n", BOLD, BCYAN, RESET);
}

// ============================================================================
// Main loop
// ============================================================================
static void interactive_loop() {
    int selected = 0;

    while (true) {
        clear_screen();
        print_banner();
        print_menu(selected);

        int key = read_key();

        if (key == -1) {                               // up arrow
            selected = (selected - 1 + MENU_COUNT) % MENU_COUNT;
        } else if (key == -2) {                        // down arrow
            selected = (selected + 1) % MENU_COUNT;
        } else if (key == 13) {                        // Enter
            if (selected == 9) return;                 // Exit
            clear_screen();
            run_stub(selected);
            press_enter();
        } else if (key >= '0' && key <= '9') {         // number shortcut
            int idx = (key == '0') ? 9 : (key - '1');
            if (idx == 9) return;
            selected = idx;
            clear_screen();
            run_stub(selected);
            press_enter();
        }
    }
}

int main() {
    init_console();
    interactive_loop();
    return 0;
}
