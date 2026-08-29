#include "term.h"
#include <pty.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <wchar.h>
#include <locale.h>
#include <stdio.h>

enum { S_TEXT = 0, S_ESC = 1, S_CSI = 2, S_OSC = 3, S_OSC_ESC = 4 };

static const uint32_t DEF_FG = 0xE5E5E5, DEF_BG = 0x000000;

static inline Cell* at(Term* t, int row, int col) {
    return &t->cells[(size_t)((t->head + row) % HIST) * t->cols + col];
}
static inline void touch(Term* t, int row) { t->dirty[(t->head + row) % HIST] = 1; }
static inline Cell blank(Term* t) { Cell c = {0, t->fg, t->bg, 0}; return c; }

void term_init(Term* t, int cols, int rows, const char* shell) {
    setlocale(LC_ALL, "C.UTF-8");
    t->cells = (Cell*)calloc((size_t)HIST * cols, sizeof(Cell));
    t->dirty = (uint8_t*)calloc(HIST, 1);
    t->fg = DEF_FG; t->bg = DEF_BG;
    for (int r = 0; r < HIST; r++)
        for (int c = 0; c < cols; c++) t->cells[(size_t)r * cols + c] = blank(t);
    t->cols = cols; t->rows = rows; t->head = 0;
    t->row = t->col = 0; t->pending = 0; t->flags = 0;
    t->scroll_top = 0; t->scroll_bot = rows - 1;
    t->saved_row = t->saved_col = 0;
    t->state = 0; t->nparams = t->cur = t->priv = 0;

    if (!shell) { t->pty_fd = open("/dev/null", O_RDWR); return; }
    struct winsize ws = {(unsigned short)rows, (unsigned short)cols, 0, 0};
    int fd;
    pid_t pid = forkpty(&fd, nullptr, nullptr, &ws);
    if (pid == 0) {
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        execl(shell, shell, "-i", (char*)nullptr);
        _exit(1);
    }
    t->pty_fd = fd;
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
}

// Resize the grid, preserving as much history as fits. No reflow: a line
// wider than the new width is truncated on the right.
void term_resize(Term* t, int cols, int rows) {
    int oldcols = t->cols;
    Cell* nu = (Cell*)calloc((size_t)HIST * cols, sizeof(Cell));
    int n = oldcols < cols ? oldcols : cols;
    for (int r = 0; r < HIST; r++) {
        memcpy(nu + (size_t)r * cols, t->cells + (size_t)r * oldcols,
               (size_t)n * sizeof(Cell));
        for (int c = n; c < cols; c++)
            nu[(size_t)r * cols + c] = {0, t->fg, t->bg, 0};
    }
    free(t->cells);
    t->cells = nu;
    t->cols = cols; t->rows = rows;
    t->scroll_top = 0; t->scroll_bot = rows - 1;
    t->pending = 0;
    if (t->col >= cols) t->col = cols - 1;
    if (t->row >= rows) t->row = rows - 1;
    memset(t->dirty, 1, HIST);
}

void term_destroy(Term* t) {
    close(t->pty_fd);
    free(t->cells);
    free(t->dirty);
}

void term_send(Term* t, const char* buf, int n) {
    write(t->pty_fd, buf, n);
}

static void scroll_up(Term* t) {
    int top = t->scroll_top, bot = t->scroll_bot;
    t->head = (t->head + 1) % HIST;
    Cell* line = &t->cells[(size_t)((t->head + bot) % HIST) * t->cols];
    for (int c = 0; c < t->cols; c++) line[c] = blank(t);
    for (int r = top; r <= bot; r++) touch(t, r);
}

static void scroll_up_region(Term* t) {
    if (t->scroll_top == 0) { scroll_up(t); return; }
    for (int r = t->scroll_top; r < t->scroll_bot; r++) {
        memcpy(at(t, r, 0), at(t, r + 1, 0), (size_t)t->cols * sizeof(Cell));
        touch(t, r);
    }
    for (int c = 0; c < t->cols; c++) *at(t, t->scroll_bot, c) = blank(t);
    touch(t, t->scroll_bot);
}

