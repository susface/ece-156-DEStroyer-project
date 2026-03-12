#pragma once
// ============================================================================
// progress.h -- In-place console progress bar
//
// Usage (same pattern for any attack — GPU or CPU):
//
//   Progress prog;
//   progress_start(&prog, "DES GPU Brute-Force", total_keys);
//
//   for (each chunk) {
//       do_work();
//       progress_update(&prog, keys_done_so_far);   // absolute, not delta
//   }
//
//   progress_finish(&prog, found);   // prints completed bar + newline
//
// progress_update redraws the bar in-place using \r — no extra newlines
// are printed during the search, so the result output appears cleanly
// below the completed bar.
// ============================================================================
#include <cstdint>

struct Progress {
    const char* label;      // shown at start: "  label:\n"
    uint64_t    total;      // total units of work
    uint64_t    done;       // units completed so far
    double      t_start;    // wall_time_sec() at progress_start()
    int         bar_width;  // visible fill characters (default 38)
};

// Begin a new progress bar. Prints the label line and the initial empty bar.
void progress_start(Progress* p, const char* label, uint64_t total);

// Redraw the bar. done is the ABSOLUTE number of units completed (not a delta).
// Safe to call from any thread context as long as stdout is not shared.
void progress_update(Progress* p, uint64_t done);

// Print the final completed (or partial) bar and advance past it with \n.
// found=true  → bar fills green   "Key found!"
// found=false → bar fills yellow  "Search complete"
void progress_finish(Progress* p, bool found);
