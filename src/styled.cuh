// Parallel layout for bounded UTF-8/SGR lines. Unsupported input stays on the
// general VT path; all eligibility checks and parsing happen on the device.
struct LinePen {
  uint32_t fg, bg, flags;
  int params[16], csi_n;
};
struct LineScan {
  int rows, col, pending;
  uint32_t fg, bg, zero, one, wide;
};
__host__ __device__ LineScan line_identity() {
  return {0, -1, 0, 0xffffffffu, 0xffffffffu, 0, 15, 0};
}
struct JoinLines {
  __host__ __device__ LineScan operator()(LineScan a, LineScan b) const {
    return {a.rows + b.rows,
            b.col >= 0 ? b.col : a.col,
            b.col >= 0 ? b.pending : a.pending,
            b.fg != 0xffffffffu ? b.fg : a.fg,
            b.bg != 0xffffffffu ? b.bg : a.bg,
            (a.zero & b.one) | (~a.zero & b.zero),
            (a.one & b.one) | (~a.one & b.zero),
            a.wide | b.wide};
  }
};
struct StyledMeta {
  int row, col, pending, scroll;
  uint32_t fg, bg, flags;
  int history_base;
};
__device__ int read_sgr(LinePen &p, const unsigned char *b, int n, int i) {
  if (i + 1 >= n || b[i] != 27 || b[i + 1] != '[')
    return -1;
  p.csi_n = 0;
  p.params[0] = 0;
  for (i += 2; i < n; ++i) {
    unsigned char c = b[i];
    if (c >= '0' && c <= '9')
      p.params[p.csi_n] = dmin(1000000, p.params[p.csi_n] * 10 + c - '0');
    else if (c == ';' && p.csi_n < 15)
      p.params[++p.csi_n] = 0;
    else if (c == 'm')
      return i + 1;
    else
      return -1;
  }
  return -1;
}
// Invalid or incomplete scalars reject the line without mutating terminal
// state; the streaming interpreter then handles its exact recovery semantics.
__device__ int read_scalar(const unsigned char *b, int n, int i, uint32_t &cp) {
  unsigned char c = b[i++];
  if (c >= 32 && c < 127) {
    cp = c;
    return i;
  }
  int need;
  uint32_t minimum;
  if (c >= 0xc2 && c <= 0xdf) {
    cp = c & 31;
    need = 1;
    minimum = 0x80;
  } else if (c >= 0xe0 && c <= 0xef) {
    cp = c & 15;
    need = 2;
    minimum = 0x800;
  } else if (c >= 0xf0 && c <= 0xf4) {
    cp = c & 7;
    need = 3;
    minimum = 0x10000;
  } else
    return -1;
  while (need--) {
    if (i >= n || (b[i] & 0xc0) != 0x80)
      return -1;
    cp = (cp << 6) | (b[i++] & 63);
  }
  return cp < minimum || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff) ? -1
                                                                         : i;
}
__device__ int line_tabcol(const DeviceState *s, int col) {
  int current = dmin(s->cols - 1, dmax(0, col));
  for (int next = current + 1; next < s->cols; ++next)
    if (s->tabs[next])
      return next;
  return s->cols - 1;
}
// Complete inline sequences can be laid out before painting. A suffix whose
// base was emitted by another feed still belongs to the streaming interpreter.
__device__ bool inline_vs16(uint32_t cp, const unsigned char *b, int pos, int n) {
  return pos + 3 <= n && b[pos] == 0xef && b[pos + 1] == 0xb8 &&
         b[pos + 2] == 0x8f && emoji_vs16_base(cp);
}
__device__ bool inline_modifier(uint32_t cp, const unsigned char *b, int pos, int n) {
  if (pos + 3 <= n && b[pos] == 0xef && b[pos + 1] == 0xb8 && b[pos + 2] == 0x8f)
    pos += 3;
  return pos + 4 <= n && b[pos] == 0xf0 && b[pos + 1] == 0x9f &&
         b[pos + 2] == 0x8f && b[pos + 3] >= 0xbb && b[pos + 3] <= 0xbf &&
         emoji_modifier_base(cp);
}
__global__ void styled_lines(const DeviceState *s, const unsigned char *b,
                             int n, LineScan *scan, int *limit) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n)
    return;
  scan[i] = line_identity();
  if (i && b[i - 1] != '\n')
    return;
  LinePen p{0xffffffffu, 0xffffffffu, 0, {}, 0};
  uint32_t one = 15;
  int pos = i, rows = 0;
  int col = i == 0 ? (s->wrap_pending ? s->cols : s->col) : 0;
  uint32_t wide = 0;
  bool newline = false, inline_selector = false, modifier_ready = false;
  int marks = 0;
  bool have_base = false;
  while (pos < n) {
    if (pos - i >= 4096) {
      atomicMin(limit, i);
      return;
    }
    unsigned char c = b[pos];
    if (c == '\t') {
      have_base = false;
      col = line_tabcol(s, col);
      ++pos;
    } else if (c == 27) {
      int end = read_sgr(p, b, dmin(n, i + 4096), pos);
      if (end < 0) {
        atomicMin(limit, i);
        return;
      }
      apply_sgr(p, one);
      pos = end;
    } else if (c == '\r') {
      // Repeated CRs before LF have the same layout as one CRLF. PTY output
      // processing can produce these when an application writes CRLF itself.
      int end = pos;
      while (end < dmin(n, i + 4096) && b[end] == '\r')
        ++end;
      if (end == dmin(n, i + 4096) || b[end] != '\n') {
        atomicMin(limit, i);
        return;
      }
      newline = true;
      break;
    } else if (c == '\n' && pos == 0 && s->col == 0 && !s->wrap_pending) {
      newline = true;
      break;
    } else {
      uint32_t cp;
      int end = read_scalar(b, dmin(n, i + 4096), pos, cp);
      if (end < 0) {
        atomicMin(limit, i);
        return;
      }
      pos = end;
      // ZWJ joins need the scalar interpreter: styled_lines has no suffix
      // arena transaction and cannot safely promote the preceding cell.
      // A leading pictograph may also join a stored ZWJ at a feed boundary.
      bool leading_join = i == 0 && !have_base && zwj_attachment(*s, cp);
      if (cp == 0x200d || leading_join) {
        atomicMin(limit, i);
        return;
      }
      bool modifier_tone = false;
      if (cp >= 0x1f3fb && cp <= 0x1f3ff) {
        if (!modifier_ready || s->cols == 1) { atomicMin(limit, i); return; }
        modifier_tone = true;
        modifier_ready = false;
      } else if (cp == 0xfe0f && modifier_ready) {
      } else {
        modifier_ready = inline_modifier(cp, b, pos, dmin(n, i + 4096));
      }
      if (cp == 0xfe0f && !inline_selector && !modifier_ready) {
        atomicMin(limit, i);
        return;
      }
      inline_selector = inline_vs16(cp, b, pos, dmin(n, i + 4096));
      int width = cp < 127 ? 1 : s->text_widths[cp];
      if (modifier_tone) width = 0;
      if (width == 1 && s->cols > 1 && (inline_selector || modifier_ready)) width = 2;
      if (width == 2 && s->cols == 1)
        width = 1;
      if (!width) {
        ++marks;
        // A line beginning with a mark may attach to a base from an earlier
        // feed; conservatively send that line through the scalar interpreter.
        if (marks > 3 || !have_base) {
          atomicMin(limit, i);
          return;
        }
      } else {
        marks = 0; have_base = true;
      }
      if (width) {
        if (col == s->cols || (width == 2 && col == s->cols - 1)) {
          ++rows;
          col = 0;
        }
        col += width;
        wide |= width == 2;
      }
    }
  }
  // A control-only fragment must preserve a preceding cursor-control barrier.
  // Let the interpreter handle it rather than committing fictitious new text.
  if (!have_base && !newline) { atomicMin(limit, i); return; }
  if (newline) {
    ++rows;
    col = 0;
  }
  scan[i] = {rows,
             dmin(s->cols - 1, col),
             !newline && col == s->cols,
             p.fg,
             p.bg,
             p.flags,
             one,
             wide};
}
__global__ void styled_commit(DeviceState *s, const unsigned char *b,
                              const LineScan *scan, const int *limit, int *done,
                              StyledMeta *meta, int *plain_rejected) {
  int n = *limit;
  if (n < 256)
    return;
  LineScan total = scan[n - 1];
  *meta = {s->row, s->col, s->wrap_pending, 0, s->fg, s->bg, s->flags};
  int scroll = dmax(0, s->row + total.rows - s->rows + 1);
  meta->scroll = scroll;
  graphics_scroll(*s, 0, s->rows - 1, scroll);
  meta->history_base = reserve_history(*s, scroll);
  rotate_rows(s->rowmap, s->rows, scroll);
  s->row = dmin(s->rows - 1, s->row + total.rows);
  s->complex_cells |= total.wide;
  s->col = total.col;
  s->wrap_pending = total.pending;
  if (total.fg != 0xffffffffu)
    s->fg = total.fg;
  if (total.bg != 0xffffffffu)
    s->bg = total.bg;
  s->flags = (s->flags & total.one) | (~s->flags & total.zero);
  s->join_blocked = 0;
  *done = n;
  *plain_rejected = 0;
}
__device__ void styled_clear(DeviceState *s, int logical, const StyledMeta &m,
                             const LinePen &p) {
  Cell *target = bulk_row(*s, logical, m.scroll, m.history_base);
  if (logical >= s->rows && target) {
    int *w = bulk_wrap(*s, logical, m.scroll, m.history_base); if (w) *w = 0;
  }
  // prepare_history already blanked new history rows with the final pen.
  if (m.history_base >= 0 && logical < m.scroll && p.fg == s->fg &&
      p.bg == s->bg)
    return;
  if (logical >= s->rows && target)
    for (int c = 0; c < s->cols; ++c)
      clear_cell(target[c], p.fg, p.bg);
}
__global__ void styled_paint(DeviceState *s, const unsigned char *b, int n,
                             const LineScan *scan, const int *done,
                             const StyledMeta *meta) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  n = *done;
  if (i >= n || (i && b[i - 1] != '\n'))
    return;
  if (!i && b[n - 1] == '\n' && meta->row + scan[n - 1].rows >= s->rows)
    for (int c = 0; c < s->cols; ++c)
      clear_cell(s->grid[at(*s, s->row, c)], s->fg, s->bg);
  if (!i && b[n - 1] == '\n' && meta->row + scan[n - 1].rows >= s->rows)
    s->row_wrap[s->rowmap[s->row]] = 0;
  StyledMeta m = *meta;
  LineScan before = i ? scan[i - 1] : line_identity();
  int logical = m.row + before.rows;
  LinePen p{before.fg == 0xffffffffu ? m.fg : before.fg,
            before.bg == 0xffffffffu ? m.bg : before.bg,
            (m.flags & before.one) | (~m.flags & before.zero),
            {},
            0};
  int col = i == 0 ? (m.pending ? s->cols : m.col) : 0;
  if (i)
    styled_clear(s, logical, m, p);
  int pos = i;
  bool modifier_ready = false;
  for (; pos < n;) {
    unsigned char c = b[pos];
    if (c == '\r' || c == '\n')
      break;
    if (c == '\t') {
      col = line_tabcol(s, col);
      ++pos;
      continue;
    }
    if (c == 27) {
      pos = read_sgr(p, b, n, pos);
      apply_sgr(p);
      continue;
    }
    uint32_t cp;
    pos = read_scalar(b, n, pos, cp);
    bool modifier_tone = cp >= 0x1f3fb && cp <= 0x1f3ff && modifier_ready;
    if (modifier_tone)
      modifier_ready = false;
    else if (cp != 0xfe0f || !modifier_ready)
      modifier_ready = inline_modifier(cp, b, pos, n);
    bool graphic = active_graphics(*s) && cp >= 0x5f && cp <= 0x7e;
    int width = cp < 127 ? 1 : s->text_widths[cp];
    if (width == 1 && s->cols > 1 &&
        (inline_vs16(cp, b, pos, n) || modifier_ready)) width = 2;
    if (modifier_tone) width = 0;
    if (graphic)
      cp = dec_graphic(cp);
    if (width == 2 && s->cols == 1) {
      width = 1;
      cp = 0xfffd;
    }
    Cell *target = bulk_row(*s, logical, m.scroll, m.history_base);
    if (!width) {
      if (target) {
        int previous = dmax(0, col - 1);
        if ((target[previous].flags & TAIL) && previous > 0)
          --previous;
        Cell &cell = target[previous];
        if (!mark_pool::append_mark(cell, cp, s->marks))
          s->pool_wait = 1;
      }
      continue;
    }
    bool earlywide = width == 2 && col == s->cols - 1;
    if (earlywide) {
      if (target) {
        if ((target[col].flags & TAIL) && col > 0)
          clear_cell(target[col - 1], p.fg, p.bg);
        clear_cell(target[col], p.fg, p.bg);
      }
      col = s->cols;
    }
    if (col == s->cols) {
      int *w = bulk_wrap(*s, logical, m.scroll, m.history_base);
      if (w) *w = earlywide ? s->cols - 1 : s->cols;
      col = 0;
      ++logical;
      styled_clear(s, logical, m, p);
    }
    target = bulk_row(*s, logical, m.scroll, m.history_base);
    if (target) {
      for (int k = 0; k < width; ++k) {
        uint32_t old = target[col + k].flags;
        if ((old & TAIL) && col + k > 0)
          clear_cell(target[col + k - 1], p.fg, p.bg);
        if ((old & WIDE) && col + k + 1 < s->cols)
          clear_cell(target[col + k + 1], p.fg, p.bg);
      }
      target[col] = {cp, p.fg, p.bg, p.flags | (width == 2 ? WIDE : 0), {}, cp == 32};
      if (width == 2)
        target[col + 1] = {0, p.fg, p.bg, p.flags | TAIL};
    }
    col += width;
    if (col == s->cols) {
      int *w = bulk_wrap(*s, logical, m.scroll, m.history_base);
      if (w) *w = 0;
    }
  }
  Cell *last = bulk_row(*s, logical, m.scroll, m.history_base);
  bool hard = pos < n && b[pos] == '\n';
  if (!hard && pos < n && b[pos] == '\r') {
    int q = pos; while (q < n && b[q] == '\r') ++q;
    hard = q < n && b[q] == '\n';
  }
  if (last && hard) { int *w = bulk_wrap(*s, logical, m.scroll, m.history_base); if (w) *w = 0; }
}
