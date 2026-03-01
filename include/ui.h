#pragma once
// ============================================================================
// ui.h -- DEStroyer console UI
// All color codes, menu definitions, and UI function declarations
// ============================================================================

// ANSI color codes
#define RESET      "\033[0m"
#define BOLD       "\033[1m"
#define DIM        "\033[2m"
#define WHITE      "\033[37m"
#define BWHITE     "\033[97m"
#define BCYAN      "\033[96m"
#define BGREEN     "\033[92m"
#define BYELLOW    "\033[93m"
#define BRED       "\033[91m"
#define RED        "\033[31m"
#define BG_BLUE    "\033[44m"

// Red-to-orange gradient used in the banner
#define GR1        "\033[91m"           // bright red
#define GR2        "\033[38;5;202m"     // red-orange
#define GR3        "\033[38;5;208m"     // orange
#define GR4        "\033[38;5;214m"     // amber

// Menu layout constants (all in visible characters)
#define MENU_INDENT  "  "   // left margin for the box
#define MENU_W       58     // visible content width between | and |

// ============================================================================
// Menu item definitions
// ============================================================================
struct MenuItem {
    const char* label;    // short name shown in menu
    const char* desc;     // description shown dimmed on the right
    const char* section;  // non-null = print a section header before this item
};

extern const MenuItem MENU_ITEMS[];
extern const int      MENU_COUNT;

// ============================================================================
// UI functions
// ============================================================================
void ui_init();                        // set UTF-8 code page + VT processing
void ui_clear();                       // cls
int  ui_read_key();                    // blocking single keypress; -1=up -2=down 13=enter
void ui_press_enter();                 // "Press Enter..." prompt

void ui_print_banner();                // DEStroyer ASCII art header
void ui_print_menu(int selected);      // full interactive menu box