static void scroll_down(Term* t) {
    for (int r = t->scroll_bot; r > t->scroll_top; r--) {
        memcpy(at(t, r, 0), at(t, r - 1, 0), (size_t)t->cols * sizeof(Cell));
        touch(t, r);
    }
    for (int c = 0; c < t->cols; c++) *at(t, t->scroll_top, c) = blank(t);
    touch(t, t->scroll_top);
}

static void newline(Term* t) {
    t->pending = 0;
    if (t->row == t->scroll_bot) { scroll_up(t); return; }
    t->row++;
    touch(t, t->row);
}

static void put(Term* t, uint32_t cp) {
    if (t->pending) { t->col = 0; newline(t); }
    int width = wcwidth((wchar_t)cp);
    if (width == 0) return;
    if (width < 0) width = 1;
    if (t->col + width > t->cols) { t->col = 0; newline(t); }
    uint32_t f = t->flags << 24;
    if (width == 2) f |= CF_WIDE;
    uint32_t slot = glyph_slot(cp, width == 2);
    Cell c1 = {cp | f, t->fg, t->bg, slot};
    *at(t, t->row, t->col) = c1;
    touch(t, t->row);
    t->col++;
    if (width == 2) {
        Cell c2 = {cp | (f & ~CF_WIDE) | CF_TAIL, t->fg, t->bg, slot ? slot + 1 : 0};
        *at(t, t->row, t->col) = c2;
        t->col++;
    }
    if (t->col >= t->cols) { t->col = t->cols - 1; t->pending = 1; }
}

static void clear(Term* t, int mode) {
    int r0 = 0, r1 = t->rows - 1, c0 = 0, c1 = t->cols - 1;
    if (mode == 0) { r0 = t->row; c0 = t->col; }
    else if (mode == 1) { r1 = t->row; c1 = t->col; }
    for (int r = r0; r <= r1; r++) {
        Cell* line = at(t, r, 0);
        for (int c = (r == r0 ? c0 : 0); c <= (r == r1 ? c1 : t->cols - 1); c++)
            line[c] = blank(t);
        touch(t, r);
    }
}

static int param(Term* t, int i, int def) {
    return (i < t->nparams && t->params[i] > 0) ? t->params[i] : def;
}

static uint32_t c256(int n) {
    static const uint8_t base[16][3] = {
        {0,0,0},{205,0,0},{0,205,0},{205,205,0},{0,0,238},{205,0,205},{0,205,205},{229,229,229},
        {127,127,127},{255,0,0},{0,255,0},{255,255,0},{92,92,255},{255,0,255},{0,255,255},{255,255,255}};
    if (n < 16) return (uint32_t)base[n][0] << 16 | base[n][1] << 8 | base[n][2];
    if (n < 232) {
        n -= 16;
        int r = n / 36, g = (n / 6) % 6, b = n % 6;
        auto v = [](int x) { return x ? 55 + x * 40 : 0; };
        return (uint32_t)v(r) << 16 | v(g) << 8 | v(b);
    }
    int v = 8 + (n - 232) * 10;
    return (uint32_t)v << 16 | v << 8 | v;
}

