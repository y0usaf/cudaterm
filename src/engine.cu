#include "engine.cuh"
#include "runtime.hpp"
#include "inflate.cuh"
#include "face.hpp"
#include "emoji_vs16.cuh"
#include "emoji_modifiers.cuh"
#include "grapheme_properties.cuh"
#include "mark_pool.cuh"
#include "mark_compaction.cuh"
#include "hyperlinks.cuh"
#include "keyboard_protocol.cuh"

#include <algorithm>
#include <cstring>
#include <cub/block/block_scan.cuh>
#include <cub/device/device_scan.cuh>
#include <cuda_runtime.h>
#include <fstream>
#include <stdexcept>
#ifndef CUDATERM_DATA_DIR
#define CUDATERM_DATA_DIR "."
#endif

namespace ct {
namespace {
template <typename T> __device__ T dmin(T a, T b) { return a < b ? a : b; }
template <typename T> __device__ T dmax(T a, T b) { return a > b ? a : b; }
template <typename T> __device__ void dswap(T &a, T &b) {
  T t = a;
  a = b;
  b = t;
}

__device__ void reverse_rows(int *rows, int count) {
  for (int i = 0; i < count / 2; ++i)
    dswap(rows[i], rows[count - i - 1]);
}
__device__ void rotate_rows(int *rows, int count, int shift) {
  shift %= count;
  if (!shift)
    return;
  reverse_rows(rows, shift);
  reverse_rows(rows + shift, count - shift);
  reverse_rows(rows, count);
}

constexpr uint32_t COLOR_INDEX = 0x01000000;
constexpr uint32_t DEFAULT_FG = COLOR_INDEX + 256, DEFAULT_BG = COLOR_INDEX + 257;
constexpr uint32_t BOLD = 1, UNDERLINE = 2, INVERSE = 4, DIM = 8;
constexpr uint32_t WIDE = 16, TAIL = 32, ITALIC = 64, STRIKE = 128, HIDDEN = 256;
constexpr int MAX_COLS = 512, MAX_ROWS = 256, REPLY_CAP = 4096;
constexpr int HISTORY_CAP = 4096;

struct ReplyBuffer {
  int length;
  int synchronized_updates;
  unsigned char bytes[REPLY_CAP];
  int title_changed;
  char title[512];
};
struct FillJob {
  Cell *first;
  int count;
  Cell value;
  const Cell *source = nullptr;
};
#include "graphics_types.cuh"
struct DeviceState {
  Theme theme, base_theme;
  int cell_width, cell_height;
  unsigned background_alpha;
  const unsigned char *face_pixels[4];
  const uint32_t *face_pages[4], *face_map[4];
  int padding_x, padding_y, cursor_style, default_cursor_style;
  int cursor_phase, window_focused;
  float cursor_x, cursor_y;
  int face_width, face_height;
  int osc_kind, osc_len;
  char osc_text[512];
  Hyperlinks *hyperlinks;
  bool hyperlinks_disabled;
  uint32_t hyperlink_id;
  GraphicsState *graphics;
  mark_pool::Arena marks;
  const uint16_t *font_rows;
  const uint32_t *font_pages, *font_map;
  const unsigned char *font_widths;
  const unsigned char *text_widths;
  const signed char *mark_offsets;
  uint32_t *repair_flags;
  int complex_cells, repair_row;
  FillJob *jobs;
  int job_count;
  int rowmap[MAX_ROWS], alt_rowmap[MAX_ROWS];
  int *row_wrap, *alt_row_wrap, *history_wrap;
  Cell *grid;
  Cell *alt;
  Cell *history;
  int history_count, history_head, history_cols, history_capacity, view_offset;
  ReplyBuffer *replies;
  int reply_len, cols, rows, row, col, saved_row, saved_col;
  int top, bottom, esc, csi, osc, csi_n, csi_private, csi_ignore, csi_intermediate,
      csi_prefix, csi_has_param, params[16];
  keyboard::Negotiation keyboard;
  int main_saved, main_row, main_col, main_wrap, main_top, main_bottom,
      main_origin, main_autowrap;
  uint32_t main_fg, main_bg, main_flags;
  int main_g0, main_g1, main_charset;
  int origin, autowrap, insert_mode, saved_origin, saved_autowrap, saved_pending;
  uint32_t saved_fg, saved_bg, saved_flags;
  int saved_g0, saved_g1, saved_charset;
  int g0, g1, charset;
  unsigned char tabs[MAX_COLS];
  uint32_t fg, bg, flags;
  uint32_t utf, utf_min;
  int utf_need;
  int cursor_visible, app_cursor, bracketed_paste, app_keypad, numlock_override,
      alt_active, wrap_pending;
  uint32_t pending_cp;
  int pending_valid, pool_wait, mark_gc;
  int join_blocked;
  int mouse_mode, mouse_sgr, mouse_row, mouse_col;
  int mouse_pixels, focus_reporting, synchronized_updates;
  int copy_flash;
  int selection_active, selection_start_row, selection_start_col;
  int selection_end_row, selection_end_col, selection_rectangle;
  unsigned char *selection_output;
  size_t selection_output_len;
};

__device__ void reply(DeviceState &s, const char *x, int n) {
  for (int i = 0; i < n && s.reply_len < REPLY_CAP; ++i)
    s.replies->bytes[s.reply_len++] = (unsigned char)x[i];
  s.replies->length = s.reply_len;
}
__host__ __device__ uint32_t resolved(const DeviceState &s, uint32_t color) {
  return color >= COLOR_INDEX && color < COLOR_INDEX + 259
    ? s.theme.colors[color - COLOR_INDEX] : color;
}
#include "appearance.cuh"
__device__ void clear_cell(Cell &c, uint32_t fg, uint32_t bg) {
  c = {32, fg, bg, 0};
}
__device__ int at(const DeviceState &s, int r, int c) {
  return s.rowmap[r] * s.cols + c;
}
__device__ void clear_history(DeviceState &s) {
  s.history_count = s.history_head = s.view_offset = 0;
  s.mark_gc = 1;
  for (int i = 0; i < s.history_capacity; ++i)
    s.history_wrap[i] = 0;
}
__device__ void graphics_clear(DeviceState &s, int screen) {
  auto &g = *s.graphics;
  g.request = {};
  g.request.ready = g.request.reset = 1;
  for (int i = 0; i < IMAGE_SLOTS; ++i) {
    if (!g.images[i].pixels || (screen >= 0 && g.images[i].screen != screen)) continue;
    g.request.release[i / 32] |= 1u << (i % 32);
    // A released image owns the bytes referenced by every placement, even
    // one pinned to the other screen. Remove those records before the host
    // frees the allocation.
    for (int j = 0; j < GRAPHIC_PLACEMENT_SLOTS; ++j)
      if (g.placements[j].occupied && g.placements[j].image_slot == i)
        g.placements[j] = {};
  }
  for (int i = 0; i < GRAPHIC_PLACEMENT_SLOTS; ++i)
    if (g.placements[i].occupied &&
        (screen < 0 || g.placements[i].screen == screen))
      g.placements[i] = {};
  g.visible_count = 0;
}
__device__ void graphics_scroll(DeviceState &s, int top, int bottom, int count) {
  auto &g = *s.graphics;
  for (int i = 0; i < g.visible_count; ++i) {
    auto &placement = g.placements[g.visible[i]];
    if (placement.screen != s.alt_active || !placement.occupied || !placement.visible) continue;
    bool full = top == 0 && bottom == s.rows - 1;
    if ((full && placement.py < (bottom + 1) * s.cell_height && placement.py + placement.height_crop > 0) ||
        (!full && placement.py >= top * s.cell_height && placement.py + placement.height_crop <= (bottom + 1) * s.cell_height)) {
      placement.py -= count * s.cell_height;
      if (top || bottom != s.rows - 1 || s.alt_active) {
        int cut = dmax(0, top * s.cell_height - placement.py);
        placement.sy += cut; placement.py += cut; placement.height_crop -= cut;
        placement.height_crop = dmin(placement.height_crop, (bottom + 1) * s.cell_height - placement.py);
        if (placement.height_crop <= 0) placement.visible = 0;
      }
    } else if (!s.alt_active && top == 0 && bottom == s.rows - 1 && placement.py < 0) {
      placement.py -= count * s.cell_height;
      if (placement.py + placement.height_crop < -HISTORY_CAP * s.cell_height) placement.visible = 0;
    }
  }
}
__device__ void history_push(DeviceState &s, const Cell *row) {
  Cell *dst = s.history + s.history_head * s.history_cols;
  s.history_wrap[s.history_head] = s.row_wrap[s.rowmap[s.top]];
  // Capture after earlier queued edits and before recycling clears the row.
  s.jobs[s.job_count++] = {dst, s.cols, {}, row};
  s.history_head = (s.history_head + 1) % s.history_capacity;
  if (s.history_count < s.history_capacity)
    ++s.history_count;
  if (s.view_offset > 0)
    s.view_offset = dmin(s.history_capacity, s.view_offset + 1);
}
__device__ int reserve_history(DeviceState &s, int count) {
  if (!count || s.alt_active || s.top || s.bottom != s.rows - 1)
    return -1;
  int base = s.history_head;
  s.history_head = (base + count) % s.history_capacity;
  s.history_count = dmin(s.history_capacity, s.history_count + count);
  if (s.view_offset)
    s.view_offset = dmin(s.history_count, s.view_offset + count);
  return base;
}
__device__ Cell *bulk_row(DeviceState &s, int logical, int scroll, int base) {
  int row = logical - scroll;
  if (row >= 0 && row < s.rows)
    return s.grid + at(s, row, 0);
  if (base >= 0 && logical >= dmax(0, scroll - s.history_capacity) &&
      logical < scroll)
    return s.history + ((base + logical) % s.history_capacity) * s.history_cols;
  return nullptr;
}
__device__ int *bulk_wrap(DeviceState &s, int logical, int scroll, int base) {
  int row = logical - scroll;
  if (row >= 0 && row < s.rows) return &s.row_wrap[s.rowmap[row]];
  if (base >= 0 && logical >= dmax(0, scroll - s.history_capacity) && logical < scroll)
    return &s.history_wrap[(base + logical) % s.history_capacity];
  return nullptr;
}
// Commits rotate only row indices. Read the old rows through the inverse
// rotation before any clearing or painting overwrites their physical cells.
template <class Meta>
__global__ void prepare_history(DeviceState *s, const int *accepted,
                                const Meta *m) {
  if (*accepted < 256 || m->history_base < 0)
    return;
  int first = dmax(0, m->scroll - s->history_capacity);
  int count = m->scroll - first;
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < count * s->cols;
       i += blockDim.x * gridDim.x) {
    int logical = first + i / s->cols, col = i % s->cols;
    Cell value = {32, s->fg, s->bg, 0};
    if (logical < s->rows) {
      int oldrow = (logical - m->scroll % s->rows + s->rows) % s->rows;
      value = s->grid[at(*s, oldrow, col)];
      if (col == 0)
        s->history_wrap[(m->history_base + logical) % s->history_capacity] =
        s->row_wrap[s->rowmap[oldrow]];
    } else if (col == 0) {
      s->history_wrap[(m->history_base + logical) % s->history_capacity] = 0;
    }
    s->history[((m->history_base + logical) % s->history_capacity) *
                   s->history_cols +
               col] = value;
  }
}
__device__ Cell viewed_cell(const DeviceState &s, int r, int c) {
  int logical = s.history_count + r - s.view_offset;
  if (logical < 0 || logical >= s.history_count + s.rows)
    return {32, DEFAULT_FG, DEFAULT_BG, 0};
  if (logical < s.history_count) {
    if (c >= s.history_cols)
      return {32, s.fg, s.bg, 0};
    return s.history[((s.history_head - s.history_count + logical +
                       s.history_capacity) %
                      s.history_capacity) *
                         s.history_cols +
                     c];
  }
  return s.grid[at(s, logical - s.history_count, c)];
}
__device__ int viewed_wrap(const DeviceState &s, int r) {
  int logical = s.history_count + r - s.view_offset;
  if (logical < 0 || logical >= s.history_count + s.rows) return 0;
  if (logical < s.history_count) {
    int slot = (s.history_head - s.history_count + logical + s.history_capacity) %
               s.history_capacity;
    return s.history_wrap[slot];
  }
  return s.row_wrap[s.rowmap[logical - s.history_count]];
}
__device__ void fill(DeviceState &s, Cell *first, int count, Cell value) {
  if (count > 0)
    s.jobs[s.job_count++] = {first, count, value};
}
__device__ void erase_line(DeviceState &s, int r, int a, int b) {
  if (a >= b)
    return;
  if (s.complex_cells) {
    if (a > 0 && (s.grid[at(s, r, a)].flags & TAIL))
      --a;
    if (b < s.cols && b > 0 && (s.grid[at(s, r, b - 1)].flags & WIDE))
      ++b;
  }
  int &length = s.row_wrap[s.rowmap[r]];
  if (length > 0 && b >= length)
    length = 0;
  fill(s, s.grid + at(s, r, a), b - a, {32, s.fg, s.bg, 0});
}
__device__ void shift_rows(DeviceState &s, int top, int bottom, int count,
                           bool up) {
  int height = bottom - top + 1;
  count = dmin(count, height);
  graphics_scroll(s, top, bottom, up ? count : -count);
  rotate_rows(s.rowmap + top, height, up ? count : height - count);
  if (top > 0)
    s.row_wrap[s.rowmap[top - 1]] = 0;
  int edge = up ? bottom - count : bottom;
  if (edge >= top && edge <= bottom)
    s.row_wrap[s.rowmap[edge]] = 0;
  int first = up ? bottom - count + 1 : top;
  for (int r = first; r < first + count; ++r)
    erase_line(s, r, 0, s.cols);
}
__device__ void scroll(DeviceState &s) {
  graphics_scroll(s, s.top, s.bottom, 1);
  if (s.top > 0)
    s.row_wrap[s.rowmap[s.top - 1]] = 0;
  if (!s.alt_active && s.top == 0 && s.bottom == s.rows - 1)
    history_push(s, s.grid + s.rowmap[s.top] * s.cols);
  int recycled = s.rowmap[s.top];
  for (int r = s.top; r < s.bottom; ++r)
    s.rowmap[r] = s.rowmap[r + 1];
  s.rowmap[s.bottom] = recycled;
  s.row_wrap[recycled] = 0;
  erase_line(s, s.bottom, 0, s.cols);
}
__device__ void tabs(DeviceState &s, int count, bool forward) {
  count = dmin(count, s.cols);
  s.wrap_pending = 0;
  for (int n = 0; n < count; ++n) {
    if (forward) {
      if (s.col == s.cols - 1)
        break;
      do {
        ++s.col;
      } while (s.col < s.cols - 1 && !s.tabs[s.col]);
    } else {
      if (s.col == 0)
        break;
      do {
        --s.col;
      } while (s.col > 0 && !s.tabs[s.col]);
    }
  }
}
__device__ void save_cursor(DeviceState &s) {
  s.saved_row = s.row;
  s.saved_col = s.col;
  s.saved_pending = s.wrap_pending;
  s.saved_fg = s.fg;
  s.saved_bg = s.bg;
  s.saved_flags = s.flags;
  s.saved_origin = s.origin;
  s.saved_autowrap = s.autowrap;
  s.saved_g0 = s.g0;
  s.saved_g1 = s.g1;
  s.saved_charset = s.charset;
}
__device__ void restore_cursor(DeviceState &s) {
  s.row = dmin(s.saved_row, s.rows - 1);
  s.col = dmin(s.saved_col, s.cols - 1);
  s.wrap_pending = s.saved_pending;
  s.fg = s.saved_fg;
  s.bg = s.saved_bg;
  s.flags = s.saved_flags;
  s.origin = s.saved_origin;
  s.autowrap = s.saved_autowrap;
  s.g0 = s.saved_g0;
  s.g1 = s.saved_g1;
  s.charset = s.saved_charset;
}
__device__ void newline(DeviceState &s, bool soft = false) {
  if (!soft)
    s.row_wrap[s.rowmap[s.row]] = 0;
  s.wrap_pending = 0;
  if (s.row == s.bottom)
    scroll(s);
  else
    s.row = dmin(s.rows - 1, s.row + 1);
}
__device__ void break_pair(DeviceState &s, int row, int col) {
  if (!s.complex_cells)
    return;
  uint32_t flags = s.grid[at(s, row, col)].flags;
  if ((flags & TAIL) && col > 0)
    fill(s, s.grid + at(s, row, col - 1), 1, {32, s.fg, s.bg, 0});
  if ((flags & WIDE) && col + 1 < s.cols)
    fill(s, s.grid + at(s, row, col + 1), 1, {32, s.fg, s.bg, 0});
}
__device__ void repair_row(DeviceState &s, int row) {
  if (!s.complex_cells)
    return;
  for (int c = 0; c < s.cols; ++c) {
    Cell &z = s.grid[at(s, row, c)];
    if (((z.flags & WIDE) &&
         (c == s.cols - 1 || !(s.grid[at(s, row, c + 1)].flags & TAIL))) ||
        ((z.flags & TAIL) &&
         (c == 0 || !(s.grid[at(s, row, c - 1)].flags & WIDE))))
      z = {32, s.fg, s.bg, 0};
  }
}
__device__ void insert_cells(DeviceState &s, int n) {
  n = dmin(n, s.cols - s.col);
  for (int c = s.cols - 1; c >= s.col + n; --c)
    s.grid[at(s, s.row, c)] = s.grid[at(s, s.row, c - n)];
  fill(s, s.grid + at(s, s.row, s.col), n, {32, s.fg, s.bg, 0});
  s.row_wrap[s.rowmap[s.row]] = 0;
  s.repair_row = s.row;
}
// Promote an eagerly printed base; queued edits precede any scroll copy.
__device__ bool promote_emoji(DeviceState &s, int col, Cell cell) {
  if (s.cols == 1 || (col == s.cols - 1 && !s.autowrap)) return false;
  int row = s.row;
  if (col == s.cols - 1) {
    bool recycled = s.row == s.bottom;
    fill(s, s.grid + at(s, row, col), 1, {32, s.fg, s.bg, 0});
    s.row_wrap[s.rowmap[row]] = s.cols - 1;
    newline(s, true);
    row = s.row;
    col = 0;
    // A recycled row is cleared by queued jobs; do not inspect its old pairs.
    if (!recycled) {
      if (s.insert_mode) {
        s.col = 0;
        insert_cells(s, 2);
      } else {
        break_pair(s, row, 0);
        break_pair(s, row, 1);
      }
    }
    cell.flags |= WIDE;
  } else {
    if (s.insert_mode) {
      int cursor = s.col;
      s.col = col + 1;
      insert_cells(s, 1);
      s.col = cursor;
    } else break_pair(s, row, col + 1);
    cell.flags |= WIDE;
  }
  fill(s, s.grid + at(s, row, col), 1, cell);
  fill(s, s.grid + at(s, row, col + 1), 1,
       {0, cell.fg, cell.bg, (cell.flags & ~WIDE) | TAIL});
  s.complex_cells = 1;
  int next = col + 2;
  if (next == s.cols) s.row_wrap[s.rowmap[row]] = 0;
  s.col = dmin(s.cols - 1, next);
  s.wrap_pending = next == s.cols && s.autowrap;
  return true;
}
// GB11's suffix test is deliberately based on the cell's complete mark
// sequence.  Overflow marks are immutable and newest-first, so walking the
// suffix backwards also works after compaction and across feed boundaries.
__device__ bool zwj_joinable(const DeviceState &s, const Cell &cell) {
  uint32_t used = *s.marks.used;
  if (used > s.marks.capacity) { *s.marks.status = mark_pool::MALFORMED; return false; }
  uint32_t ref = mark_pool::head(cell), cp = 0;
  int inline_pos = (int)mark_pool::inline_count(cell) - 1;
  bool saw_zwj = false;
  for (uint32_t steps = 0; ref || inline_pos >= 0; ++steps) {
    if (steps > used + 3) { *s.marks.status = mark_pool::MALFORMED; return false; }
    if (ref) {
      if (ref > used || s.marks.nodes[ref - 1].parent >= ref) {
        *s.marks.status = mark_pool::MALFORMED; return false;
      }
      cp = s.marks.nodes[ref - 1].cp;
      ref = s.marks.nodes[ref - 1].parent;
    } else {
      cp = cell.combining[inline_pos--];
    }
    if (!saw_zwj) {
      // A default ignorable may sit between the component and its ZWJ. It is
      // retained in the mark arena but does not change the GB11 suffix.
      if (grapheme_zwj_ignorable(cp)) continue;
      if (cp != 0x200d) return false;
      saw_zwj = true;
    } else if (grapheme_zwj_ignorable(cp)) {
      // Monstar keeps default ignorables transparent on either side of ZWJ.
      continue;
    } else if (!grapheme_extend(cp)) {
      return grapheme_extended_pictographic(cp);
    }
  }
  return saw_zwj && grapheme_extended_pictographic(cell.cp);
}
// Emoji modifiers are immediate to the last meaningful component, even when
// that component was appended after a ZWJ and the mark sequence spans feeds.
__device__ bool emoji_modifier_attachment(const DeviceState &s,
                                          const Cell &cell) {
  uint32_t used = *s.marks.used;
  if (used > s.marks.capacity) {
    *s.marks.status = mark_pool::MALFORMED;
    return false;
  }
  uint32_t ref = mark_pool::head(cell), cp = 0;
  int inline_pos = (int)mark_pool::inline_count(cell) - 1;
  for (uint32_t steps = 0; ref || inline_pos >= 0; ++steps) {
    if (steps > used + 3) {
      *s.marks.status = mark_pool::MALFORMED;
      return false;
    }
    if (ref) {
      if (ref > used || s.marks.nodes[ref - 1].parent >= ref) {
        *s.marks.status = mark_pool::MALFORMED;
        return false;
      }
      cp = s.marks.nodes[ref - 1].cp;
      ref = s.marks.nodes[ref - 1].parent;
    } else {
      cp = cell.combining[inline_pos--];
    }
    // VS16 is transparent to the modifier relation. Other default
    // ignorables and every ordinary Extend break the required adjacency.
    if (cp == 0xfe0f) continue;
    if (cp == 0x200d || grapheme_default_ignorable_zero(cp) ||
        grapheme_extend(cp))
      return false;
    return emoji_modifier_base(cp);
  }
  return emoji_modifier_base(cell.cp);
}
__device__ bool zwj_attachment(const DeviceState &s, uint32_t cp) {
  if (s.cols < 2 || s.join_blocked || !(s.col > 0 || s.wrap_pending) ||
      (!s.autowrap && s.col == s.cols - 1) ||
      !grapheme_extended_pictographic(cp)) return false;
  int previous = s.wrap_pending ? s.col : s.col - 1;
  if ((s.grid[at(s, s.row, previous)].flags & TAIL) && previous > 0) --previous;
  Cell cell = s.grid[at(s, s.row, previous)];
  int next = previous + ((cell.flags & WIDE) ? 2 : 1);
  return (s.wrap_pending ? next == s.cols : s.col == next) && zwj_joinable(s, cell);
}
__device__ void put(DeviceState &s, uint32_t cp, bool force_single = false) {
  int width = force_single ? 1 : s.text_widths[cp];
  bool modifier = !force_single && cp >= 0x1f3fb && cp <= 0x1f3ff;
  bool default_ignorable = !force_single &&
                           grapheme_default_ignorable_zero(cp);
  // Emoji modifiers are GCB Extend in Unicode, but Monstar tailors them to
  // remain visible as standalone scalars unless an emoji base accepts them.
  bool extend = !force_single && !modifier && grapheme_extend(cp);
  bool attach_modifier = false;
  bool attach_extend = false;
  bool attach_zwj = false;
  // A clipped no-wrap cursor cannot identify the last printed base reliably.
  if ((modifier || extend) && (s.col > 0 || s.wrap_pending) &&
      (s.autowrap || s.col < s.cols - 1)) {
    int previous = s.wrap_pending ? s.col : s.col - 1;
    if ((s.grid[at(s, s.row, previous)].flags & TAIL) && previous > 0)
      --previous;
    Cell cell = s.grid[at(s, s.row, previous)];
    // Marks retained on an untouched blank are leading marks, not a base for
    // a later Extend or emoji modifier. Explicit spaces remain valid bases.
    bool base = cell.cp != 32 || (cell.reserved & 1u);
    int next = previous + ((cell.flags & WIDE) ? 2 : 1);
    bool adjacent = s.wrap_pending ? next == s.cols : s.col == next;
    if (adjacent && base) {
      attach_modifier = modifier && emoji_modifier_attachment(s, cell);
      attach_extend = extend;
    }
  }
  attach_zwj = !force_single && zwj_attachment(s, cp);
  if (default_ignorable || attach_modifier || attach_extend || attach_zwj)
    width = 0;
  if (width == 0) {
    int col = s.wrap_pending ? s.col : dmax(0, s.col - 1);
    if ((s.grid[at(s, s.row, col)].flags & TAIL) && col > 0)
      --col;
    Cell cell = s.grid[at(s, s.row, col)];
    bool promote = (cp == 0xfe0f || attach_modifier || attach_zwj ||
                    (attach_extend && grapheme_extend_widthful(cp))) &&
                   !(cell.flags & WIDE) &&
      // With autowrap disabled the clipped cursor does not identify the last
      // printed cell; retain scalar behavior until that tracking is explicit.
      (s.autowrap || s.col < s.cols - 1) &&
      (attach_modifier || attach_zwj ||
       (attach_extend && grapheme_extend_widthful(cp)) ||
       (!cell.combining[0] && emoji_vs16_base(cell.cp)));
    if (!mark_pool::append_mark(cell, cp, s.marks)) {
      s.pending_cp = cp;
      s.pending_valid = s.pool_wait = 1;
      return;
    }
    if (!promote || !promote_emoji(s, col, cell))
      fill(s, s.grid + at(s, s.row, col), 1, cell);
    return;
  }
  if (width == 2 && s.cols == 1) {
    cp = 0xfffd;
    width = 1;
  }
  bool fresh_row = false;
  if (s.wrap_pending) {
    fresh_row = s.row == s.bottom;
    s.col = 0;
    s.row_wrap[s.rowmap[s.row]] = s.cols;
    newline(s, true);
  }
  if (width == 2 && s.col == s.cols - 1) {
    if (s.autowrap) {
      fresh_row = s.row == s.bottom;
      erase_line(s, s.row, s.col, s.cols);
      s.col = 0;
      s.row_wrap[s.rowmap[s.row]] = s.cols - 1;
      newline(s, true);
    } else {
      cp = 0xfffd;
      width = 1;
    }
  }
  // A scroll's history copy precedes its queued row clear. Do not shift that
  // recycled row before the copy; insertion into the cleared row needs no shift.
  if (s.insert_mode && !fresh_row)
    insert_cells(s, width);
  else {
    break_pair(s, s.row, s.col);
    if (width == 2)
      break_pair(s, s.row, s.col + 1);
  }
  if (s.col + width == s.cols)
    s.row_wrap[s.rowmap[s.row]] = 0;
  fill(s, s.grid + at(s, s.row, s.col), 1,
       {cp, s.fg, s.bg, s.flags | (s.hyperlink_id << HYPERLINK_SHIFT) | (width == 2 ? WIDE : 0), {}, cp == 32});
  if (width == 2) {
    fill(s, s.grid + at(s, s.row, s.col + 1), 1,
         {0, s.fg, s.bg, s.flags | (s.hyperlink_id << HYPERLINK_SHIFT) | TAIL});
    s.complex_cells = 1;
  }
  int next = s.col + width;
  s.col = dmin(s.cols - 1, next);
  s.wrap_pending = next == s.cols && s.autowrap;
  s.join_blocked = 0;
}
__device__ uint32_t dec_graphic(uint32_t cp) {
  if (cp < 0x5f || cp > 0x7e)
    return cp;
  static const uint32_t table[32] = {
      0x00a0, 0x25c6, 0x2592, 0x2409, 0x240c, 0x240d, 0x240a, 0x00b0,
      0x00b1, 0x2424, 0x240b, 0x2518, 0x2510, 0x250c, 0x2514, 0x253c,
      0x23ba, 0x23bb, 0x2500, 0x23bc, 0x23bd, 0x251c, 0x2524, 0x2534,
      0x252c, 0x2502, 0x2264, 0x2265, 0x03c0, 0x2260, 0x00a3, 0x00b7};
  return table[cp - 0x5f];
}
__device__ bool active_graphics(const DeviceState &s) {
  return s.charset ? s.g1 : s.g0;
}
__device__ uint32_t mapped_ascii(const DeviceState &s, unsigned char c) {
  return active_graphics(s) ? dec_graphic(c) : c;
}
__device__ int param(const DeviceState &s, int i, int d = 1) {
  return (i <= s.csi_n && s.params[i]) ? s.params[i] : d;
}
__device__ uint32_t color16(int n) { return COLOR_INDEX + (n & 15); }
__device__ uint32_t color256(int n) { return COLOR_INDEX + dmin(255, dmax(0, n)); }
template <class State>
__device__ void apply_sgr(State &s, uint32_t &shadow_flags) {
  for (int i = 0; i <= s.csi_n; ++i) {
    int p = s.params[i];
    if (p == 0) {
      s.fg = DEFAULT_FG;
      s.bg = DEFAULT_BG;
      s.flags = shadow_flags = 0;
    } else if (p == 1) {
      s.flags |= BOLD;
      shadow_flags |= BOLD;
    } else if (p == 2) {
      s.flags |= DIM;
      shadow_flags |= DIM;
    } else if (p == 3) {
      s.flags |= ITALIC; shadow_flags |= ITALIC;
    } else if (p == 9) {
      s.flags |= STRIKE; shadow_flags |= STRIKE;
    } else if (p == 8) {
      s.flags |= HIDDEN; shadow_flags |= HIDDEN;
    } else if (p == 23) {
      s.flags &= ~ITALIC; shadow_flags &= ~ITALIC;
    } else if (p == 29) {
      s.flags &= ~STRIKE; shadow_flags &= ~STRIKE;
    } else if (p == 28) {
      s.flags &= ~HIDDEN; shadow_flags &= ~HIDDEN;
    } else if (p == 4) {
      s.flags |= UNDERLINE;
      shadow_flags |= UNDERLINE;
    } else if (p == 7) {
      s.flags |= INVERSE;
      shadow_flags |= INVERSE;
    } else if (p == 22) {
      s.flags &= ~(BOLD | DIM);
      shadow_flags &= ~(BOLD | DIM);
    } else if (p == 24) {
      s.flags &= ~UNDERLINE;
      shadow_flags &= ~UNDERLINE;
    } else if (p == 27) {
      s.flags &= ~INVERSE;
      shadow_flags &= ~INVERSE;
    }
    else if (p == 39)
      s.fg = DEFAULT_FG;
    else if (p == 49)
      s.bg = DEFAULT_BG;
    else if (p >= 30 && p <= 37)
      s.fg = color16(p - 30);
    else if (p >= 40 && p <= 47)
      s.bg = color16(p - 40);
    else if (p >= 90 && p <= 97)
      s.fg = color16(p - 90 + 8);
    else if (p >= 100 && p <= 107)
      s.bg = color16(p - 100 + 8);
    else if (p == 38 || p == 48) {
      if (i + 2 <= s.csi_n && s.params[i + 1] == 5) {
        uint32_t v = s.params[i + 2];
        uint32_t r = color256(v);
        if (p == 38)
          s.fg = r;
        else
          s.bg = r;
        i += 2;
      } else if (i + 4 <= s.csi_n && s.params[i + 1] == 2) {
        uint32_t r = dmin(255, s.params[i + 2]), g = dmin(255, s.params[i + 3]),
                 b = dmin(255, s.params[i + 4]);
        uint32_t v = (r << 16) | (g << 8) | b;
        if (p == 38)
          s.fg = v;
        else
          s.bg = v;
        i += 4;
      }
    }
  }
}
template <class State> __device__ void apply_sgr(State &s) {
  apply_sgr(s, s.flags);
}
__device__ void switch_screen(DeviceState &s, bool on) {
  if (bool(s.alt_active) == on)
    return;
  dswap(s.grid, s.alt);
  dswap(s.row_wrap, s.alt_row_wrap);
  for (int r = 0; r < s.rows; ++r)
    dswap(s.rowmap[r], s.alt_rowmap[r]);
  s.alt_active = on;
  // Hyperlink state belongs to the active screen. Monstar/Ghostty end it
  // whenever the active screen changes, so it must never leak into the new
  // screen or be restored from an ID that may have been evicted.
  s.hyperlink_id = 0;
  s.view_offset = 0;
  // Yield at screen transitions so the host can reserve history before any
  // subsequent primary-screen output, without reserving it for TUI frames.
  auto &request = s.graphics->request;
  if (!request.ready) request = {};
  request.ready = request.barrier = 1;
}
__device__ void alternate_screen(DeviceState &s, bool on) {
  if (on) {
    if (!s.alt_active) {
      graphics_clear(s, 1);
      fill(s, s.alt, s.cols * s.rows, {32, s.fg, s.bg, 0});
      for (int r = 0; r < s.rows; ++r)
        s.alt_row_wrap[r] = 0;
      switch_screen(s, true);
      s.main_saved = 1;
      s.main_row = s.row;
      s.main_col = s.col;
      s.main_wrap = s.wrap_pending;
      s.main_top = s.top;
      s.main_bottom = s.bottom;
      s.main_origin = s.origin;
      s.main_autowrap = s.autowrap;
      s.main_fg = s.fg;
      s.main_bg = s.bg;
      s.main_flags = s.flags;
      s.main_g0 = s.g0;
      s.main_g1 = s.g1;
      s.main_charset = s.charset;
    }
    return;
  }
  if (!on) {
    if (s.alt_active) {
      graphics_clear(s, 1);
      switch_screen(s, false);
      if (!s.main_saved)
        return;
      s.main_saved = 0;
      s.row = dmin(s.main_row, s.rows - 1);
      s.col = dmin(s.main_col, s.cols - 1);
      s.wrap_pending = s.main_wrap;
      s.top = s.main_top;
      s.bottom = s.main_bottom;
      s.origin = s.main_origin;
      s.autowrap = s.main_autowrap;
      s.fg = s.main_fg;
      s.bg = s.main_bg;
      s.flags = s.main_flags;
      s.g0 = s.main_g0;
      s.g1 = s.main_g1;
      s.charset = s.main_charset;
    }
    return;
  }
}
__device__ void kitty_keyboard_reply(DeviceState &s) {
  char out[32] = {27, '[', '?'};
  int n = osc_decimal(out, 3,
                      static_cast<int>(keyboard::current(s.keyboard,
                                                          s.alt_active != 0)));
  out[n++] = 'u';
  reply(s, out, n);
}
__device__ void kitty_keyboard_command(DeviceState &s) {
  const bool alternate = s.alt_active != 0;
  switch (s.csi_prefix) {
  case '?':
    // CSI ? u is the only Kitty query.  The parser tracks whether a parameter
    // was present so explicit CSI ? 0 u remains malformed rather than being
    // confused with the omitted form.
    if (!s.csi_has_param)
      kitty_keyboard_reply(s);
    break;
  case '>':
    if (s.csi_n == 0)
      keyboard::push(s.keyboard, alternate, static_cast<uint32_t>(s.params[0]));
    break;
  case '<':
    if (s.csi_n == 0)
      keyboard::pop(s.keyboard, alternate,
                    s.csi_has_param ? static_cast<uint32_t>(s.params[0]) : 1u);
    break;
  case '=': {
    if (s.csi_n > 1)
      break;
    const uint32_t mode = s.csi_n == 0 ? 1u : static_cast<uint32_t>(s.params[1]);
    keyboard::set(s.keyboard, alternate, static_cast<uint32_t>(s.params[0]), mode);
  } break;
  default:
    break;
  }
}
__device__ void csi(DeviceState &s, unsigned char f) {
  if (f == 'u' && s.csi_prefix && !s.csi_intermediate) {
    kitty_keyboard_command(s);
    return;
  }
  // Kitty's >, =, and < prefixes belong only to the keyboard protocol.  Do
  // not let a malformed prefixed CSI reach a legacy handler (for example,
  // CSI >5n must not be mistaken for a device-status report).
  if (s.csi_prefix == '>' || s.csi_prefix == '=' || s.csi_prefix == '<')
    return;
  if (s.csi_intermediate) {
    if (s.csi_intermediate == ' ' && f == 'q' && !s.csi_private && !s.csi_n && s.params[0] <= 6)
      s.cursor_style = s.params[0];
    return;
  }
  int a = param(s, 0), b = param(s, 1);
  if (f != 'm' && f != 'n' && f != 'c' && f != 't')
    s.join_blocked = 1;
  if (f != 'm' && f != 'n' && f != 'c' && f != 'h' && f != 'l')
    s.wrap_pending = 0;
  switch (f) {
  case 'F':
    s.col = 0;
    [[fallthrough]];
  case 'A':
    s.row = dmax(s.row >= s.top ? s.top : 0, s.row - a);
    break;
  case 'E':
    s.col = 0;
    [[fallthrough]];
  case 'B':
  case 'e':
    s.row = dmin(s.row <= s.bottom ? s.bottom : s.rows - 1, s.row + a);
    break;
  case 'C':
  case 'a':
    s.col = dmin(s.cols - 1, s.col + a);
    break;
  case 'D':
    s.col = dmax(0, s.col - a);
    break;
  case 'G':
  case '`':
    s.col = dmax(0, dmin(s.cols - 1, a - 1));
    break;
  case 'd':
    s.row = dmax(s.origin ? s.top : 0, dmin(s.origin ? s.bottom : s.rows - 1,
                                            a - 1 + (s.origin ? s.top : 0)));
    break;
  case 'H':
  case 'f':
    s.row = dmax(s.origin ? s.top : 0, dmin(s.origin ? s.bottom : s.rows - 1,
                                            a - 1 + (s.origin ? s.top : 0)));
    s.col = dmax(0, dmin(s.cols - 1, b - 1));
    break;
  case '@': {
    insert_cells(s, a);
  } break;
  case 'P': {
    int n = dmin(a, s.cols - s.col);
    for (int c = s.col; c < s.cols - n; ++c)
      s.grid[at(s, s.row, c)] = s.grid[at(s, s.row, c + n)];
    fill(s, s.grid + at(s, s.row, s.cols - n), n, {32, s.fg, s.bg, 0});
    s.row_wrap[s.rowmap[s.row]] = 0;
    s.repair_row = s.row;
  } break;
  case 'X':
    erase_line(s, s.row, s.col, dmin(s.cols, s.col + a));
    break;
  case 'L':
  case 'M':
    if (s.row >= s.top && s.row <= s.bottom)
      shift_rows(s, s.row, s.bottom, a, f == 'M');
    break;
  case 'S':
    shift_rows(s, s.top, s.bottom, a, true);
    break;
  case 'T':
    if (s.csi_n == 0)
      shift_rows(s, s.top, s.bottom, a, false);
    break;
  case 'I':
    tabs(s, a, true);
    break;
  case 'Z':
    tabs(s, a, false);
    break;
  case 'g':
    if (s.params[0] == 0)
      s.tabs[s.col] = 0;
    else if (s.params[0] == 3)
      for (int c = 0; c < MAX_COLS; ++c)
        s.tabs[c] = 0;
    break;
  case 'J': {
    int q = (s.csi_n == 0 && s.params[0] == 0) ? 0 : a;
    if (q == 3) {
      clear_history(s);
      break;
    }
    if (q == 2) {
      graphics_clear(s, s.alt_active);
      for (int r = 0; r < s.rows; ++r)
        erase_line(s, r, 0, s.cols);
    } else if (q == 0) {
      erase_line(s, s.row, s.col, s.cols);
      for (int r = s.row + 1; r < s.rows; ++r)
        erase_line(s, r, 0, s.cols);
    } else if (q == 1) {
      for (int r = 0; r < s.row; ++r)
        erase_line(s, r, 0, s.cols);
      erase_line(s, s.row, 0, s.col + 1);
    }
  } break;
  case 'K': {
    int q = (s.csi_n == 0 && s.params[0] == 0) ? 0 : a;
    if (q == 0)
      erase_line(s, s.row, s.col, s.cols);
    else if (q == 1)
      erase_line(s, s.row, 0, s.col + 1);
    else
      erase_line(s, s.row, 0, s.cols);
  } break;
  case 'm':
    apply_sgr(s);
    break;
  case 'h':
  case 'l':
    if (s.csi_private)
      for (int i = 0; i <= s.csi_n; ++i) {
        int mode = s.params[i], on = f == 'h';
        if (mode == 1000 || mode == 1002 || mode == 1003) {
          s.mouse_mode = on ? mode : 0;
          s.mouse_row = s.mouse_col = -1;
        } else if (mode == 1006)
          s.mouse_sgr = on;
        else if (mode == 1016) {
          s.mouse_pixels = on;
          s.mouse_row = s.mouse_col = -1;
        } else if (mode == 1004)
          s.focus_reporting = on;
        else if (mode == 2026) {
          if (!on && s.synchronized_updates) {
            if (!s.graphics->request.ready) s.graphics->request = {};
            s.graphics->request.ready = 1;
            s.graphics->request.barrier = 2; // Completed presentation boundary.
          }
          s.replies->synchronized_updates = s.synchronized_updates = on;
        } else if (mode == 47 || mode == 1047) {
          if (mode == 1047 && !on && s.alt_active) {
            graphics_clear(s, 1);
            fill(s, s.grid, s.cols * s.rows, {32, s.fg, s.bg, 0});
            for (int r = 0; r < s.rows; ++r)
              s.row_wrap[r] = 0;
          }
          switch_screen(s, on);
          if (!on)
            s.main_saved = 0;
        } else if (mode == 1049)
          alternate_screen(s, on);
        else if (mode == 1048) {
          if (on)
            save_cursor(s);
          else
            restore_cursor(s);
        } else if (mode == 25)
          s.cursor_visible = on;
        else if (mode == 2004)
          s.bracketed_paste = on;
        else if (mode == 1)
          s.app_cursor = on;
        else if (mode == 66)
          s.app_keypad = on;
        else if (mode == 1035)
          s.numlock_override = on;
        else if (mode == 6) {
          s.origin = on;
          s.row = on ? s.top : 0;
          s.col = 0;
          s.wrap_pending = 0;
        } else if (mode == 7) {
          s.autowrap = on;
          s.wrap_pending = 0;
        }
      }
    else
      for (int i = 0; i <= s.csi_n; ++i)
        if (s.params[i] == 4)
          s.insert_mode = f == 'h';
    break;
  case 'r': {
    int end = param(s, 1, s.rows);
    if (a >= 1 && end <= s.rows && a < end) {
      s.top = a - 1;
      s.bottom = end - 1;
      s.row = s.origin ? s.top : 0;
      s.col = 0;
    }
  } break;
  case 's':
    s.saved_row = s.row;
    s.saved_col = s.col;
    break;
  case 'u':
    s.row = s.saved_row;
    s.col = s.saved_col;
    break;
  case 'n':
    if (!s.csi_private && a == 5) {
      const char x[] = "\x1b[0n";
      reply(s, x, 4);
    } else if (a == 6) {
      char x[64];
      int n = 0;
      x[n++] = '\x1b';
      x[n++] = '[';
      n += 0;
      int q = s.row + 1 - (s.origin ? s.top : 0);
      char t[12];
      int z = 0;
      do {
        t[z++] = (char)('0' + q % 10);
        q /= 10;
      } while (q);
      for (int j = z - 1; j >= 0; --j)
        x[n++] = t[j];
      x[n++] = ';';
      q = s.col + 1;
      z = 0;
      do {
        t[z++] = (char)('0' + q % 10);
        q /= 10;
      } while (q);
      for (int j = z - 1; j >= 0; --j)
        x[n++] = t[j];
      x[n++] = 'R';
      reply(s, x, n);
    }
    break;
  case 't':
    if (!s.csi_private && s.params[0] == 16) {
      char out[32] = {27, '[', '6', ';'};
      int n = osc_decimal(out, 4, s.cell_height);
      out[n++] = ';'; n = osc_decimal(out, n, s.cell_width); out[n++] = 't';
      reply(s, out, n);
    }
    break;
  case 'c': {
    const char x[] = "\x1b[?1;2c";
    reply(s, x, 7);
  } break;
  }
}
#include "graphics.cuh"
__device__ void byte(DeviceState &s, unsigned char c) {
  if (s.osc >= 3) {
    auto &g = *s.graphics;
    if (c == 0x18 || c == 0x1a) {
      s.osc = 0; g.invalid = 1; graphic_plan(s); return;
    }
    if (s.osc == 3) {
      s.osc_kind = '_'; s.osc_len = -1;
      s.osc = c == 'G' ? 4 : 1;
      if (c == 'G') graphic_begin(g);
      return;
    }
    if (s.osc == 6) {
      if (c == '\\') { s.osc = 0; graphic_plan(s); }
      else { g.invalid = 1; s.osc = c == 27 ? 6 : 5; }
      return;
    }
    if (c == 27) {
      if (s.osc == 4 && g.phase) graphic_parameter(g);
      s.osc = 6; return;
    }
    if (s.osc == 4) {
      if (c == ';') { graphic_parameter(g); s.osc = 5; }
      else graphic_header(g, c);
    } else if (g.chunk_size < 4096) g.chunk[g.chunk_size++] = c;
    else g.invalid = 1;
    return;
  }
  if (s.osc) {
    if (c == 0x18 || c == 0x1a) { s.osc = 0; return; }
    if (c == 7 || (s.osc == 2 && c == '\\')) {
      if (s.osc_kind == ']' && s.osc_len >= 0) finish_osc(s, c == 7);
      s.osc = 0;
    } else if (c == 27) s.osc = 2;
    else {
      if (s.osc == 2) s.osc_len = -1;
      s.osc = 1;
      if (s.osc_len >= 0) {
        if (s.osc_len < 511) s.osc_text[s.osc_len++] = c;
        else s.osc_len = -1;
      }
    }
    return;
  }
  if (s.utf_need) {
    if ((c & 0xc0) == 0x80) {
      s.utf = (s.utf << 6) | (c & 63);
      if (!--s.utf_need)
        put(s, (s.utf < s.utf_min || s.utf > 0x10ffff ||
                (s.utf >= 0xd800 && s.utf <= 0xdfff))
                   ? 0xfffd
                   : s.utf);
      return;
    }
    s.utf_need = 0;
    put(s, 0xfffd); // Reprocess the non-continuation byte.
  }
  if (c == 27) {
    s.esc = 1;
    s.csi = 0;
    return;
  }
  if (c == 0x18 || c == 0x1a) {
    s.join_blocked = 1;
    s.esc = s.csi = 0;
    return;
  }
  if (c == 127)
    return;
  if (c < 32) {
    s.join_blocked = 1;
    if (c == 0x0e) {
      s.charset = 1;
      return;
    }
    if (c == 0x0f) {
      s.charset = 0;
      return;
    }
    if (c == 10 || c == 11 || c == 12)
      newline(s);
    else if (c == 13) {
      s.col = 0;
      s.wrap_pending = 0;
    } else if (c == 8) {
      s.col = dmax(0, s.col - 1);
      s.wrap_pending = 0;
    } else if (c == 9)
      tabs(s, 1, true);
    return;
  }
  if (s.csi) {
    // Printable CSI syntax is consumed by csi_run. Remaining non-ASCII
    // bytes retain the existing ignore-until-final behavior.
    s.csi_ignore = 1;
    return;
  }
  if (s.esc) {
    int designation = s.esc;
    s.esc = 0;
    if (c != '[')
      s.join_blocked = 1;
    if (designation == 2 || designation == 3) {
      if (c == '0' || c == 'B') {
        if (designation == 2)
          s.g0 = c == '0';
        else
          s.g1 = c == '0';
      }
      return;
    }
    if (c == ']' || c == 'P' || c == '_' || c == '^' || c == 'X') {
      s.osc_kind = c; s.osc_len = 0;
      s.osc = c == '_' ? 3 : 1;
      return;
    }
    if (c == '[') {
      s.csi = 1;
      s.csi_n = s.csi_private = s.csi_ignore = s.csi_intermediate = 0;
      s.csi_prefix = 0;
      s.csi_has_param = 0;
      s.params[0] = 0;
      return;
    }
    if (c == '(' || c == ')') {
      s.esc = c == '(' ? 2 : 3;
      return;
    }
    if (c == '=') {
      s.app_keypad = 1;
      return;
    }
    if (c == '>') {
      s.app_keypad = 0;
      return;
    }
    if (c == '7') {
      save_cursor(s);
    } else if (c == '8') {
      restore_cursor(s);
    } else if (c == 'H') {
      s.tabs[s.col] = 1;
    } else if (c == 'M') {
      s.wrap_pending = 0;
      if (s.row == s.top)
        shift_rows(s, s.top, s.bottom, 1, false);
      else
        s.row = dmax(0, s.row - 1);
    } else if (c == 'D')
      newline(s);
    else if (c == 'E') {
      s.col = 0;
      newline(s);
    } else if (c == 'c') {
      // RIS supersedes earlier effects in this dispatch. Two whole-grid
      // fills avoid exhausting the bounded FillJob queue.
      s.job_count = 0;
      graphics_clear(s, -1);
      clear_history(s);
      if (s.alt_active) {
        dswap(s.grid, s.alt);
        dswap(s.row_wrap, s.alt_row_wrap);
      }
      s.alt_active = 0;
      s.main_saved = 0;
      for (int r = 0; r < s.rows; ++r)
        s.rowmap[r] = s.alt_rowmap[r] = r;
      for (int r = 0; r < s.rows; ++r)
        s.row_wrap[r] = s.alt_row_wrap[r] = 0;
      s.row = s.col = s.top = s.flags = s.wrap_pending = 0;
      s.hyperlink_id = 0;
      s.join_blocked = 0;
      s.bottom = s.rows - 1;
      s.fg = DEFAULT_FG;
      s.bg = DEFAULT_BG;
      s.origin = 0;
      s.insert_mode = 0;
      s.autowrap = 1;
      s.cursor_visible = 1;
      s.cursor_style = 0;
      s.app_cursor = s.bracketed_paste = s.app_keypad = 0;
      s.numlock_override = 1;
      s.mouse_mode = s.mouse_sgr = 0;
      s.mouse_pixels = s.focus_reporting = 0;
      s.replies->synchronized_updates = s.synchronized_updates = 0;
      s.mouse_row = s.mouse_col = -1;
      s.complex_cells = 0;
      s.repair_row = -1;
      s.main_row = s.main_col = s.main_wrap = 0;
      s.main_top = 0;
      s.main_bottom = s.rows - 1;
      s.main_origin = 0;
      s.main_autowrap = 1;
      s.theme = s.base_theme;
      s.main_fg = DEFAULT_FG;
      s.main_bg = DEFAULT_BG;
      s.main_flags = 0;
      s.main_g0 = s.main_g1 = s.main_charset = 0;
      s.saved_row = s.saved_col = s.saved_pending = 0;
      s.saved_origin = 0;
      s.saved_autowrap = 1;
      s.saved_fg = DEFAULT_FG;
      s.saved_bg = DEFAULT_BG;
      s.saved_flags = 0;
      s.saved_g0 = s.saved_g1 = s.saved_charset = 0;
      s.g0 = s.g1 = s.charset = 0;
      s.esc = s.csi = s.osc = s.csi_n = s.csi_private = s.csi_ignore = s.csi_intermediate = 0;
      s.csi_prefix = 0;
      s.csi_has_param = 0;
      keyboard::reset(s.keyboard);
      s.utf = s.utf_min = 0;
      s.utf_need = 0;
      for (int c = 0; c < MAX_COLS; ++c)
        s.tabs[c] = (c > 0 && c % 8 == 0);
      Cell blank{32, DEFAULT_FG, DEFAULT_BG, 0};
      fill(s, s.grid, s.cols * s.rows, blank);
      fill(s, s.alt, s.cols * s.rows, blank);
    }
    return;
  }
  if (c == 127)
    return;
  if (c < 128) {
    put(s, mapped_ascii(s, c), active_graphics(s) && c >= 0x5f && c <= 0x7e);
    return;
  }
  if (c >= 0xc2 && c <= 0xdf) {
    s.utf = c & 31;
    s.utf_need = 1;
    s.utf_min = 0x80;
  } else if (c >= 0xe0 && c <= 0xef) {
    s.utf = c & 15;
    s.utf_need = 2;
    s.utf_min = 0x800;
  } else if (c >= 0xf0 && c <= 0xf4) {
    s.utf = c & 7;
    s.utf_need = 3;
    s.utf_min = 0x10000;
  } else
    put(s, 0xfffd);
}
// Keep the current CSI value in a register while consuming printable syntax.
// C0 controls and ESC return to byte(), preserving interruption semantics.
__device__ size_t csi_run(DeviceState &s, const unsigned char *input, size_t n,
                          size_t offset) {
  int index = s.csi_n, value = s.params[index];
  int ignore = s.csi_ignore, priv = s.csi_private;
  while (offset < n) {
    unsigned char c = input[offset];
    if (c < 32 || c >= 127)
      break;
    ++offset;
    if (c >= '0' && c <= '9') {
      s.csi_has_param = 1;
      if (s.csi_intermediate) ignore = 1;
      if (!ignore)
        value = dmin(1000000, value * 10 + c - '0');
    } else if (c == ';') {
      s.csi_has_param = 1;
      if (s.csi_intermediate) ignore = 1;
      if (index < 15) {
        s.params[index++] = value;
        value = 0;
      } else
        ignore = 1;
    } else if ((c == '?' || c == '>' || c == '<' || c == '=') &&
               index == 0 && value == 0 && !s.csi_intermediate) {
      if (c == '?')
        priv = 1;
      s.csi_prefix = c;
    } else if (c == ' ' && !s.csi_intermediate) {
      s.csi_intermediate = c;
    } else if (c >= 0x40 && c <= 0x7e) {
      s.params[index] = value;
      s.csi_n = index;
      s.csi_private = priv;
      s.csi_ignore = ignore;
      if (!ignore)
        csi(s, c);
      s.csi = 0;
      return offset;
    } else
      ignore = 1;
  }
  s.params[index] = value;
  s.csi_n = index;
  s.csi_private = priv;
  s.csi_ignore = ignore;
  return offset;
}
#include "styled.cuh"

__global__ void feed_kernel(DeviceState *state, const unsigned char *input,
                            size_t n, const int *rejected = nullptr,
                            const int *styled = nullptr,
                            int *resume = nullptr) {
  size_t skip = rejected && *rejected >= 256 ? (size_t)*rejected : 0;
  if (styled && *styled >= 256)
    skip = dmax((int)skip, *styled);
  if (skip >= n && !state->pending_valid) {
    if (threadIdx.x == 0) {
      auto &r = state->graphics->request;
      r.consumed = n; r.alternate = state->alt_active; r.history_rows = state->history_count;
      r.pool_wait = r.pool_gc = 0;
    }
    return;
  }
  input += skip;
  n -= skip;
  // A warp cooperates on printable runs. The leader preserves VT ordering for
  // controls and UTF-8; frequently changed parser state stays in shared memory.
  __shared__ DeviceState s;
  __shared__ FillJob jobs[MAX_ROWS + 4];
  __shared__ size_t offset;
  int lane = threadIdx.x;
  if (lane == 0) {
    s = *state;
    s.jobs = jobs;
    s.job_count = 0;
    offset = 0;
    s.pool_wait = 0;
  }
  __syncwarp();
  // A scalar that completed on the previous fragment is committed before
  // parsing any new byte. Flush its queued edits while the job list is empty.
  if (lane == 0 && s.pending_valid) {
    uint32_t pending = s.pending_cp;
    s.pending_valid = 0;
    s.job_count = 0;
    s.repair_row = -1;
    put(s, pending);
    for (int j = 0; j < s.job_count; ++j) {
      FillJob op = jobs[j];
      for (int i = 0; i < op.count; ++i)
        op.first[i] = op.source ? op.source[i] : op.value;
    }
    if (s.repair_row >= 0) repair_row(s, s.repair_row);
    s.job_count = 0;
  }
  __syncwarp();
  while (offset < n && !s.graphics->request.ready && !s.pool_wait) {
    // Opaque graphics payloads are copied cooperatively instead of taking the
    // scalar VT interpreter through every base64 character.
    if (s.osc == 5) {
      auto &g = *s.graphics;
      size_t index = offset + lane;
      unsigned char c = index < n ? input[index] : 0;
      bool payload = index < n && c != 27 && c != 0x18 && c != 0x1a;
      unsigned mask = __ballot_sync(0xffffffffu, payload);
      int count = mask == 0xffffffffu ? 32 : __ffs(~mask) - 1;
      if (count) {
        if (lane < count && g.chunk_size + lane < 4096) g.chunk[g.chunk_size + lane] = c;
        __syncwarp();
        if (!lane) {
          if (g.chunk_size + count > 4096) g.invalid = 1;
          g.chunk_size = dmin(4096, g.chunk_size + count);
          offset += count;
        }
        __syncwarp();
        continue;
      }
    }
    if (resume && offset > 0 && !s.esc && !s.csi && !s.osc && !s.utf_need)
      break;
    if (!s.esc && !s.csi && !s.osc && !s.utf_need && !s.wrap_pending &&
        (!s.insert_mode || !s.complex_cells)) {
      size_t index = offset + lane;
      unsigned char c = index < n ? input[index] : 0;
      bool printable = index < n && lane < s.cols - s.col && c >= 32 && c < 127;
      unsigned mask = __ballot_sync(0xffffffffu, printable);
      int count = mask == 0xffffffffu ? 32 : __ffs(~mask) - 1;
      if (count) {
        if (s.insert_mode) {
          // Descending blocks preserve overlapping source cells. All lanes
          // load before any store, then finish stores before the next block.
          for (int end = s.cols - 1; end >= s.col + count; end -= 32) {
            int dest = end - lane;
            Cell moved{};
            if (dest >= s.col + count)
              moved = s.grid[at(s, s.row, dest - count)];
            __syncwarp();
            if (dest >= s.col + count)
              s.grid[at(s, s.row, dest)] = moved;
            __syncwarp();
          }
        }
        // Only the two edges can leave half of an old wide glyph behind.
        // Finish these reads before any lane overwrites the run.
        if (lane == 0 && s.complex_cells) {
          if (s.col > 0 && (s.grid[at(s, s.row, s.col)].flags & TAIL))
            clear_cell(s.grid[at(s, s.row, s.col - 1)], s.fg, s.bg);
          int end = s.col + count;
          if (end < s.cols && (s.grid[at(s, s.row, end - 1)].flags & WIDE))
            clear_cell(s.grid[at(s, s.row, end)], s.fg, s.bg);
        }
        __syncwarp();
        if (lane < count)
          s.grid[at(s, s.row, s.col + lane)] = {mapped_ascii(s, c), s.fg, s.bg,
                                                s.flags | (s.hyperlink_id << HYPERLINK_SHIFT), {}, c == 32};
        __syncwarp();
        if (lane == 0) {
          if (s.insert_mode || s.col + count == s.cols)
            s.row_wrap[s.rowmap[s.row]] = 0;
          offset += count;
          s.col += count;
          if (s.col == s.cols) {
            s.col--;
            s.wrap_pending = s.autowrap;
          }
          s.join_blocked = 0;
        }
        __syncwarp();
        continue;
      }
    }
    __syncwarp(); // Finish shared predicate reads before the leader mutates
                  // state.
    if (lane == 0) {
      s.job_count = 0;
      s.repair_row = -1;
      do {
        size_t next = s.csi ? csi_run(s, input, n, offset) : offset;
        if (next == offset)
          byte(s, input[offset++]);
        else
          offset = next;
      } while (offset < n && s.job_count == 0 && !s.graphics->request.ready &&
               (s.esc || s.csi || (s.osc && s.osc != 5) || s.utf_need));
    }
    __syncwarp();
    // Effects are applied in stream order: a wrap can clear a row and then
    // write its first glyph within the same byte dispatch.
    for (int job = 0; job < s.job_count; ++job) {
      FillJob op = jobs[job];
      for (int i = lane; i < op.count; i += 32)
        op.first[i] = op.source ? op.source[i] : op.value;
      __syncwarp();
    }
    if (lane == 0 && s.repair_row >= 0)
      repair_row(s, s.repair_row);
    __syncwarp();
    auto &g = *s.graphics;
    // Valid continuation chunks use already-reserved device storage. Yield to
    // the host only for capacity growth or the final decode/commit operation.
    if (g.request.ready && !g.request.reset && !g.request.barrier && g.active &&
        !g.invalid && graphic_value(g.command, 'm') &&
        g.request.input_bytes <= g.input_capacity) {
      bool ok = graphic_decode(g, g.input);
      if (!lane) {
        if (ok) g.request.ready = 0;
        else g.invalid = 1;
      }
      __syncwarp();
    }
  }
  if (lane == 0) {
    s.jobs = nullptr;
    s.job_count = 0;
    s.graphics->request.consumed = skip + offset;
    s.graphics->request.pool_wait = s.pool_wait;
    s.graphics->request.pool_gc = s.mark_gc;
    s.mark_gc = 0;
    *state = s;
    s.graphics->request.alternate = s.alt_active;
    s.graphics->request.history_rows = s.history_count;
    if (resume)
      *resume = (int)offset;
  }
}
// CRLF-delimited ASCII can be laid out independently in parallel. Validation
// happens on the GPU; controls, Unicode, and partial parser state use the warp
// interpreter. Prefix scans give each glyph a unique logical row and column.
struct PlainMeta {
  int start_row, start_col, scroll, history_base;
};
__global__ void plain_classify(const DeviceState *s, const unsigned char *b,
                               int n, int *starts, int *rejected, int *styled,
                               int *styled_limit) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n)
    return;
  if (i == 0) {
    *styled = 0;
    *styled_limit = (!s->hyperlink_id && !s->esc && !s->csi && !s->osc && !s->utf_need &&
                     s->autowrap && !s->insert_mode && s->top == 0 &&
                     s->bottom == s->rows - 1)
                        ? n
                        : 0;
  }
  if (i == 0) {
    if (s->hyperlink_id || s->esc || s->csi || s->osc || s->utf_need ||
        (n > 1 && b[0] == 27 && (b[1] == '(' || b[1] == ')')) ||
        (b[0] < 32 && b[0] != 27 &&
         !(b[0] == '\n' && s->col == 0 && !s->wrap_pending) &&
         !(b[0] == '\r' && n > 1 && b[1] == '\n')))
      atomicMin(rejected, -1);
    else if (!s->autowrap || s->insert_mode || s->top != 0 ||
             s->bottom != s->rows - 1)
      atomicMin(rejected, 0);
  }
  unsigned char c = b[i];
  bool valid = (c >= 32 && c < 127) ||
               (c == '\r' && (i == n - 1 || b[i + 1] == '\n')) ||
               (c == '\n' && ((i > 0 && b[i - 1] == '\r') ||
                              (i == 0 && s->col == 0 && !s->wrap_pending)));
  if (!valid)
    atomicMin(rejected, i);
  starts[i] = (i > 0 && b[i - 1] == '\n') ? i : 0;
}
__global__ void plain_scan_small(const DeviceState *s, const unsigned char *b,
                                 int n, const int *rejected, int *starts,
                                 int *advances) {
  using BlockScan = cub::BlockScan<int, 256>;
  __shared__ typename BlockScan::TempStorage storage;
  int input[16], output[16];
  int rejected_value = *rejected;
  int base = int(threadIdx.x) * 16;
  for (int j = 0; j < 16; ++j) {
    int index = base + j;
    input[j] = index < n ? starts[index] : 0;
  }
  BlockScan(storage).InclusiveScan(input, output, cub::Max());
  for (int j = 0; j < 16; ++j) {
    int index = base + j;
    if (index < n)
      starts[index] = output[j];
  }
  __syncthreads();
  for (int j = 0; j < 16; ++j) {
    int index = base + j;
    input[j] = 0;
    if (index < n && rejected_value >= 256 && index < rejected_value &&
        b[index] == '\n') {
      int start = output[j];
      int chars = index - start -
                  ((index > start && b[index - 1] == '\r') ? 1 : 0);
      int col = start == 0 ? (s->wrap_pending ? s->cols : s->col) : 0;
      input[j] = chars > 0 ? (col + chars - 1) / s->cols + 1 : 1;
    }
  }
  BlockScan(storage).InclusiveSum(input, output);
  for (int j = 0; j < 16; ++j) {
    int index = base + j;
    if (index < n)
      advances[index] = output[j];
  }
}
__global__ void plain_advances(const DeviceState *s, const unsigned char *b,
                               int n, const int *starts, int *advances,
                               const int *rejected) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n)
    return;
  int count = 0;
  if (*rejected >= 256 && i < *rejected && b[i] == '\n') {
    int start = starts[i];
    int chars = i - start - ((i > start && b[i - 1] == '\r') ? 1 : 0);
    int col = start == 0 ? (s->wrap_pending ? s->cols : s->col) : 0;
    count = chars > 0 ? (col + chars - 1) / s->cols + 1 : 1;
  }
  advances[i] = count;
}
__global__ void plain_commit(DeviceState *s, const unsigned char *b, int n,
                             const int *starts, const int *advances,
                             const int *rejected, PlainMeta *meta) {
  n = *rejected;
  if (n < 256)
    return;
  meta->start_row = s->row;
  meta->start_col = s->wrap_pending ? s->cols : s->col;
  int start = starts[n - 1], total = advances[n - 1];
  if (b[n - 1] == '\n') {
    s->col = 0;
    s->wrap_pending = 0;
  } else {
    bool cr = b[n - 1] == '\r';
    int chars = n - start - (cr ? 1 : 0);
    int col = start == 0 ? meta->start_col : 0;
    if (chars > 0)
      total += (col + chars - 1) / s->cols;
    if (cr) {
      s->col = 0;
      s->wrap_pending = 0;
    } else {
      int end = (col + chars - 1) % s->cols + 1;
      s->col = dmin(end, s->cols - 1);
      s->wrap_pending = end == s->cols;
    }
  }
  int finalrow = s->row + total;
  int scroll = dmax(0, finalrow - s->rows + 1);
  meta->scroll = scroll;
  graphics_scroll(*s, 0, s->rows - 1, scroll);
  meta->history_base = reserve_history(*s, scroll);
  rotate_rows(s->rowmap, s->rows, scroll);
  s->row = dmin(s->rows - 1, finalrow);
  s->join_blocked = 0;
}
__global__ void plain_clear(DeviceState *s, const int *rejected,
                            const PlainMeta *meta) {
  if (*rejected < 256)
    return;
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= s->rows * s->cols)
    return;
  int r = i / s->cols;
  if (r >= s->rows - dmin(s->rows, meta->scroll))
    s->grid[at(*s, r, i % s->cols)] = {32, s->fg, s->bg, 0};
  if (r >= s->rows - dmin(s->rows, meta->scroll) && i % s->cols == 0)
    s->row_wrap[s->rowmap[r]] = 0;
  if (s->complex_cells)
    s->repair_flags[i] = s->grid[at(*s, r, i % s->cols)].flags;
}
__global__ void plain_scatter(DeviceState *s, const unsigned char *b, int n,
                              const int *starts, const int *advances,
                              const int *rejected, const PlainMeta *meta) {
  if (*rejected < 256)
    return;
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= *rejected || b[i] < 32)
    return;
  int start = starts[i];
  int position = i - start + (start == 0 ? meta->start_col : 0);
  int logical = meta->start_row + advances[i] + position / s->cols;
  int row = logical - meta->scroll;
  Cell *target = bulk_row(*s, logical, meta->scroll, meta->history_base);
  if (target) {
    int col = position % s->cols;
    target[col] = {mapped_ascii(*s, b[i]), s->fg, s->bg, s->flags, {}, b[i] == 32};
    if (s->complex_cells && row >= 0)
      s->repair_flags[row * s->cols + col] = 0;
  }
}
__global__ void plain_wrap_metadata(DeviceState *s, const unsigned char *b,
                                    int n, const int *starts,
                                    const int *advances, const int *rejected,
                                    const PlainMeta *meta) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  n = *rejected;
  if (n < 256 || i >= n || starts[i] != i)
    return;
  int end = i;
  while (end < n && b[end] != '\n') ++end;
  int chars = end - i;
  if (chars && b[i + chars - 1] == '\r') --chars;
  int row = meta->start_row + (i ? advances[i - 1] : 0),
      col = i ? 0 : meta->start_col;
  if (!chars && end < n && b[end] == '\n') {
    int *wrap = bulk_wrap(*s, row, meta->scroll, meta->history_base);
    if (wrap) *wrap = 0;
    return;
  }
  if (chars <= 0) return;
  int lastrow = row + (col + chars - 1) / s->cols;
  for (int r = row; r < lastrow; ++r) {
    int *wrap = bulk_wrap(*s, r, meta->scroll, meta->history_base);
    if (wrap) *wrap = s->cols;
  }
  int final_col = (col + chars) % s->cols;
  if (final_col == 0 || (end < n && b[end] == '\n')) {
    int *wrap = bulk_wrap(*s, lastrow, meta->scroll, meta->history_base);
    if (wrap) *wrap = 0;
  }
}
// Snapshot flags are immutable during repair: adjacent lanes may clear cells
// independently without racing on the wide-pair predicates.
__global__ void plain_repair(DeviceState *s, const int *rejected) {
  if (*rejected < 256 || !s->complex_cells)
    return;
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= s->rows * s->cols)
    return;
  int col = i % s->cols;
  uint32_t f = s->repair_flags[i];
  if (((f & WIDE) &&
       (col == s->cols - 1 || !(s->repair_flags[i + 1] & TAIL))) ||
      ((f & TAIL) && (col == 0 || !(s->repair_flags[i - 1] & WIDE))))
    s->grid[at(*s, i / s->cols, col)] = {32, s->fg, s->bg, 0};
}
__global__ void repair_history(DeviceState *s, const int *accepted,
                               const PlainMeta *m) {
  if (*accepted < 256 || !s->complex_cells || m->history_base < 0)
    return;
  int first = dmax(0, m->scroll - s->history_capacity);
  for (int logical = first + blockIdx.x * blockDim.x + threadIdx.x;
       logical < m->scroll; logical += blockDim.x * gridDim.x) {
    Cell *row =
        s->history +
        ((m->history_base + logical) % s->history_capacity) * s->history_cols;
    // One thread owns a complete row, so neighbor repair has no data race.
    for (int c = 0; c < s->cols; ++c) {
      uint32_t f = row[c].flags;
      if (((f & WIDE) && (c + 1 == s->cols || !(row[c + 1].flags & TAIL))) ||
          ((f & TAIL) && (!c || !(row[c - 1].flags & WIDE))))
        row[c] = {32, s->fg, s->bg, 0};
    }
  }
}
__device__ uint32_t glyph_slot(const DeviceState *s, uint32_t cp) {
  if (cp < 65536)
    return cp;
  if (cp >= 0x110000)
    return 0xffffffffu;
  uint32_t page = s->font_pages[cp >> 8];
  return page == 0xffffffffu ? page : s->font_map[page * 256 + (cp & 255)];
}
__device__ uint16_t glyph(const DeviceState *s, uint32_t slot, int y) {
  return s->font_rows[slot * 16 + y];
}
__device__ unsigned face_alpha(const DeviceState *s, uint32_t cp, int x, int y, int style) {
  if (!s->face_pixels[style] || cp >= 0x110000) return 256;
  uint32_t page = s->face_pages[style][cp >> 8];
  if (page == 0xffffffffu) return 256;
  uint32_t slot = s->face_map[style][page * 256 + (cp & 255)];
  if (slot == 0xffffffffu) return 256;
  return s->face_pixels[style][(size_t(slot) * s->face_height + y) * s->face_width * 2 + x];
}
__device__ void selection_columns(const DeviceState &s, int row, int &first, int &last) {
  first = s.selection_rectangle || row == s.selection_start_row ? s.selection_start_col : 0;
  last = s.selection_rectangle || row == s.selection_end_row ? s.selection_end_col : s.cols - 1;
  if (s.selection_rectangle) {
    if (first > 0 && (viewed_cell(s, row, first).flags & TAIL)) --first;
    if (last + 1 < s.cols && (viewed_cell(s, row, last).flags & WIDE)) ++last;
  }
}
__global__ void render_kernel(const DeviceState *s, uint32_t *out, int w,
                              int h, const Cell *prompt, bool preedit) {
  int x = blockIdx.x * blockDim.x + threadIdx.x,
      y = blockIdx.y * blockDim.y + threadIdx.y;
  if (x >= w || y >= h)
    return;
  int output_x = x, output_y = y;
  x -= s->padding_x; y -= s->padding_y;
  int c = x / s->cell_width, r = y / s->cell_height;
  int prompt_col = preedit ? c - dmin(s->col, s->cols - 1) : c;
  bool overlay = prompt && x >= 0 && y >= 0 && c < s->cols &&
    (preedit ? (!s->view_offset && r == s->row && prompt_col >= 0 &&
                prompt[prompt_col].cp != 0) : r == s->rows - 1);
  int glyph_y = (y % s->cell_height) * 16 / s->cell_height;
  uint32_t color = resolved(*s, DEFAULT_BG);
  unsigned opacity = s->background_alpha;
  if (opacity != 255) {
    uint32_t premultiplied = 0;
    for (int shift = 0; shift <= 16; shift += 8)
      premultiplied |= ((((color >> shift) & 255) * opacity + 127) / 255) << shift;
    color = premultiplied;
  }
  if (x >= 0 && y >= 0 && c < s->cols && r < s->rows) {
    Cell z = overlay ? prompt[prompt_col] : viewed_cell(*s, r, c);
    int gx = (x % s->cell_width) * 8 / s->cell_width;
    int face_x = (x % s->cell_width) * s->face_width / s->cell_width;
    if ((z.flags & TAIL) && c > 0) {
      z = overlay ? prompt[prompt_col - 1] : viewed_cell(*s, r, c - 1);
      gx += 8;
      face_x += s->face_width;
    }
    int span = (z.flags & WIDE) ? 16 : 8;
    if (overlay && preedit) z.flags |= UNDERLINE;
    uint32_t fg = resolved(*s, z.fg), bg = resolved(*s, z.bg);
    if (z.flags & INVERSE)
      dswap(fg, bg);
    int selection_first = 0, selection_last = -1;
    bool selected = !overlay && s->selection_active &&
                    r >= s->selection_start_row && r <= s->selection_end_row;
    if (selected) {
      selection_columns(*s, r, selection_first, selection_last);
      selected = c >= selection_first && c <= selection_last;
    }
    if (selected) {
      dswap(fg, bg);
      if (s->theme.customized & 4) fg = s->theme.colors[260];
      if (s->theme.customized & 8) bg = s->theme.colors[261];
      if (s->copy_flash) { fg = 0x000000; bg = 0xffffaf; }
    }
    float cx = (s->cursor_x < 0 ? float(s->col) : s->cursor_x) * s->cell_width;
    float cy = (s->cursor_y < 0 ? float(s->row) : s->cursor_y) * s->cell_height;
    float cursor_local_x = x - cx, cursor_local_y = y - cy;
    bool cursor = !overlay && !s->view_offset && s->cursor_visible &&
                  cursor_local_x >= 0 && cursor_local_x < s->cell_width &&
                  cursor_local_y >= 0 && cursor_local_y < s->cell_height;
    int style = s->cursor_style ? s->cursor_style : s->default_cursor_style;
    bool blink_on = !(style & 1) || s->cursor_phase;
    int local_x = x % s->cell_width, local_y = y % s->cell_height;
    bool cursor_pixel = cursor && (s->window_focused ? blink_on : true);
    if (!s->window_focused)
      cursor_pixel &= cursor_local_x < 1 || cursor_local_x >= s->cell_width - 1 ||
                      cursor_local_y < 1 || cursor_local_y >= s->cell_height - 1;
    else if (style == 3 || style == 4) cursor_pixel &= cursor_local_y >= s->cell_height - 2;
    else if (style == 5 || style == 6) cursor_pixel &= cursor_local_x < 2;
    cursor = cursor_pixel;
    if (cursor) {
      dswap(fg, bg);
      if (s->theme.customized & 1) bg = s->theme.colors[258];
      if (s->theme.customized & 2) fg = s->theme.colors[259];
    }
    if ((z.flags & DIM) && !selected && !cursor)
      fg = (fg & 0xfefefe) >> 1;
    uint32_t slot = glyph_slot(s, z.cp);
    if (slot == 0xffffffffu || !s->font_widths[slot])
      slot = 0xfffd;
    int bitmap_width = s->font_widths[slot];
    int bit = gx * bitmap_width / span;
    uint16_t bits = glyph(s, slot, glyph_y);
    bool ink = bits & (0x8000u >> bit);
    if ((z.flags & BOLD) && bit > 0)
      ink |= (bits & (0x8000u >> (bit - 1))) != 0;
    uint32_t mark_ref = mark_pool::head(z);
    for (int m = 0;;) {
      uint32_t mark;
      if (!mark_pool::overlay_mark(z, s->marks, m, mark_ref, mark)) break;
      if (grapheme_default_ignorable(mark)) continue;
      uint32_t mark_slot = glyph_slot(s, mark);
      if (mark_slot == 0xffffffffu || !s->font_widths[mark_slot])
        continue;
      int mx = gx - (span + s->mark_offsets[mark]);
      if (mx >= 0 && mx < s->font_widths[mark_slot])
        ink |= (glyph(s, mark_slot, glyph_y) & (0x8000u >> mx)) != 0;
    }
    if ((z.flags & UNDERLINE) && glyph_y == 14)
      ink = true;
    int font_style = (z.flags & BOLD ? 1 : 0) | (z.flags & ITALIC ? 2 : 0);
    const int face_y = (y % s->cell_height) * s->face_height / s->cell_height;
    unsigned alpha = face_alpha(s, z.cp, face_x, face_y, font_style);
    if (alpha == 256) alpha = ink ? 255 : 0;
    else {
      if ((z.flags & BOLD) && s->face_pixels[1] == s->face_pixels[0] && face_x > 0)
        alpha = dmax(alpha, face_alpha(s, z.cp, face_x - 1, face_y, font_style));
      if ((z.flags & UNDERLINE) && glyph_y == 14) alpha = 255;
      // Combining marks retain the existing Unifont placement/coverage.
      uint32_t face_mark_ref = mark_pool::head(z);
      for (int m = 0;;) {
        uint32_t mark;
        if (!mark_pool::overlay_mark(z, s->marks, m, face_mark_ref, mark)) break;
        if (grapheme_default_ignorable(mark)) continue;
        uint32_t slot = glyph_slot(s, mark);
        int mx = gx - (span + s->mark_offsets[mark]);
        if (slot != 0xffffffffu && mx >= 0 && mx < s->font_widths[slot] &&
            (glyph(s, slot, glyph_y) & (0x8000u >> mx))) alpha = 255;
      }
    }
    if ((z.flags & STRIKE) && local_y == s->cell_height / 2) alpha = 255;
    if (z.flags & HIDDEN) alpha = 0;
    unsigned base_alpha = z.bg == DEFAULT_BG && !(z.flags & INVERSE) && !selected && !cursor
      ? s->background_alpha : 255;
    opacity = alpha + (base_alpha * (255 - alpha) + 127) / 255;
    if (alpha == 255) color = fg;
    else if (!alpha && base_alpha == 255) color = bg;
    else {
      color = 0;
      for (int shift = 0; shift <= 16; shift += 8)
        color |= ((((fg >> shift) & 255) * alpha * 255 +
          ((bg >> shift) & 255) * base_alpha * (255 - alpha) + 32512) / 65025) << shift;
    }
  }
  if (!overlay && x >= 0 && y >= 0 && c < s->cols && r < s->rows)
    color = graphic_pixel(*s, x, y, color, opacity);
  out[output_y * w + output_x] =
      (opacity << 24) | ((color & 255) << 16) | (color & 0xff00) | (color >> 16);
}
__global__ void clear_selection_kernel(DeviceState *s) {
  s->selection_active = 0;
  s->copy_flash = 0;
}
__global__ void set_selection_output_kernel(DeviceState *s,
                                            unsigned char *output) {
  s->selection_output = output;
}
// Word selection groups letters/digits/underscore and non-ASCII glyphs;
// ASCII punctuation selects runs of the same character. Combining marks remain
// attached to their base cell. This is not Unicode word segmentation.
__device__ uint32_t selection_class(DeviceState &s, int row, int col) {
  Cell z = viewed_cell(s, row, col);
  if ((z.flags & TAIL) && col > 0) z = viewed_cell(s, row, col - 1);
  uint32_t cp = z.cp;
  if (cp == 0 || cp == ' ' || cp == '\t') return 0;
  if (cp >= 128 || (cp >= 'a' && cp <= 'z') ||
      (cp >= 'A' && cp <= 'Z') || (cp >= '0' && cp <= '9') || cp == '_')
    return 1;
  return cp;
}
__device__ uint32_t selection_token(DeviceState &s, int row, int col, SelectionMode mode) {
  if (mode != SelectionMode::Link) return selection_class(s, row, col);
  Cell cell = viewed_cell(s, row, col);
  if ((cell.flags & TAIL) && col > 0) cell = viewed_cell(s, row, col - 1);
  uint32_t cp = cell.cp;
  bool space = cp == 0x85 || cp == 0xa0 || cp == 0x1680 ||
    (cp >= 0x2000 && cp <= 0x200a) || cp == 0x2028 || cp == 0x2029 ||
    cp == 0x202f || cp == 0x205f || cp == 0x3000;
  return !space && cp > 32 && cp != 127 && cp != '"' && cp != '\'' && cp != '<' && cp != '>';
}
__global__ void select_kernel(DeviceState *s, int sr, int sc, int er, int ec,
                              SelectionMode mode, bool history) {
  s->copy_flash = 0;
  int min_row = s->alt_active ? 0 : s->view_offset - s->history_count;
  int max_row = s->alt_active ? s->rows - 1 : s->view_offset + s->rows - 1;
  sr = dmax(history ? min_row : 0, dmin(sr, history ? max_row : s->rows - 1));
  er = dmax(history ? min_row : 0, dmin(er, history ? max_row : s->rows - 1));
  sc = dmax(0, dmin(sc, s->cols - 1));
  ec = dmax(0, dmin(ec, s->cols - 1));
  if (sr > er || (sr == er && sc > ec)) {
    dswap(sr, er);
    dswap(sc, ec);
  }
  if (mode == SelectionMode::Rectangle && sc > ec) dswap(sc, ec);
  if (mode == SelectionMode::Line) {
    while (sr > min_row && viewed_wrap(*s, sr - 1) > 0) --sr;
    while (er < max_row && viewed_wrap(*s, er) > 0) ++er;
    sc = 0;
    ec = s->cols - 1;
  } else if (mode == SelectionMode::Word || mode == SelectionMode::Link) {
    uint32_t first = selection_token(*s, sr, sc, mode);
    uint32_t last = selection_token(*s, er, ec, mode);
    while (sc > 0 && selection_token(*s, sr, sc - 1, mode) == first) --sc;
    // A word can continue across a soft-wrapped row.  Positive wrap lengths
    // are the only row joins; retained-history boundaries and hard breaks stop it.
    while (sc == 0 && sr > min_row && viewed_wrap(*s, sr - 1) > 0) {
      int candidate_row = sr - 1;
      int limit = viewed_wrap(*s, candidate_row);
      int candidate_col = limit > 0 ? limit - 1 : s->cols - 1;
      if (selection_token(*s, candidate_row, candidate_col, mode) != first) break;
      sr = candidate_row;
      sc = candidate_col;
      while (sc > 0 && selection_token(*s, sr, sc - 1, mode) == first) --sc;
    }
    int end_limit = viewed_wrap(*s, er);
    if (end_limit <= 0) end_limit = s->cols;
    while (ec + 1 < end_limit && selection_token(*s, er, ec + 1, mode) == last) ++ec;
    while (er < max_row) {
      int limit = viewed_wrap(*s, er);
      if (limit <= 0 || ec + 1 < limit) break;
      int candidate_row = er + 1;
      if (selection_token(*s, candidate_row, 0, mode) != last) break;
      er = candidate_row;
      ec = 0;
      end_limit = viewed_wrap(*s, er);
      if (end_limit <= 0) end_limit = s->cols;
      while (ec + 1 < end_limit && selection_token(*s, er, ec + 1, mode) == last) ++ec;
    }
  }
  Cell a = viewed_cell(*s, sr, sc), b = viewed_cell(*s, er, ec);
  if (mode != SelectionMode::Rectangle && (a.flags & TAIL) && sc > 0)
    --sc;
  if (mode != SelectionMode::Rectangle && (b.flags & WIDE) && ec + 1 < s->cols)
    ++ec;
  s->selection_rectangle = mode == SelectionMode::Rectangle;
  s->selection_start_row = sr;
  s->selection_start_col = sc;
  s->selection_end_row = er;
  s->selection_end_col = ec;
  s->selection_active = 1;
}

