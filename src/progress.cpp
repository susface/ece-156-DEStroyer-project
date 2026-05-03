// ============================================================================
// progress.cpp -- In-place console progress bar implementation
// ============================================================================
#include <windows.h>
#include <cstdio>
#include <cstring>
#include "progress.h"
#include "common.h"     // wall_time_sec()

// Color macros as #defines for string literal concatenation
#define RESET   "\033[0m"
#define DIM     "\033[2m"
#define BGREEN  "\033[92m"
#define BYELLOW "\033[93m"
#define BRED    "\033[91m"
#define BCYAN   "\033[96m"
#define BWHITE  "\033[97m"

// Block fill characters (UTF-8, works because ui_init sets CP_UTF8)
#define FILL_CHAR  "\xe2\x96\x88"   // U+2588  FULL BLOCK      █
#define EMPTY_CHAR "\xe2\x96\x91"   // U+2591  LIGHT SHADE     ░

// ── helpers ───────────────────────────────────────────────────────────────────

// Format a key count into a human-readable string: 1.2M, 345.6K, 12.3B, etc.
static void fmt_keys(char* buf, size_t buf_sz, uint64_t n) {
    if      (n >= 1000000000ULL) snprintf(buf, buf_sz, "%.1fB", n / 1e9);
    else if (n >= 1000000ULL)    snprintf(buf, buf_sz, "%.1fM", n / 1e6);
    else if (n >= 1000ULL)       snprintf(buf, buf_sz, "%.1fK", n / 1e3);
    else                         snprintf(buf, buf_sz, "%llu",  (unsigned long long)n);
}

// ── draw ──────────────────────────────────────────────────────────────────────

static void draw_bar(Progress* p, bool finished, bool found) {
    double elapsed = wall_time_sec() - p->t_start;
    double pct     = (p->total > 0)
                   ? (double)p->done / (double)p->total * 100.0
                   : 0.0;
    if (pct > 100.0) pct = 100.0;

    int filled = (int)(pct / 100.0 * p->bar_width + 0.5);
    if (filled > p->bar_width) filled = p->bar_width;
    int empty  = p->bar_width - filled;

    double kps = (elapsed > 0.001) ? (double)p->done / elapsed : 0.0;

    char done_str[16], total_str[16], kps_str[16];
    fmt_keys(done_str,  sizeof(done_str),  p->done);
    fmt_keys(total_str, sizeof(total_str), p->total);
    fmt_keys(kps_str,   sizeof(kps_str),   (uint64_t)kps);

    // Choose fill color based on state
    const char* fill_col;
    if (finished) {
        fill_col = found ? BGREEN : BYELLOW;
    } else {
        // Gradient: green → yellow → red as keyspace fills up
        if      (pct < 50.0) fill_col = BGREEN;
        else if (pct < 80.0) fill_col = BYELLOW;
        else                 fill_col = BRED;
    }

    // Print: \r moves back to line start, overwriting the previous bar.
    // ANSI codes don't add visible width so we don't need to track them.
    printf("\r  " BCYAN "[" RESET);

    // Filled portion
    if (filled > 0) {
        printf("%s", fill_col);
        for (int i = 0; i < filled; i++) printf(FILL_CHAR);
        printf(RESET);
    }

    // Empty portion
    if (empty > 0) {
        printf(DIM);
        for (int i = 0; i < empty; i++) printf(EMPTY_CHAR);
        printf(RESET);
    }

    printf(BCYAN "]" RESET);

    // Stats
    printf(BYELLOW "  %5.1f%%" RESET, pct);
    printf(DIM "  %s/%s" RESET, done_str, total_str);
    printf(DIM "  %.1fs" RESET, elapsed);
    if (!finished && kps > 0.0)
        printf(DIM "  %s k/s" RESET, kps_str);

    fflush(stdout);
}

// ── public API ────────────────────────────────────────────────────────────────

void progress_start(Progress* p, const char* label, uint64_t total) {
    p->label     = label;
    p->total     = total;
    p->done      = 0;
    p->t_start   = wall_time_sec();
    p->bar_width = 38;

    // Print label on its own line, then draw initial empty bar below it.
    printf("\n  " BCYAN "%s" RESET "\n", label);
    draw_bar(p, false, false);
}

void progress_update(Progress* p, uint64_t done) {
    p->done = done;
    draw_bar(p, false, false);
}

void progress_finish(Progress* p, bool found) {
    p->done = p->total;
    draw_bar(p, true, found);
    printf("\n");   // advance past the bar line
    fflush(stdout);
}
