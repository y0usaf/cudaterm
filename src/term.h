#pragma once
// Cell grid, VT parser, PTY.
// Cell is 16 bytes (uint4): cp|flags, fg RGB, bg RGB, pad.
// Flags: wide=1 tail=2 bold=4 underline=8 inverse=16
#include <stdint.h>

typedef struct { uint32_t cf, fg, bg, pad; } Cell;

#define HIST 1000

struct Term {
    Cell* cells;        // ring of HIST rows
    uint8_t* dirty;     // per-row upload flag
    int cols, rows, head;
    int row, col;
    int pending;        // deferred wrap at last column
    uint32_t fg, bg;    // current pen colors
    uint32_t flags;     // bold|underline|inverse for next put
    int scroll_top, scroll_bot;
    uint32_t saved_row, saved_col;
    // parser state
    int state;          // 0=text 1=after-ESC 2=in-CSI
    int params[16];
    int nparams, cur, priv;
    int pty_fd;
};

#define CF_WIDE 0x01000000u
#define CF_TAIL 0x02000000u
#define CF_BOLD 0x04000000u
#define CF_UNDER 0x08000000u
#define CF_INV 0x10000000u

void term_init(Term* t, int cols, int rows, const char* shell);
void term_resize(Term* t, int cols, int rows);
uint32_t glyph_slot(uint32_t cp, int wide);
void term_destroy(Term* t);
void term_feed(Term* t, const char* buf, int n);
void term_send(Term* t, const char* buf, int n);
