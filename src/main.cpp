// ============================================================================
// DEStroyer -- Double DES Meet-in-the-Middle Attack
// ============================================================================
#define NOMINMAX
#include <windows.h>
#include <cstdio>
#include "ui.h"

// Bit settings (declared here, referenced in ui.cpp via extern)
int g_mitm_bits    = 20;
int g_compare_bits = 10;
int g_des_bits     = 24;

// ============================================================================
// Stub screen shown for each unimplemented option
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
    printf(MENU_INDENT BCYAN "+----------------------------------------------------------+\n" RESET);
    printf(MENU_INDENT BCYAN "|                                                          |\n" RESET);
    printf(MENU_INDENT BCYAN "|  " BWHITE "%-56s" BCYAN "|\n" RESET, OPTION_NAMES[idx]);
    printf(MENU_INDENT BCYAN "|                                                          |\n" RESET);
    printf(MENU_INDENT BCYAN "|  " BYELLOW "%-56s" BCYAN "|\n" RESET, "Not yet implemented.");
    printf(MENU_INDENT BCYAN "|                                                          |\n" RESET);
    printf(MENU_INDENT BCYAN "+----------------------------------------------------------+\n" RESET);
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
            if (selected == 9) return;
            ui_clear();
            ui_print_banner();
            run_stub(selected);
            ui_press_enter();
        } else if (key >= '0' && key <= '9') {
            int idx = (key == '0') ? 9 : (key - '1');
            if (idx == 9) return;
            selected = idx;
            ui_clear();
            ui_print_banner();
            run_stub(selected);
            ui_press_enter();
        }
    }
}

int main() {
    ui_init();
    run_loop();
    return 0;
}