__device__ size_t append_utf8(unsigned char *out, size_t pos, uint32_t cp) {
  if (!out) return pos + (cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4);
  if (cp < 0x80) {
    out[pos++] = (unsigned char)cp;
  } else if (cp < 0x800) {
    out[pos++] = (unsigned char)(0xc0 | (cp >> 6));
    out[pos++] = (unsigned char)(0x80 | (cp & 63));
  } else if (cp < 0x10000) {
    out[pos++] = (unsigned char)(0xe0 | (cp >> 12));
    out[pos++] = (unsigned char)(0x80 | ((cp >> 6) & 63));
    out[pos++] = (unsigned char)(0x80 | (cp & 63));
  } else {
    out[pos++] = (unsigned char)(0xf0 | (cp >> 18));
    out[pos++] = (unsigned char)(0x80 | ((cp >> 12) & 63));
    out[pos++] = (unsigned char)(0x80 | ((cp >> 6) & 63));
    out[pos++] = (unsigned char)(0x80 | (cp & 63));
  }
  return pos;
}
__global__ void selected_text_kernel(DeviceState *s, int batch_start, int batch_end, bool count_only) {
  if (threadIdx.x || blockIdx.x)
    return;
  size_t pos = 0;
  unsigned char *out = count_only ? nullptr : s->selection_output;
  if (!s->selection_active) {
    s->selection_output_len = 0;
    return;
  }
  int start = dmax(s->selection_start_row, batch_start);
  int end = dmin(s->selection_end_row, batch_end);
  for (int r = start; r <= end; ++r) {
    int first, last; selection_columns(*s, r, first, last);
    int wrap = viewed_wrap(*s, r);
    bool joined = !s->selection_rectangle && wrap > 0 && r != s->selection_end_row;
    if (wrap > 0)
      last = dmin(last, wrap - 1);
    // Preserve actual edge spaces inside a logical line, but omit synthetic
    // wide-wrap/resize padding using the recorded continuation length.
    while (!joined && last >= first) {
      Cell z = viewed_cell(*s, r, last);
      if (z.flags & TAIL) {
        --last;
        continue;
      }
      bool marked = mark_pool::mark_count(z, s->marks) != 0;
      if (z.cp != 32 || marked)
        break;
      --last;
    }
    for (int c = first; c <= last; ++c) {
      Cell z = viewed_cell(*s, r, c);
      if (z.flags & TAIL)
        continue;
      pos = append_utf8(out, pos, z.cp);
      for (int i = 0; i < 3 && z.combining[i]; ++i)
        pos = append_utf8(out, pos, z.combining[i]);
      size_t suffix_start = pos;
      uint32_t ref = mark_pool::head(z);
      while (ref) {
        if (*s->marks.used > s->marks.capacity || ref > *s->marks.used ||
            s->marks.nodes[ref - 1].parent >= ref) {
          *s->marks.status = mark_pool::MALFORMED;
          return;
        }
        auto node = s->marks.nodes[ref - 1];
        if (out) {
          unsigned char encoded[4];
          int bytes = int(append_utf8(encoded, 0, node.cp));
          while (bytes) out[pos++] = encoded[--bytes];
        } else pos = append_utf8(nullptr, pos, node.cp);
        ref = node.parent;
      }
      // Reversing both each scalar's bytes and the suffix restores forward UTF-8.
      if (out) for (size_t i = suffix_start, j = pos; i < j && i < --j; ++i)
        dswap(out[i], out[j]);
    }
    if (r != s->selection_end_row && !joined) {
      if (out) out[pos] = '\n';
      ++pos;
    }
  }
  s->selection_output_len = pos;
}
__global__ void init_grid(Cell *a, Cell *b, int n) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n)
    a[i] = b[i] = {32, DEFAULT_FG, DEFAULT_BG, 0};
}
#include "reflow.cuh"
#include "search_kernels.cuh"
__global__ void grow_history_kernel(const DeviceState *s, Cell *out) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= s->history_count * s->history_cols)
    return;
  int row = i / s->history_cols, col = i % s->history_cols;
  int slot = (s->history_head - s->history_count + row + s->history_capacity) %
             s->history_capacity;
  out[i] = s->history[slot * s->history_cols + col];
}
__global__ void commit_history_growth(DeviceState *s, Cell *out, int capacity) {
  // This kernel launches one thread. Shared scratch avoids a 16 KiB per-thread
  // CUDA stack reservation while protecting the in-place ring permutation.
  __shared__ int wrap[HISTORY_CAP];
  for (int row = 0; row < s->history_count; ++row) {
    int old_slot = (s->history_head - s->history_count + row +
                    s->history_capacity) % s->history_capacity;
    wrap[row] = s->history_wrap[old_slot];
  }
  for (int row = 0; row < s->history_count; ++row)
    s->history_wrap[row] = wrap[row];
  s->history = out;
  s->history_capacity = capacity;
  s->history_head = s->history_count % capacity;
}
__global__ void reset_replies(DeviceState *s) {
  s->reply_len = s->replies->length = 0;
  s->replies->title_changed = 0;
}
__global__ void scroll_view_kernel(DeviceState *s, int delta) {
  if (s->alt_active) {
    s->view_offset = 0;
    s->selection_active = 0;
    s->copy_flash = 0;
    return;
  }
  int maxoff = s->history_count;
  long long next = (long long)s->view_offset + delta;
  s->view_offset = (int)(next < 0 ? 0 : next > maxoff ? maxoff : next);
  s->selection_active = 0;
  s->copy_flash = 0;
}
__device__ int mouse_number(char *out, int value) {
  char digits[10];
  int count = 0;
  do {
    digits[count++] = char('0' + value % 10);
    value /= 10;
  } while (value);
  for (int i = 0; i < count; ++i)
    out[i] = digits[count - i - 1];
  return count;
}
__global__ void mouse_kernel(DeviceState *s, int button, int row, int col,
                             int modifiers, int action, int pixel_x, int pixel_y,
                             int *handled) {
  *handled = s->mouse_mode && !s->view_offset;
  if (!*handled)
    return;
  row = dmax(0, dmin(s->rows - 1, row));
  col = dmax(0, dmin(s->cols - 1, col));
  if (s->mouse_pixels) {
    row = dmax(0, dmin(s->rows * s->cell_height - 1, pixel_y < 0 ? row * s->cell_height : pixel_y));
    col = dmax(0, dmin(s->cols * s->cell_width - 1, pixel_x < 0 ? col * s->cell_width : pixel_x));
  }
  if (action == 2 &&
      (s->mouse_mode == 1000 || (s->mouse_mode == 1002 && button == 3) ||
       (row == s->mouse_row && col == s->mouse_col)))
    return;
  if (button >= 64 && action != 0)
    return;
  s->mouse_row = row;
  s->mouse_col = col;
  int code = button + (modifiers & 28) + (action == 2 ? 32 : 0);
  char out[40] = {27, '['};
  int n = 2;
  if (s->mouse_sgr || s->mouse_pixels) {
    out[n++] = '<';
    n += mouse_number(out + n, code);
    out[n++] = ';';
    n += mouse_number(out + n, col + 1);
    out[n++] = ';';
    n += mouse_number(out + n, row + 1);
    out[n++] = action == 1 ? 'm' : 'M';
  } else {
    if (col >= 223 || row >= 223)
      return;
    out[n++] = 'M';
    out[n++] = char(32 + (action == 1 ? 3 + (modifiers & 28) : code));
    out[n++] = char(33 + col);
    out[n++] = char(33 + row);
  }
  reply(*s, out, n);
}
__global__ void follow_output_kernel(DeviceState *s) {
  s->view_offset = 0;
  s->selection_active = 0;
  s->copy_flash = 0;
}

} // namespace