static void sgr(Term* t) {
    if (t->nparams == 0) { t->fg = DEF_FG; t->bg = DEF_BG; t->flags = 0; return; }
    for (int i = 0; i < t->nparams; i++) {
        int p = t->params[i];
        if (p == 0) { t->fg = DEF_FG; t->bg = DEF_BG; t->flags = 0; }
        else if (p == 1) t->flags |= 4;
        else if (p == 4) t->flags |= 8;
        else if (p == 7) t->flags |= 16;
        else if (p == 22) t->flags &= ~4u;
        else if (p == 24) t->flags &= ~8u;
        else if (p == 27) t->flags &= ~16u;
        else if (p >= 30 && p <= 37) t->fg = c256(p - 30);
        else if (p >= 90 && p <= 97) t->fg = c256(p - 90 + 8);
        else if (p == 39) t->fg = DEF_FG;
        else if (p >= 40 && p <= 47) t->bg = c256(p - 40);
        else if (p >= 100 && p <= 107) t->bg = c256(p - 100 + 8);
        else if (p == 49) t->bg = DEF_BG;
        else if (p == 38 || p == 48 || p == 58) {
            uint32_t* dst = p == 38 ? &t->fg : p == 48 ? &t->bg : nullptr;
            if (i + 1 >= t->nparams) break;
            if (t->params[i + 1] == 5 && i + 2 < t->nparams) {
                if (dst) *dst = c256(t->params[i + 2] & 0xff);
                i += 2;
            } else if (t->params[i + 1] == 2 && i + 4 < t->nparams) {
                if (dst) *dst = (uint32_t)(t->params[i + 2] & 0xff) << 16
                     | (uint32_t)(t->params[i + 3] & 0xff) << 8
                     | (uint32_t)(t->params[i + 4] & 0xff);
                i += 4;
            }
        }
    }
}

static void csi(Term* t, int final) {
    switch (final) {
    case 'H': case 'f':
        t->pending = 0;
        t->row = param(t, 0, 1) - 1; t->col = param(t, 1, 1) - 1;
        break;
    case 'A': t->row -= param(t, 0, 1); break;
    case 'B': t->row += param(t, 0, 1); break;
    case 'C': t->col += param(t, 0, 1); t->pending = 0; break;
    case 'D': t->col -= param(t, 0, 1); t->pending = 0; break;
    case 'G': t->col = param(t, 0, 1) - 1; t->pending = 0; break;
    case 'd': t->row = param(t, 0, 1) - 1; break;
    case 'J': clear(t, t->nparams ? t->params[0] : 0); break;
    case 'K': {
        int mode = t->nparams ? t->params[0] : 0;
        int from = mode == 1 ? 0 : t->col;
        int to = mode == 0 ? t->col : t->cols - 1;
        for (int c = from; c <= to; c++) *at(t, t->row, c) = blank(t);
        touch(t, t->row);
        break;
    }
    case 'S': { int n = param(t, 0, 1); for (int i = 0; i < n; i++) scroll_up_region(t); break; }
    case 'T': { int n = param(t, 0, 1); for (int i = 0; i < n; i++) scroll_down(t); break; }
    case 'L': {
        int n = param(t, 0, 1);
        for (int r = t->scroll_bot; r > t->row; r--) {
            int src = r - n;
            if (src >= t->row)
                memcpy(at(t, r, 0), at(t, src, 0), (size_t)t->cols * sizeof(Cell));
            else {
                for (int c = 0; c < t->cols; c++) *at(t, r, c) = blank(t);
            }
            touch(t, r);
        }
        break;
    }
    case 'M': {
        int n = param(t, 0, 1);
        for (int r = t->row; r <= t->scroll_bot; r++) {
            int src = r + n;
            if (src <= t->scroll_bot)
                memcpy(at(t, r, 0), at(t, src, 0), (size_t)t->cols * sizeof(Cell));
            else {
                for (int c = 0; c < t->cols; c++) *at(t, r, c) = blank(t);
            }
            touch(t, r);
        }
        break;
    }
    case 'X': {
        int n = param(t, 0, 1);
        for (int c = t->col; c < t->col + n && c < t->cols; c++) *at(t, t->row, c) = blank(t);
        touch(t, t->row);
        break;
    }
    case 'P': {
        int n = param(t, 0, 1);
        for (int c = t->col; c < t->cols; c++)
            *at(t, t->row, c) = (c + n < t->cols) ? *at(t, t->row, c + n) : blank(t);
        touch(t, t->row);
        break;
    }
    case '@': {
        int n = param(t, 0, 1);
        for (int c = t->cols - 1; c >= t->col + n; c--)
            *at(t, t->row, c) = *at(t, t->row, c - n);
        for (int c = t->col; c < t->col + n && c < t->cols; c++) *at(t, t->row, c) = blank(t);
        touch(t, t->row);
        break;
    }
    case 'r': {
        int top = param(t, 0, 1) - 1, bot = param(t, 1, t->rows) - 1;
        if (top >= 0 && bot < t->rows && top < bot) {
            t->scroll_top = top; t->scroll_bot = bot;
            t->row = 0; t->col = 0;
        }
        break;
    }
    case 's': t->saved_row = t->row; t->saved_col = t->col; break;
    case 'u': t->row = t->saved_row; t->col = t->saved_col; break;
    case 'm': sgr(t); break;
    }
    if (t->row < 0) t->row = 0;
    if (t->row >= t->rows) t->row = t->rows - 1;
    if (t->col < 0) t->col = 0;
    if (t->col >= t->cols) t->col = t->cols - 1;
}