struct Engine::Impl {
  unsigned char *face = nullptr;
  size_t face_bytes = 0;
  cudaStream_t decode_stream = nullptr;
  void (*decode_pump)(void *, bool) = nullptr;
  void *pump_context = nullptr;
  bool decoding = false;
  std::string title;
  bool title_changed = false;
  GraphicsState *graphics = nullptr;
  unsigned char *graphics_input = nullptr;
  size_t graphics_capacity = 0;
  unsigned char *images[IMAGE_SLOTS]{};
  size_t image_sizes[IMAGE_SLOTS]{};
  size_t font_bytes = 0, grid_bytes = 0;
  void service_graphics(GraphicsRequest &request);
  DeviceState *d = nullptr;
  Hyperlinks *hyperlinks = nullptr;
  uint32_t *repair_flags = nullptr;
  uint16_t *font_rows = nullptr;
  uint32_t *font_pages = nullptr, *font_map = nullptr;
  unsigned char *font_widths = nullptr, *text_widths = nullptr;
  signed char *mark_offsets = nullptr;
  int *starts = nullptr;
  int *advances = nullptr;
  int *rejected = nullptr;
  PlainMeta *plain = nullptr;
  LineScan *lines = nullptr;
  StyledMeta *styled_meta = nullptr;
  int *styled_limit = nullptr, *styled_done = nullptr;
  void *scan_storage = nullptr;
  size_t scan_bytes = 0;
  int scan_capacity = 0;
  void reserve_scan(size_t requested);
  Cell *grids[2]{};
  Cell *history = nullptr;
  int history_capacity = 128, history_cols = 0;
  int history_rows = 0;
  bool alternate = false;
  void reserve_history(size_t bytes);
  void history_capacity_to(int capacity);
  ReplyBuffer *replies = nullptr;
  unsigned char *dbytes = nullptr;
  size_t input_capacity = 0;
  unsigned char *selection_output = nullptr;
  int *row_wrap = nullptr, *alt_row_wrap = nullptr, *history_wrap = nullptr;
  size_t selection_output_capacity = 0;
  mark_pool::Node *mark_nodes = nullptr;
  uint32_t *mark_used = nullptr, *mark_status = nullptr;
  uint32_t mark_capacity = 0;
  void grow_mark_pool();
  void compact_mark_pool();
  bool selection_possible = false;
  bool view_possible = false;
  SearchWork *search_work = nullptr;
  Cell *prompt_cells = nullptr;
  uint32_t *prompt_text = nullptr;
  std::string search_query, prompt;
  bool prompt_preedit = false;
  uint64_t content_generation = 0, search_generation = 0;
  unsigned long long search_token = ~0ull;
  bool synchronized = false;
  ~Impl() {
    cudaFree(hyperlinks);
    cudaFree(search_work); cudaFree(prompt_cells); cudaFree(prompt_text);
    if (decode_stream) {
      cudaStreamSynchronize(decode_stream);
      cudaStreamDestroy(decode_stream);
    }
    cudaFree(graphics);
    cudaFree(face);
    cudaFree(graphics_input);
    for (auto *image : images) cudaFree(image);
    cudaFree(repair_flags);
    cudaFree(font_rows);
    cudaFree(font_pages);
    cudaFree(font_map);
    cudaFree(font_widths);
    cudaFree(text_widths);
    cudaFree(mark_offsets);
    cudaFree(starts);
    cudaFree(advances);
    cudaFree(rejected);
    cudaFree(plain);
    cudaFree(lines);
    cudaFree(styled_meta);
    cudaFree(styled_limit);
    cudaFree(styled_done);
    cudaFree(scan_storage);
    cudaFree(d);
    cudaFree(grids[0]);
    cudaFree(grids[1]);
    cudaFree(history);
    cudaFree(replies);
    cudaFree(dbytes);
    cudaFree(selection_output);
    cudaFree(mark_nodes); cudaFree(mark_used); cudaFree(mark_status);
    cudaFree(row_wrap); cudaFree(alt_row_wrap); cudaFree(history_wrap);
  }
};
static void ck(cudaError_t e) {
  if (e != cudaSuccess)
    throw std::runtime_error(cudaGetErrorString(e));
}
__global__ void initialize_hyperlinks(DeviceState *s, Hyperlinks *links) {
  s->hyperlinks = links;
  s->hyperlinks_disabled = !links;
  s->graphics->request.ready = 0;
  s->graphics->request.barrier = 0;
  finish_osc(*s, false);
}
void Engine::Impl::service_graphics(GraphicsRequest &request) {
  if (request.barrier == 3) {
    if (!hyperlinks) {
      auto error = cudaMalloc(&hyperlinks, sizeof(Hyperlinks));
      if (error == cudaErrorMemoryAllocation) {
        hyperlinks = nullptr;
        cudaGetLastError();
      } else {
        ck(error);
        ck(cudaMemset(hyperlinks, 0, sizeof(Hyperlinks)));
      }
    }
    initialize_hyperlinks<<<1, 1>>>(d, hyperlinks);
    ck(cudaGetLastError());
    return;
  }
  // The GPU supplies validated allocation sizes and slot ownership. The host
  // only allocates/frees device storage; it never decodes terminal/image bytes.
  unsigned char *output = nullptr;
  bool failed = false;
  if (request.history_growth) {
    alternate = request.alternate;
    history_rows = request.history_rows;
    reserve_history((request.history_growth + 1) / 2);
  }
  if (request.input_bytes > graphics_capacity) {
    size_t capacity = 4096;
    while (capacity < request.input_bytes) capacity *= 2;
    unsigned char *next = nullptr;
    auto error = cudaMalloc(&next, capacity);
    if (error == cudaErrorMemoryAllocation) failed = true;
    else {
      ck(error);
      if (graphics_capacity)
        ck(cudaMemcpy(next, graphics_input, graphics_capacity, cudaMemcpyDeviceToDevice));
      ck(cudaFree(graphics_input));
      graphics_input = next; graphics_capacity = capacity;
    }
  }
  if (request.output_bytes && !failed) {
    auto error = cudaMalloc(&output, request.output_bytes);
    if (error == cudaErrorMemoryAllocation) failed = true;
    else ck(error);
  }
  const bool interactive = decode_pump && output && !failed;
  if (interactive) {
    if (!decode_stream) ck(cudaStreamCreateWithFlags(&decode_stream, cudaStreamNonBlocking));
    ck(cudaStreamSynchronize(nullptr));
  }
  graphics_decode<<<1, 128, 0, interactive ? decode_stream : nullptr>>>(
      d, graphics_input, output, graphics_capacity, failed);
  ck(cudaGetLastError());
  if (interactive) {
    decoding = true;
    try {
      for (;;) {
        auto status = cudaStreamQuery(decode_stream);
        if (status == cudaSuccess) break;
        if (status != cudaErrorNotReady) ck(status);
        decode_pump(pump_context, true);
      }
      decoding = false;
      decode_pump(pump_context, false);
    } catch (...) {
      cudaStreamSynchronize(decode_stream);
      decoding = false;
      cudaFree(output);
      throw;
    }
  }
  graphics_execute<<<1, 1>>>(d, graphics_input, output, failed);
  ck(cudaGetLastError());
  ck(cudaMemcpy(&request, &graphics->request, sizeof(request), cudaMemcpyDeviceToHost));
  if (request.committed) {
    ck(cudaFree(images[request.slot]));
    images[request.slot] = output;
    image_sizes[request.slot] = request.output_bytes;
  } else ck(cudaFree(output));
  for (int i = 0; i < IMAGE_SLOTS; ++i)
    if (request.release[i / 32] & (1u << (i % 32))) {
      ck(cudaFree(images[i])); images[i] = nullptr; image_sizes[i] = 0;
    }
  if (!request.keep_upload) {
    ck(cudaFree(graphics_input)); graphics_input = nullptr; graphics_capacity = 0;
  }
}
void Engine::Impl::reserve_scan(size_t requested) {
  if (requested <= (size_t)scan_capacity)
    return;
  size_t n = 256;
  while (n < requested)
    n *= 2;
  cudaFree(starts);
  starts = nullptr;
  cudaFree(advances);
  advances = nullptr;
  cudaFree(scan_storage);
  scan_storage = nullptr;
  scan_capacity = 0;
  ck(cudaMalloc(&starts, n * sizeof(int)));
  ck(cudaMalloc(&advances, n * sizeof(int)));
  cudaFree(lines);
  lines = nullptr;
  ck(cudaMalloc(&lines, n * sizeof(LineScan)));
  size_t a = 0, b = 0, c = 0;
  ck(cub::DeviceScan::InclusiveScan(nullptr, a, starts, starts, cub::Max(),
                                    (int)n));
  ck(cub::DeviceScan::InclusiveSum(nullptr, b, advances, advances, (int)n));
  ck(cub::DeviceScan::InclusiveScan(nullptr, c, lines, lines, JoinLines(),
                                    (int)n));
  scan_bytes = std::max(std::max(a, b), c);
  ck(cudaMalloc(&scan_storage, scan_bytes));
  scan_capacity = (int)n;
}
void Engine::Impl::reserve_history(size_t bytes) {
  // One byte can flush an invalid UTF-8 scalar and then emit another glyph
  // or newline. Reserving two rows per byte bounds both without host parsing.
  if (alternate) return;
  size_t bound = std::min(size_t(HISTORY_CAP), size_t(history_rows) + 2 * bytes);
  if (bound <= size_t(history_capacity))
    return;
  int capacity = history_capacity;
  while (size_t(capacity) < bound)
    capacity *= 2;
  history_capacity_to(capacity);
}
void Engine::Impl::history_capacity_to(int capacity) {
  Cell *next = nullptr;
  ck(cudaMalloc(&next, size_t(capacity) * history_cols * sizeof(Cell)));
  try {
    grow_history_kernel<<<(history_capacity * history_cols + 255) / 256, 256>>>(
        d, next);
    ck(cudaGetLastError());
    ck(cudaStreamSynchronize(nullptr));
    commit_history_growth<<<1, 1>>>(d, next, capacity);
    ck(cudaGetLastError());
    ck(cudaStreamSynchronize(nullptr));
  } catch (...) {
    cudaFree(next);
    throw;
  }
  cudaFree(history);
  history = next;
  history_capacity = capacity;
}
void Engine::Impl::grow_mark_pool() {
  constexpr uint32_t limit = 1u << 20; // At most 8 MiB of immutable suffix nodes.
  if (mark_capacity >= limit)
    throw std::runtime_error("mark suffix arena exhausted with live nodes");
  uint32_t capacity = std::max<uint32_t>(64, std::min(limit, mark_capacity * 2));
  mark_pool::Node *next = nullptr;
  ck(cudaMalloc(&next, size_t(capacity) * sizeof(mark_pool::Node)));
  try {
    uint32_t used = 0;
    ck(cudaMemcpy(&used, mark_used, sizeof(used), cudaMemcpyDeviceToHost));
    if (used) ck(cudaMemcpy(next, mark_nodes, size_t(used) * sizeof(mark_pool::Node), cudaMemcpyDeviceToDevice));
    DeviceState s;
    ck(cudaMemcpy(&s, d, sizeof(s), cudaMemcpyDeviceToHost));
    s.marks = {next, mark_used, capacity, mark_status};
    ck(cudaMemcpy(d, &s, sizeof(s), cudaMemcpyHostToDevice));
  } catch (...) { cudaFree(next); throw; }
  cudaFree(mark_nodes); mark_nodes = next; mark_capacity = capacity;
}
void Engine::Impl::compact_mark_pool() {
  if (!mark_capacity) return;
  DeviceState s;
  ck(cudaMemcpy(&s, d, sizeof(s), cudaMemcpyDeviceToHost));
  uint32_t n = 0;
  ck(cudaMemcpy(&n, mark_used, sizeof(n), cudaMemcpyDeviceToHost));
  if (n > mark_capacity)
    throw std::runtime_error("malformed mark suffix arena reference");
  std::vector<mark_pool::RootSpan> roots;
  roots.push_back({s.grid, (uint32_t)(s.rows * s.cols)});
  roots.push_back({s.alt, (uint32_t)(s.rows * s.cols)});
  if (s.history_count) {
    int first = (s.history_head - s.history_count + s.history_capacity) % s.history_capacity;
    int count = std::min(s.history_count, s.history_capacity - first);
    roots.push_back({s.history + first * s.history_cols, uint32_t(count * s.history_cols)});
    if (count < s.history_count)
      roots.push_back({s.history, uint32_t((s.history_count - count) * s.history_cols)});
  }
  if (prompt_cells) roots.push_back({prompt_cells, MAX_COLS});
  uint32_t root_count = 0;
  for (const auto &root : roots) root_count += root.count;
  mark_pool::RootSpan *droots = nullptr; uint32_t *map = nullptr;
  mark_pool::Node *scratch = nullptr; void *scan_temp = nullptr;
  size_t scan_bytes = 0;
  try {
    ck(cudaMalloc(&droots, roots.size() * sizeof(*droots)));
    ck(cudaMemcpy(droots, roots.data(), roots.size() * sizeof(*droots), cudaMemcpyHostToDevice));
    ck(cudaMemset(mark_status, 0, sizeof(uint32_t)));
    if (n && !mark_compaction_parallel::use_serial(n, root_count)) {
      ck(cudaMalloc(&map, size_t(n) * sizeof(uint32_t)));
      ck(cudaMalloc(&scratch, size_t(n) * sizeof(mark_pool::Node)));
      ck(mark_compaction_parallel::scan_prefix(nullptr, scan_bytes, map, n));
      ck(cudaMalloc(&scan_temp, scan_bytes));
    } else if (n) {
      ck(cudaMalloc(&map, size_t(n) * sizeof(uint32_t)));
      ck(cudaMalloc(&scratch, size_t(n) * sizeof(mark_pool::Node)));
    }
    mark_compaction_parallel::parallel_compact(
        s.marks, droots, roots.size(), n, root_count, map, scratch,
        scan_temp, scan_bytes);
    ck(cudaStreamSynchronize(nullptr));
    uint32_t status = 0; ck(cudaMemcpy(&status, mark_status, sizeof(status), cudaMemcpyDeviceToHost));
    if (status != mark_pool::OK)
      throw std::runtime_error("malformed mark suffix arena reference");
  } catch (...) {
    cudaFree(droots); cudaFree(map); cudaFree(scratch); cudaFree(scan_temp); throw;
  }
  ck(cudaFree(droots)); ck(cudaFree(map)); ck(cudaFree(scratch)); ck(cudaFree(scan_temp));
  uint32_t used = 0; ck(cudaMemcpy(&used, mark_used, sizeof(used), cudaMemcpyDeviceToHost));
  if (!used) {
    s.marks = {nullptr, mark_used, 0, mark_status};
    ck(cudaMemcpy(d, &s, sizeof(s), cudaMemcpyHostToDevice));
    cudaFree(mark_nodes); mark_nodes = nullptr; mark_capacity = 0;
  }
}
static void dims(int c, int r) {
  if (c < 1 || c > MAX_COLS || r < 1 || r > MAX_ROWS)
    throw std::runtime_error("invalid terminal dimensions");
}
static std::vector<unsigned char> read_data(const char *name, size_t size) {
  std::string path = std::string(CUDATERM_DATA_DIR) + "/" + name;
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  auto length = file.tellg();
  if (length < 0 || length > 64 * 1024 * 1024 ||
      (size && size_t(length) != size))
    throw std::runtime_error("invalid font data size: " + path);
  if (!size)
    size = size_t(length);
  file.seekg(0);
  std::vector<unsigned char> bytes(size);
  if (!file.read((char *)bytes.data(), size) ||
      file.peek() != std::char_traits<char>::eof())
    throw std::runtime_error("cannot read font data: " + path);
  return bytes;
}
Engine::Engine(int c, int r) : p(nullptr) {
  dims(c, r);
  configure_runtime();
  // This sm_89 build's largest compiled frame is 96 bytes. CUDA's 1024-byte
  // default reserves 168 MiB more on a 4090. The driver can grow this limit
  // for kernels requiring larger frames; no recursive device calls are used.
  ck(cudaDeviceSetLimit(cudaLimitStackSize, 128));
  p = new Impl;
  try {
    ck(cudaMalloc(&p->graphics, sizeof(GraphicsState)));
    ck(cudaMemset(p->graphics, 0, sizeof(GraphicsState)));
    ck(cudaMalloc(&p->d, sizeof(DeviceState)));
    ck(cudaMalloc(&p->mark_used, sizeof(uint32_t)));
    ck(cudaMalloc(&p->mark_status, sizeof(uint32_t)));
    ck(cudaMemset(p->mark_used, 0, sizeof(uint32_t)));
    ck(cudaMemset(p->mark_status, 0, sizeof(uint32_t)));
    p->history_cols = c;
    ck(cudaMalloc(&p->history, p->history_capacity * c * sizeof(Cell)));
    ck(cudaMalloc(&p->row_wrap, MAX_ROWS * sizeof(int)));
    ck(cudaMalloc(&p->alt_row_wrap, MAX_ROWS * sizeof(int)));
    ck(cudaMalloc(&p->history_wrap, HISTORY_CAP * sizeof(int)));
    ck(cudaMemset(p->row_wrap, 0, MAX_ROWS * sizeof(int)));
    ck(cudaMemset(p->alt_row_wrap, 0, MAX_ROWS * sizeof(int)));
    ck(cudaMemset(p->history_wrap, 0, HISTORY_CAP * sizeof(int)));
    ck(cudaMalloc(&p->repair_flags, MAX_ROWS * MAX_COLS * sizeof(uint32_t)));
    ck(cudaMalloc(&p->rejected, sizeof(int)));
    ck(cudaMalloc(&p->plain, sizeof(PlainMeta)));
    ck(cudaMalloc(&p->styled_meta, sizeof(StyledMeta)));
    ck(cudaMalloc(&p->styled_limit, sizeof(int)));
    ck(cudaMalloc(&p->styled_done, sizeof(int)));
    auto font = read_data("font.bin", 0);
    if (font.size() < 16 || std::memcmp(font.data(), "CTFONT02", 8))
      throw std::runtime_error("invalid font atlas header");
    auto word = [&](size_t offset) {
      uint32_t value;
      std::memcpy(&value, font.data() + offset, sizeof(value));
      return value;
    };
    uint32_t count = word(8), pages = word(12);
    size_t widths_start = 16 + size_t(count) * 32;
    size_t pages_start = widths_start + count;
    size_t map_start = pages_start + 0x1100 * sizeof(uint32_t);
    if (count < 65536 || count > 0x110000 || pages > 0x1100 ||
        font.size() != map_start + size_t(pages) * 256 * sizeof(uint32_t))
      throw std::runtime_error("invalid font atlas dimensions");
    for (size_t i = widths_start; i < pages_start; ++i)
      if (font[i] != 0 && font[i] != 8 && font[i] != 16)
        throw std::runtime_error("invalid font glyph width");
    if (!font[widths_start + 0xfffd])
      throw std::runtime_error("font lacks replacement glyph");
    for (size_t i = pages_start; i < map_start; i += 4)
      if (word(i) != 0xffffffffu && word(i) >= pages)
        throw std::runtime_error("invalid font page");
    for (size_t i = map_start; i < font.size(); i += 4)
      if (word(i) != 0xffffffffu && word(i) >= count)
        throw std::runtime_error("invalid font mapping");
    auto widths = read_data("widths.bin", 0x110000);
    auto offsets = read_data("offsets.bin", 0x110000);
    p->font_bytes = size_t(count) * 33 + 0x1100 * 4 +
                    std::max(size_t(4), size_t(pages) * 256 * 4) + widths.size() + offsets.size();
    ck(cudaMalloc(&p->font_rows, size_t(count) * 32));
    ck(cudaMalloc(&p->font_widths, count));
    ck(cudaMalloc(&p->font_pages, 0x1100 * sizeof(uint32_t)));
    ck(cudaMalloc(&p->font_map, std::max(size_t(4), size_t(pages) * 256 * 4)));
    ck(cudaMemcpy(p->font_pages, font.data() + pages_start, 0x1100 * 4,
                  cudaMemcpyHostToDevice));
    if (pages)
      ck(cudaMemcpy(p->font_map, font.data() + map_start,
                    size_t(pages) * 256 * 4, cudaMemcpyHostToDevice));
    ck(cudaMalloc(&p->text_widths, widths.size()));
    ck(cudaMalloc(&p->mark_offsets, offsets.size()));
    ck(cudaMemcpy(p->font_rows, font.data() + 16, size_t(count) * 32,
                  cudaMemcpyHostToDevice));
    ck(cudaMemcpy(p->font_widths, font.data() + widths_start, count,
                  cudaMemcpyHostToDevice));
    ck(cudaMemcpy(p->text_widths, widths.data(), widths.size(),
                  cudaMemcpyHostToDevice));
    ck(cudaMemcpy(p->mark_offsets, offsets.data(), offsets.size(),
                  cudaMemcpyHostToDevice));
    ck(cudaMalloc(&p->grids[0], c * r * sizeof(Cell)));
    ck(cudaMalloc(&p->grids[1], c * r * sizeof(Cell)));
    p->grid_bytes = size_t(c) * r * sizeof(Cell) * 2;
    ck(cudaMalloc(&p->replies, sizeof(ReplyBuffer)));
    ck(cudaMemset(p->replies, 0, sizeof(ReplyBuffer)));
    init_grid<<<(c * r + 255) / 256, 256>>>(p->grids[0], p->grids[1], c * r);
    ck(cudaGetLastError());
    DeviceState s{};
    s.cell_width = 8; s.cell_height = 16;
    s.background_alpha = 255;
    s.theme = s.base_theme = default_theme();
    s.graphics = p->graphics;
    s.marks = {p->mark_nodes, p->mark_used, p->mark_capacity, p->mark_status};
    s.repair_flags = p->repair_flags;
    s.font_rows = p->font_rows;
    s.font_pages = p->font_pages;
    s.font_map = p->font_map;
    s.font_widths = p->font_widths;
    s.text_widths = p->text_widths;
    s.mark_offsets = p->mark_offsets;
    s.cols = c;
    s.rows = r;
    s.bottom = r - 1;
    s.fg = DEFAULT_FG;
    s.bg = DEFAULT_BG;
    s.cursor_visible = 1;
    s.cursor_phase = s.window_focused = 1;
    s.cursor_x = s.cursor_y = -1;
    s.default_cursor_style = 2;
    s.numlock_override = 1;
    s.mouse_row = s.mouse_col = -1;
    s.autowrap = s.saved_autowrap = 1;
    s.saved_fg = DEFAULT_FG;
    s.saved_bg = DEFAULT_BG;
    for (int c = 0; c < MAX_COLS; ++c)
      s.tabs[c] = (c > 0 && c % 8 == 0);
    for (int i = 0; i < r; ++i)
      s.rowmap[i] = s.alt_rowmap[i] = i;
    s.grid = p->grids[0];
    s.alt = p->grids[1];
    s.history = p->history;
    s.row_wrap = p->row_wrap; s.alt_row_wrap = p->alt_row_wrap;
    s.history_wrap = p->history_wrap;
    s.history_count = s.history_head = s.history_cols = s.view_offset = 0;
    s.history_cols = c;
    s.history_capacity = p->history_capacity;
    s.replies = p->replies;
    s.selection_output = nullptr;
    s.selection_output_len = 0;
    s.selection_active = 0;
    ck(cudaMemcpy(p->d, &s, sizeof(s), cudaMemcpyHostToDevice));
  } catch (...) {
    delete p;
    p = nullptr;
    throw;
  }
}
Engine::~Engine() { delete p; }
void Engine::feed(const unsigned char *b, size_t n) {
  enqueue_feed(b, n);
  if (n)
    ck(cudaStreamSynchronize(nullptr));
}
std::string Engine::feed_and_replies(const unsigned char *b, size_t n) {
  enqueue_feed(b, n);
  // The blocking reply-buffer copy completes preceding default-stream work.
  return take_replies();
}
FeedResult Engine::feed_frame(const unsigned char *b, size_t n) {
  return enqueue_feed(b, n, true);
}
FeedResult Engine::enqueue_feed(const unsigned char *b, size_t n, bool stop_at_frame) {
  if (p->decoding) throw std::logic_error("cannot feed PTY output from decode pump");
  if (!n)
    return {0, false};
  if (!b || n > (1u << 20))
    throw std::runtime_error("invalid input chunk");
  ++p->content_generation;
  if (n > p->input_capacity) {
    size_t capacity = 4096;
    while (capacity < n) capacity *= 2;
    unsigned char *next = nullptr;
    ck(cudaMalloc(&next, capacity));
    ck(cudaFree(p->dbytes));
    p->dbytes = next; p->input_capacity = capacity;
  }
  if (p->selection_possible) {
    clear_selection_kernel<<<1, 1>>>(p->d);
    ck(cudaGetLastError());
    p->selection_possible = false;
  }
  ck(cudaMemcpy(p->dbytes, b, n, cudaMemcpyHostToDevice));
  bool pending_retry = false;
  auto dispatch = [&](const unsigned char *device_input, size_t n) {
  if (pending_retry) {
    feed_kernel<<<1, 32>>>(p->d, device_input, std::min(n, size_t(4096)));
    ck(cudaGetLastError());
    return;
  }
  // An upload in progress is opaque graphics transport, not text to classify.
  if (n >= 256 && !p->graphics_capacity) {
    p->reserve_scan(n);
    int input_size = (int)n;
    ck(cudaMemcpy(p->rejected, &input_size, sizeof(int),
                  cudaMemcpyHostToDevice));
    plain_classify<<<(n + 255) / 256, 256>>>(p->d, device_input, n, p->starts,
                                             p->rejected, p->styled_done,
                                             p->styled_limit);
    ck(cudaGetLastError());
    int ascii_prefix = 0;
    ck(cudaMemcpy(&ascii_prefix, p->rejected, sizeof(int),
                  cudaMemcpyDeviceToHost));
    if (ascii_prefix < 0) {
      // GPU finishes a bounded fragment; the host only transports its consumed
      // byte count, then launches the classifier on the untouched remainder.
      feed_kernel<<<1, 32>>>(p->d, device_input, std::min(n, size_t(4096)),
                             nullptr, nullptr, p->styled_done);
      ck(cudaGetLastError());
      return;
    }
    // A short non-ASCII tail costs less in the interpreter than a styled scan
    // of the entire input. The plain path still commits the classified prefix.
    if (ascii_prefix != (int)n &&
        (ascii_prefix < 256 || (int)n - ascii_prefix >= 256)) {
      styled_lines<<<(n + 127) / 128, 128>>>(p->d, device_input, (int)n,
                                             p->lines, p->styled_limit);
      ck(cudaGetLastError());
      ck(cub::DeviceScan::InclusiveScan(p->scan_storage, p->scan_bytes,
                                        p->lines, p->lines, JoinLines(),
                                        (int)n));
      styled_commit<<<1, 1>>>(p->d, device_input, p->lines, p->styled_limit,
                              p->styled_done, p->styled_meta, p->rejected);
      ck(cudaGetLastError());
      prepare_history<<<256, 256>>>(p->d, p->styled_done, p->styled_meta);
      ck(cudaGetLastError());
      styled_paint<<<(n + 127) / 128, 128>>>(
          p->d, device_input, (int)n, p->lines, p->styled_done, p->styled_meta);
      ck(cudaGetLastError());
    }
    if (n <= 4096) {
      plain_scan_small<<<1, 256>>>(p->d, device_input, (int)n, p->rejected,
                                   p->starts, p->advances);
      ck(cudaGetLastError());
    } else {
      ck(cub::DeviceScan::InclusiveScan(p->scan_storage, p->scan_bytes,
                                        p->starts, p->starts, cub::Max(),
                                        (int)n));
      plain_advances<<<(n + 255) / 256, 256>>>(
          p->d, device_input, n, p->starts, p->advances, p->rejected);
      ck(cudaGetLastError());
      ck(cub::DeviceScan::InclusiveSum(p->scan_storage, p->scan_bytes,
                                       p->advances, p->advances, (int)n));
    }
    plain_commit<<<1, 1>>>(p->d, device_input, n, p->starts, p->advances,
                           p->rejected, p->plain);
    ck(cudaGetLastError());
    prepare_history<<<256, 256>>>(p->d, p->rejected, p->plain);
    ck(cudaGetLastError());
    plain_clear<<<(MAX_ROWS * MAX_COLS + 255) / 256, 256>>>(p->d, p->rejected,
                                                            p->plain);
    ck(cudaGetLastError());
    plain_scatter<<<(n + 255) / 256, 256>>>(p->d, device_input, n, p->starts,
                                            p->advances, p->rejected, p->plain);
    ck(cudaGetLastError());
    plain_wrap_metadata<<<(n + 255) / 256, 256>>>(
        p->d, device_input, n, p->starts, p->advances, p->rejected, p->plain);
    ck(cudaGetLastError());
    repair_history<<<16, 256>>>(p->d, p->rejected, p->plain);
    ck(cudaGetLastError());
    plain_repair<<<(MAX_ROWS * MAX_COLS + 255) / 256, 256>>>(p->d, p->rejected);
    ck(cudaGetLastError());
    feed_kernel<<<1, 32>>>(p->d, device_input, n, p->rejected, p->styled_done);
  } else
    feed_kernel<<<1, 32>>>(p->d, device_input, n);

  ck(cudaGetLastError());
  };
  size_t offset = 0;
  while (offset < n || pending_retry) {
    bool resumed = pending_retry;
    if (offset < n) p->reserve_history(n - offset);
    dispatch(p->dbytes + offset, n - offset);
    GraphicsRequest request;
    ck(cudaMemcpy(&request, &p->graphics->request, sizeof(request), cudaMemcpyDeviceToHost));
    pending_retry = request.pool_wait != 0;
    if (request.consumed < 0 || (request.consumed == 0 && !request.pool_wait && !resumed) ||
        size_t(request.consumed) > n - offset)
      throw std::runtime_error("GPU parser made invalid progress");
    offset += request.consumed;
    bool reset = request.ready && request.reset;
    bool complete = request.ready && request.barrier == 2;
    if (request.ready) p->service_graphics(request);
    p->alternate = request.alternate;
    p->history_rows = request.history_rows;
    if (request.pool_wait) {
      uint32_t status = 0;
      ck(cudaMemcpy(&status, p->mark_status, sizeof(status), cudaMemcpyDeviceToHost));
      if (status == mark_pool::MALFORMED)
        throw std::runtime_error("malformed mark suffix arena reference");
      if (status != mark_pool::FULL)
        throw std::runtime_error("GPU parser requested invalid mark-pool wait");
      p->compact_mark_pool();
      uint32_t used = 0;
      ck(cudaMemcpy(&used, p->mark_used, sizeof(used), cudaMemcpyDeviceToHost));
      if (used >= p->mark_capacity) p->grow_mark_pool();
      ck(cudaMemset(p->mark_status, 0, sizeof(uint32_t)));
      continue;
    }
    if (request.pool_gc)
      p->compact_mark_pool();
    if (p->alternate || reset) {
      int capacity = 128;
      while (capacity < p->history_rows) capacity *= 2;
      if (capacity < p->history_capacity) p->history_capacity_to(capacity);
    }
    if (complete && stop_at_frame) return {offset, true};
  }
  return {n, false};
}

void Engine::resize(int c, int r) {
  dims(c, r);
  if (c == p->history_cols && size_t(c) * r * sizeof(Cell) * 2 == p->grid_bytes) return;
  ++p->content_generation;
  Cell *a = nullptr, *b = nullptr, *history = nullptr;
  int *rw = nullptr, *arw = nullptr, *hw = nullptr, *map = nullptr, *wrap = nullptr;
  ReflowPlan *plan = nullptr, result{};
  ReflowRow *info = nullptr;
  int capacity = 128;
  size_t source_cells = size_t(p->history_capacity + MAX_ROWS) * p->history_cols;
  try {
    ck(cudaMalloc(&map, source_cells * sizeof(int)));
    ck(cudaMemset(map, 0xff, source_cells * sizeof(int)));
    ck(cudaMalloc(&wrap, (HISTORY_CAP + r) * sizeof(int)));
    ck(cudaMalloc(&plan, sizeof(ReflowPlan)));
    ck(cudaMalloc(&info, (p->history_capacity + MAX_ROWS) * sizeof(ReflowRow)));
    inspect_reflow_rows<<<p->history_capacity + MAX_ROWS, 256>>>(p->d, info);
    ck(cudaGetLastError());
    plan_reflow<<<1, 1>>>(p->d, c, r, map, wrap, info, plan);
    ck(cudaGetLastError());
    ck(cudaMemcpy(&result, plan, sizeof(result), cudaMemcpyDeviceToHost));
    int history_count = std::min(HISTORY_CAP, result.screen_start);
    while (capacity < history_count) capacity *= 2;
    ck(cudaMalloc(&a, size_t(c) * r * sizeof(Cell)));
    ck(cudaMalloc(&b, size_t(c) * r * sizeof(Cell)));
    ck(cudaMalloc(&history, size_t(capacity) * c * sizeof(Cell)));
    ck(cudaMalloc(&rw, MAX_ROWS * sizeof(int)));
    ck(cudaMalloc(&arw, MAX_ROWS * sizeof(int)));
    ck(cudaMalloc(&hw, HISTORY_CAP * sizeof(int)));
    ck(cudaMemset(hw, 0, HISTORY_CAP * sizeof(int)));
    initialize_reflow<<<(std::max(capacity, r) * c + 255) / 256, 256>>>(
        p->d, a, b, history, c, r, capacity);
    ck(cudaGetLastError());
    scatter_reflow<<<(source_cells + 255) / 256, 256>>>(p->d, map, plan, info, c, r, a, b, history);
    ck(cudaGetLastError());
    ck(cudaStreamSynchronize(nullptr));
    commit_reflow<<<1, 1>>>(p->d, a, b, history, rw, arw, hw, wrap, map, plan, info, c, r, capacity);
    ck(cudaGetLastError());
    ck(cudaStreamSynchronize(nullptr));
  } catch (...) {
    cudaFree(a); cudaFree(b); cudaFree(history);
    cudaFree(rw); cudaFree(arw); cudaFree(hw);
    cudaFree(map); cudaFree(wrap); cudaFree(plan); cudaFree(info);
    throw;
  }
  cudaFree(p->grids[0]); cudaFree(p->grids[1]); cudaFree(p->history);
  cudaFree(p->row_wrap); cudaFree(p->alt_row_wrap); cudaFree(p->history_wrap);
  cudaFree(map); cudaFree(wrap); cudaFree(plan); cudaFree(info);
  p->grids[0] = a; p->grids[1] = b; p->history = history;
  p->row_wrap = rw; p->alt_row_wrap = arw; p->history_wrap = hw;
  p->history_cols = c; p->history_capacity = capacity;
  p->history_rows = std::min(HISTORY_CAP, result.screen_start);
  p->grid_bytes = size_t(c) * r * sizeof(Cell) * 2;
  p->selection_possible = false;
}
MemoryUsage Engine::memory_usage() const {
  size_t images = 0;
  for (size_t bytes : p->image_sizes) images += bytes;
  uint32_t mark_nodes = 0;
  ck(cudaMemcpy(&mark_nodes, p->mark_used, sizeof(mark_nodes), cudaMemcpyDeviceToHost));
  size_t bytes = sizeof(DeviceState) + sizeof(GraphicsState) + sizeof(ReplyBuffer) +
    sizeof(int) * (3 + 2 * MAX_ROWS + HISTORY_CAP) + sizeof(PlainMeta) + sizeof(StyledMeta) +
    MAX_ROWS * MAX_COLS * sizeof(uint32_t) + p->font_bytes + p->face_bytes + p->grid_bytes +
    size_t(p->history_capacity) * p->history_cols * sizeof(Cell) +
    p->input_capacity + size_t(p->scan_capacity) * (sizeof(int) * 2 + sizeof(LineScan)) +
    p->scan_bytes + p->selection_output_capacity + p->graphics_capacity + images +
    (p->hyperlinks ? sizeof(Hyperlinks) : 0) +
    size_t(p->mark_capacity) * sizeof(mark_pool::Node) + 2 * sizeof(uint32_t) +
    (p->search_work ? sizeof(SearchWork) : 0) +
    (p->prompt_cells ? MAX_COLS * sizeof(Cell) : 0) +
    (p->prompt_text ? 1024 * sizeof(uint32_t) : 0);
  return {bytes, images, p->graphics_capacity, p->history_capacity,
          size_t(p->mark_capacity) * sizeof(mark_pool::Node), mark_nodes};
}
__global__ void hyperlink_at_kernel(const DeviceState *s, int row, int col, char *out) {
  out[0] = 0;
  if (!s->hyperlinks || row < 0 || row >= s->rows || col < 0 || col >= s->cols) return;
  uint32_t id = viewed_cell(*s, row, col).flags >> HYPERLINK_SHIFT;
  if (!id) return;
  const auto &entry = s->hyperlinks->entries[(id - 1) % HYPERLINK_SLOTS];
  if (entry.id != id) return;
  for (int i = 0; i < 512; ++i) {
    out[i] = entry.uri[i];
    if (!out[i]) return;
  }
}
std::string Engine::hyperlink_at(int row, int col) {
  if (!p->hyperlinks) return {};
  char *device = p->hyperlinks->query;
  char uri[512]{};
  hyperlink_at_kernel<<<1, 1>>>(p->d, row, col, device);
  ck(cudaGetLastError());
  ck(cudaMemcpy(uri, device, sizeof(uri), cudaMemcpyDeviceToHost));
  return uri;
}
Snapshot Engine::snapshot() {
  DeviceState s;
  ck(cudaMemcpy(&s, p->d, sizeof(s), cudaMemcpyDeviceToHost));
  return {s.cols,
          s.rows,
          s.row,
          s.col,
          s.history_count,
          s.view_offset,
          (bool)s.cursor_visible,
          (bool)s.app_cursor,
          (bool)s.bracketed_paste,
          s.mouse_mode != 0,
          s.synchronized_updates != 0, s.cell_width, s.cell_height, s.alt_active != 0,
          s.app_keypad != 0, s.numlock_override != 0,
          s.cursor_style ? s.cursor_style : s.default_cursor_style,
          keyboard::current(s.keyboard, s.alt_active != 0)};
}
__global__ void focus_kernel(DeviceState *s, bool focused) {
  if (s->focus_reporting) reply(*s, focused ? "\033[I" : "\033[O", 3);
}
void Engine::focus(bool focused) {
  focus_kernel<<<1, 1>>>(p->d, focused);
  ck(cudaGetLastError());
}
bool Engine::mouse(int button, int row, int col, int modifiers, int action,
                    int pixel_x, int pixel_y) {
  if ((button < 0 || (button > 3 && (button < 64 || button > 67))) ||
      action < 0 || action > 2)
    throw std::runtime_error("invalid mouse event");
  mouse_kernel<<<1, 1>>>(p->d, button, row, col, modifiers, action, pixel_x, pixel_y,
                         p->styled_done);
  ck(cudaGetLastError());
  int handled = 0;
  ck(cudaMemcpy(&handled, p->styled_done, sizeof(handled),
                cudaMemcpyDeviceToHost));
  return handled != 0;
}
void Engine::scroll_view(int delta) {
  if (!delta)
    return;
  scroll_view_kernel<<<1, 1>>>(p->d, delta);
  ck(cudaGetLastError());
  ck(cudaStreamSynchronize(nullptr));
  p->selection_possible = false;
  p->view_possible = true;
}
void Engine::follow_output() {
  // Only host viewport navigation can leave the live view. Terminal output
  // may reset that state, so this conservative hint can only cause extra work.
  if (!p->view_possible && !p->selection_possible)
    return;
  follow_output_kernel<<<1, 1>>>(p->d);
  ck(cudaGetLastError());
  ck(cudaStreamSynchronize(nullptr));
  p->selection_possible = false;
  p->view_possible = false;
}
std::vector<Cell> Engine::cells() {
  DeviceState s;
  ck(cudaMemcpy(&s, p->d, sizeof(s), cudaMemcpyDeviceToHost));
  std::vector<Cell> z(s.cols * s.rows);
  ck(cudaMemcpy(z.data(), s.grid, z.size() * sizeof(Cell),
                cudaMemcpyDeviceToHost));
  std::vector<Cell> ordered(z.size());
  for (int r = 0; r < s.rows; ++r)
    std::copy_n(z.data() + s.rowmap[r] * s.cols, s.cols,
                ordered.data() + r * s.cols);
  for (auto &cell : ordered) {
    cell.fg = resolved(s, cell.fg); cell.bg = resolved(s, cell.bg);
  }
  return ordered;
}
std::string Engine::take_replies() {
  ReplyBuffer buffer;
  ck(cudaMemcpy(&buffer, p->replies, sizeof(buffer), cudaMemcpyDeviceToHost));
  p->synchronized = buffer.synchronized_updates;
  if (buffer.title_changed) { p->title = buffer.title; p->title_changed = true; }
  if (buffer.length < 0 || buffer.length > REPLY_CAP)
    throw std::runtime_error("invalid reply buffer length");
  std::string z(reinterpret_cast<const char *>(buffer.bytes), buffer.length);
  if (buffer.length || buffer.title_changed) {
    reset_replies<<<1, 1>>>(p->d);
    ck(cudaGetLastError());
  }
  return z;
}
bool Engine::synchronized_updates() const { return p->synchronized; }