void term_feed(Term* t, const char* buf, int n) {
    uint32_t cp = 0;
    int utf8_left = 0;
    for (int i = 0; i < n; i++) {
        unsigned char c = buf[i];
        if (utf8_left) { cp = cp << 6 | (c & 0x3f); if (--utf8_left == 0) put(t, cp); continue; }
        if (c >= 0xc0) { cp = c & (c >= 0xe0 ? (c >= 0xf0 ? 0x07 : 0x0f) : 0x1f); utf8_left = c >= 0xe0 ? (c >= 0xf0 ? 3 : 2) : 1; continue; }
        if (c < 0x80) cp = c; else continue;

        if (t->state == S_ESC) {
            if (c == 'M') { if (t->row == t->scroll_top) scroll_down(t); else if (t->row > 0) t->row--; }
            else if (c == 'D') newline(t);
            else if (c == 'E') { t->col = 0; newline(t); }
            else if (c == '7') { t->saved_row = t->row; t->saved_col = t->col; }
            else if (c == '8') { t->row = t->saved_row; t->col = t->saved_col; }
            else if (c == 'c') { clear(t, 2); t->row = t->col = 0; t->scroll_top = 0; t->scroll_bot = t->rows - 1; }
            else if (c == '[') { t->state = S_CSI; t->nparams = t->cur = 0; t->priv = 0; continue; }
            else if (c == ']') { t->state = S_OSC; continue; }
            t->state = S_TEXT;
            t->nparams = t->cur = 0;
            continue;
        }
        if (t->state == S_OSC) {
            if (c == 0x07) t->state = S_TEXT;
            else if (c == 0x1b) t->state = S_OSC_ESC;
            continue;
        }
        if (t->state == S_OSC_ESC) {
            t->state = S_TEXT;
            continue;
        }
        if (t->state == S_CSI) {
            if (c >= '0' && c <= '9') {
                if (t->nparams == 0) { t->nparams = 1; t->params[0] = 0; }
                int& p = t->params[t->nparams - 1];
                p = t->cur ? p * 10 + (c - '0') : c - '0';
                t->cur = 1;
            } else if (c == ';' || c == ':') {
                if (t->nparams < 16) t->nparams++;
                t->cur = 0;
                t->params[t->nparams - 1] = 0;
            } else if (c == '?' || c == '>') {
                t->priv = 1;
            } else if (c >= 0x40 && c <= 0x7e) {
                t->state = S_TEXT;
                if (!t->priv) csi(t, c);
                t->priv = 0;
            }
            continue;
        }
        switch (c) {
        case '\n': case 0x0b: case 0x0c: newline(t); break;
        case '\r': t->col = 0; t->pending = 0; break;
        case '\b': if (t->col > 0) t->col--; t->pending = 0; break;
        case '\t': {
            int nc = ((t->col / 8) + 1) * 8;
            t->col = nc < t->cols ? nc : t->cols - 1;
            t->pending = 0;
            break;
        }
        case 0x1b: t->state = S_ESC; break;
        default: if (c >= 0x20) put(t, c);
        }
    }
}