void Engine::select(int sr, int sc, int er, int ec, SelectionMode mode, bool history) {
  select_kernel<<<1, 1>>>(p->d, sr, sc, er, ec, mode, history);
  ck(cudaGetLastError());
  ck(cudaStreamSynchronize(nullptr));
  p->selection_possible = true;
}
__global__ void copy_flash_kernel(DeviceState *s, bool active) {
  s->copy_flash = active;
}
void Engine::set_copy_flash(bool active) {
  copy_flash_kernel<<<1, 1>>>(p->d, active);
  ck(cudaGetLastError());
}
void Engine::clear_selection() {
  if (!p->selection_possible)
    return;
  clear_selection_kernel<<<1, 1>>>(p->d);
  ck(cudaGetLastError());
  ck(cudaStreamSynchronize(nullptr));
  p->selection_possible = false;
}
static std::vector<uint32_t> search_decode(const std::string &text, size_t limit) {
  std::vector<uint32_t> result;
  for (size_t i = 0; i < text.size();) {
    unsigned char b = text[i++];
    uint32_t cp = b; int extra = 0;
    if (b >= 0xc2 && b <= 0xdf) { cp = b & 31; extra = 1; }
    else if (b >= 0xe0 && b <= 0xef) { cp = b & 15; extra = 2; }
    else if (b >= 0xf0 && b <= 0xf4) { cp = b & 7; extra = 3; }
    else if (b >= 0x80) throw std::invalid_argument("invalid UTF-8 search text");
    if (i + extra > text.size()) throw std::invalid_argument("incomplete UTF-8 search text");
    for (int n = 0; n < extra; ++n) {
      unsigned char v = text[i++];
      if ((v & 0xc0) != 0x80) throw std::invalid_argument("invalid UTF-8 search text");
      cp = (cp << 6) | (v & 63);
    }
    if ((extra == 1 && cp < 0x80) || (extra == 2 && cp < 0x800) ||
        (extra == 3 && cp < 0x10000) || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff))
      throw std::invalid_argument("invalid UTF-8 search codepoint");
    if (result.size() == limit) throw std::invalid_argument("search text exceeds codepoint limit");
    result.push_back(cp);
  }
  return result;
}
SearchMatch Engine::search(const std::string &query, SearchDirection direction, bool restart) {
  auto decoded = search_decode(query, 512);
  if (decoded.empty()) { clear_search(); return {false,false,0,0,0,0,snapshot().view_offset}; }
  auto s = snapshot();
  if (!restart && p->search_query == query && p->search_generation != p->content_generation)
    return {false,true,0,0,0,0,s.view_offset};
  int history = s.alternate_screen ? 0 : s.history_rows;
  SearchWork work{};
  std::copy(decoded.begin(), decoded.end(), work.query);
  work.length = decoded.size(); work.cells = (history + s.rows) * s.cols;
  work.total = (unsigned long long)work.cells << 32;
  work.step = direction == SearchDirection::Forward ? 1 : -1;
  if (!restart && p->search_query == query && p->search_token != ~0ull)
    work.start = (p->search_token + work.total + (work.step > 0 ? 1 : -1ll)) % work.total;
  else work.start = work.step > 0 ? ((unsigned long long)(history - s.view_offset) * s.cols << 32)
                                  : ((unsigned long long)(history - s.view_offset + s.rows) * s.cols << 32) - 1;
  work.rank = ~0ull;
  if (!p->search_work) ck(cudaMalloc(&p->search_work, sizeof(SearchWork)));
  ck(cudaMemcpy(p->search_work, &work, sizeof(work), cudaMemcpyHostToDevice));
  find_search<<<(work.cells + 255) / 256, 256>>>(p->d, p->search_work);
  ck(cudaGetLastError());
  commit_search<<<1, 1>>>(p->d, p->search_work);
  ck(cudaGetLastError());
  ck(cudaMemcpy(&work, p->search_work, sizeof(work), cudaMemcpyDeviceToHost));
  p->search_query = query; p->search_token = work.token;
  p->search_generation = p->content_generation;
  p->selection_possible = work.match.found;
  p->view_possible = work.match.view_offset != 0;
  return work.match;
}
void Engine::clear_search() {
  p->search_query.clear(); p->search_token = ~0ull;
  cudaFree(p->search_work); p->search_work = nullptr;
  clear_selection();
}
void Engine::set_search_prompt(const std::string &text) {
  set_overlay(text, false);
}
void Engine::set_preedit(const std::string &text) {
  set_overlay(text, true);
}
void Engine::set_overlay(const std::string &text, bool preedit) {
  p->prompt_preedit = preedit;
  auto decoded = search_decode(text, 1024);
  if (decoded.empty()) {
    cudaFree(p->prompt_cells); p->prompt_cells = nullptr;
    cudaFree(p->prompt_text); p->prompt_text = nullptr;
    p->prompt.clear();
    if (p->mark_capacity) p->compact_mark_pool();
    return;
  }
  if (!p->prompt_cells) ck(cudaMalloc(&p->prompt_cells, MAX_COLS * sizeof(Cell)));
  ck(cudaMemset(p->prompt_cells, 0, MAX_COLS * sizeof(Cell)));
  if (!p->prompt_text) ck(cudaMalloc(&p->prompt_text, 1024 * sizeof(uint32_t)));
  ck(cudaMemcpy(p->prompt_text, decoded.data(), decoded.size() * sizeof(uint32_t), cudaMemcpyHostToDevice));
  search_prompt_cells<<<1, 1>>>(p->d, p->prompt_text, decoded.size(), p->prompt_cells, true, preedit);
  ck(cudaGetLastError());
  uint32_t needed = 0, used = 0;
  ck(cudaMemcpy(&needed, p->mark_status, sizeof(needed), cudaMemcpyDeviceToHost));
  ck(cudaMemcpy(&used, p->mark_used, sizeof(used), cudaMemcpyDeviceToHost));
  if (needed > p->mark_capacity - used) {
    if (p->mark_capacity) p->compact_mark_pool();
    ck(cudaMemcpy(&used, p->mark_used, sizeof(used), cudaMemcpyDeviceToHost));
    while (needed > p->mark_capacity - used) p->grow_mark_pool();
  }
  ck(cudaMemset(p->mark_status, 0, sizeof(uint32_t)));
  search_prompt_cells<<<1, 1>>>(p->d, p->prompt_text, decoded.size(), p->prompt_cells, false, preedit);
  ck(cudaGetLastError());
  uint32_t status = 0;
  ck(cudaMemcpy(&status, p->mark_status, sizeof(status), cudaMemcpyDeviceToHost));
  if (status != mark_pool::OK) throw std::runtime_error("mark prompt allocation failed");
  p->prompt = text;
}
std::string Engine::selected_text() {
  if (!p->selection_possible)
    return {};
  DeviceState s;
  ck(cudaMemcpy(&s, p->d, sizeof(s), cudaMemcpyDeviceToHost));
  if (!s.selection_active) return {};
  std::string result;
  for (int start = s.selection_start_row; start <= s.selection_end_row; start += s.rows) {
    int end = std::min(s.selection_end_row, start + s.rows - 1);
    ck(cudaMemset(p->mark_status, 0, sizeof(uint32_t)));
    selected_text_kernel<<<1, 1>>>(p->d, start, end, true);
    ck(cudaGetLastError());
    uint32_t status = 0;
    ck(cudaMemcpy(&status, p->mark_status, sizeof(status), cudaMemcpyDeviceToHost));
    if (status != mark_pool::OK) throw std::runtime_error("malformed selection mark reference");
    ck(cudaMemcpy(&s, p->d, sizeof(s), cudaMemcpyDeviceToHost));
    size_t needed = s.selection_output_len;
    if (needed > (64u << 20)) throw std::runtime_error("selection batch exceeds 64 MiB");
    if (needed > p->selection_output_capacity) {
      unsigned char *next = nullptr;
      ck(cudaMalloc(&next, needed));
      cudaFree(p->selection_output);
      p->selection_output = next; p->selection_output_capacity = needed;
      set_selection_output_kernel<<<1, 1>>>(p->d, next);
      ck(cudaGetLastError());
    }
    if (needed) {
      selected_text_kernel<<<1, 1>>>(p->d, start, end, false);
      ck(cudaGetLastError());
      size_t old = result.size(); result.resize(old + needed);
      ck(cudaMemcpy(result.data() + old, p->selection_output, needed, cudaMemcpyDeviceToHost));
    }
  }
  // Large copy buffers are transient; ordinary selections retain at most 64 KiB.
  if (p->selection_output_capacity > (64u << 10)) {
    cudaFree(p->selection_output); p->selection_output = nullptr; p->selection_output_capacity = 0;
    set_selection_output_kernel<<<1, 1>>>(p->d, nullptr);
    ck(cudaGetLastError());
  }
  return result;
}
void Engine::render(uint32_t *out, int w, int h) {
  if (!out || w < 1 || h < 1)
    return;
  dim3 b(16, 16), g((w + 15) / 16, (h + 15) / 16);
  render_kernel<<<g, b>>>(p->d, out, w, h, p->prompt_cells, p->prompt_preedit);
  ck(cudaGetLastError());
}
} // namespace ct

namespace ct {
__global__ void theme_kernel(DeviceState *s, Theme theme) {
  s->theme = s->base_theme = theme;
}
void Engine::set_theme(const Theme &theme) {
  for (uint32_t color : theme.colors)
    if (color > 0xffffff) throw std::runtime_error("invalid theme color");
  theme_kernel<<<1, 1>>>(p->d, theme);
  ck(cudaGetLastError());
}
bool Engine::take_title(std::string &title) {
  if (!p->title_changed) return false;
  title = p->title; p->title_changed = false; return true;
}
}

namespace ct {
void Engine::set_decode_pump(void (*pump)(void *, bool), void *context) {
  if (p->decoding) throw std::logic_error("cannot replace active decode pump");
  // Lazy kernel loading can synchronize the context on the first input event.
  // Preload just the kernels used by input callbacks, retaining lazy loading
  // for unrelated work and the small single-connection queue configuration.
  if (pump) {
    cudaFuncAttributes attributes;
    ck(cudaFuncGetAttributes(&attributes, mouse_kernel));
    ck(cudaFuncGetAttributes(&attributes, focus_kernel));
    ck(cudaFuncGetAttributes(&attributes, reset_replies));
    ck(cudaFuncGetAttributes(&attributes, follow_output_kernel));
    ck(cudaFuncGetAttributes(&attributes, clear_selection_kernel));
    ck(cudaFuncGetAttributes(&attributes, select_kernel));
    ck(cudaFuncGetAttributes(&attributes, selected_text_kernel));
    ck(cudaFuncGetAttributes(&attributes, set_selection_output_kernel));
    ck(cudaFuncGetAttributes(&attributes, scroll_view_kernel));
  }
  p->decode_pump = pump; p->pump_context = context;
}
}

namespace ct {
__global__ void cell_size_kernel(DeviceState *s, int width, int height) {
  s->cell_width = width; s->cell_height = height;
}
void Engine::set_cell_size(int width, int height) {
  if (width < 1 || width > 64 || height < 1 || height > 128)
    throw std::runtime_error("invalid cell dimensions");
  cell_size_kernel<<<1,1>>>(p->d, width, height);
  ck(cudaGetLastError());
}
}

namespace ct {
__global__ void face_kernel(DeviceState *s, const unsigned char *data,
                           FaceHeader h, size_t pages_offset, int style) {
  s->face_pixels[style] = data + 24;
  s->face_pages[style] = reinterpret_cast<const uint32_t *>(data + pages_offset);
  s->face_map[style] = s->face_pages[style] + 0x1100;
  s->face_width = h.width; s->face_height = h.height;
}
void Engine::load_face(const std::string &path) {
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  auto length = file.tellg();
  if (!file || length < 24 || length > 72 * 1024 * 1024)
    throw std::runtime_error("invalid font face size: " + path);
  std::array<std::vector<unsigned char>, 4> faces;
  faces[0].resize(static_cast<size_t>(length));
  file.seekg(0);
  if (!file.read(reinterpret_cast<char *>(faces[0].data()), faces[0].size()))
    throw std::runtime_error("cannot read font face: " + path);
  load_faces(faces);
}
__global__ void clear_face_kernel(DeviceState *s) {
  for (int i = 0; i < 4; ++i) { s->face_pixels[i] = nullptr; s->face_pages[i] = s->face_map[i] = nullptr; }
  s->face_width = s->face_height = 0;
}
void Engine::load_faces(const std::array<std::vector<unsigned char>, 4> &faces) {
  if (p->decoding) throw std::logic_error("cannot load font during decoding");
  if (faces[0].empty()) {
    clear_face_kernel<<<1,1>>>(p->d); ck(cudaGetLastError()); ck(cudaStreamSynchronize(nullptr));
    cudaFree(p->face); p->face = nullptr; p->face_bytes = 0; return;
  }
  std::array<FaceHeader, 4> headers;
  size_t offsets[4], page_offsets[4];
  size_t total = 0;
  for (int style = 0; style < 4; ++style) {
    const auto &data = faces[style].empty() ? faces[0] : faces[style];
    auto h = face_header(data.data(), data.size());
    if (style && (h.width != headers[0].width || h.height != headers[0].height))
      throw std::runtime_error("font style cell dimensions differ");
    size_t pages_offset = (24 + size_t(h.count) * h.width * 2 * h.height + 3) & ~size_t(3);
    size_t map_offset = pages_offset + 0x1100 * 4;
    if (data.size() != map_offset + size_t(h.pages) * 256 * 4)
      throw std::runtime_error("invalid font face payload");
    for (size_t i = pages_offset; i < data.size(); i += 4) {
      uint32_t index; std::memcpy(&index, data.data() + i, 4);
      if (index != 0xffffffffu && index >= (i < map_offset ? h.pages : h.count))
        throw std::runtime_error("invalid font face index");
    }
    headers[style] = h; page_offsets[style] = pages_offset;
    if (style && faces[style].empty()) offsets[style] = 0;
    else {
      offsets[style] = total;
      if (total + data.size() > 72 * 1024 * 1024)
        throw std::runtime_error("combined font atlas exceeds 72 MiB");
      total += data.size();
    }
  }
  unsigned char *next = nullptr;
  ck(cudaMalloc(&next, total));
  try {
    // Validate every face before allocation; copy directly into the final device
    // allocation instead of assembling another full atlas on the host.
    for (int style = 0; style < 4; ++style)
      if (!faces[style].empty())
        ck(cudaMemcpy(next + offsets[style], faces[style].data(), faces[style].size(), cudaMemcpyHostToDevice));
    for (int style = 0; style < 4; ++style)
      face_kernel<<<1,1>>>(p->d, next + offsets[style], headers[style], page_offsets[style], style);
    ck(cudaGetLastError());
    ck(cudaStreamSynchronize(nullptr));
  } catch (...) { cudaFree(next); throw; }
  cudaFree(p->face);
  p->face = next; p->face_bytes = total;
}
__global__ void presentation_kernel(DeviceState *s, int x, int y, int style) {
  s->padding_x = x; s->padding_y = y; s->default_cursor_style = style;
}
void Engine::set_presentation(int x, int y, int style) {
  if (x < 0 || y < 0 || x > 400 || y > 400 || style < 1 || style > 6)
    throw std::runtime_error("invalid presentation settings");
  presentation_kernel<<<1,1>>>(p->d, x, y, style);
  ck(cudaGetLastError());
}
__global__ void cursor_position_kernel(DeviceState *s, float x, float y) {
  s->cursor_x = x; s->cursor_y = y;
}
void Engine::set_cursor_position(float col, float row) {
  if (!(col >= 0 && col < MAX_COLS && row >= 0 && row < MAX_ROWS))
    throw std::runtime_error("invalid visual cursor position");
  cursor_position_kernel<<<1,1>>>(p->d, col, row);
  ck(cudaGetLastError());
}
__global__ void cursor_phase_kernel(DeviceState *s, int visible, int focused) {
  s->cursor_phase = visible; s->window_focused = focused;
}
void Engine::set_cursor_phase(bool visible, bool focused) {
  cursor_phase_kernel<<<1,1>>>(p->d, visible, focused);
  ck(cudaGetLastError());
}

}

namespace ct {
__global__ void opacity_kernel(DeviceState *s, unsigned alpha) { s->background_alpha = alpha; }
void Engine::set_background_opacity(float opacity) {
  if (!(opacity >= 0 && opacity <= 1)) throw std::runtime_error("invalid background opacity");
  opacity_kernel<<<1,1>>>(p->d, unsigned(opacity * 255 + 0.5f));
  ck(cudaGetLastError());
}
}
