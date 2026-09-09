// Included inside the engine's device namespace after DeviceState is defined.
struct ReflowPlan {
  int source_rows, output_rows, cursor_pos, saved_pos, view_pos;
  int cursor_edge, saved_edge, screen_start;
};
__device__ Cell primary_cell(const DeviceState &s, int row, int col) {
  if (row < s.history_count) {
    int slot = (s.history_head - s.history_count + row + s.history_capacity) % s.history_capacity;
    return s.history[slot * s.history_cols + col];
  }
  int y = row - s.history_count;
  return s.alt_active ? s.alt[s.alt_rowmap[y] * s.cols + col]
                      : s.grid[at(s, y, col)];
}
__device__ int primary_wrap(const DeviceState &s, int row) {
  if (row < s.history_count)
    return s.history_wrap[(s.history_head - s.history_count + row + s.history_capacity) % s.history_capacity];
  int y = row - s.history_count;
  return s.alt_active ? s.alt_row_wrap[s.alt_rowmap[y]] : s.row_wrap[s.rowmap[y]];
}
__device__ bool reflow_blank(const Cell &v, const mark_pool::Arena &marks) {
  return v.cp == 32 && !v.reserved && v.fg == DEFAULT_FG && v.bg == DEFAULT_BG && !v.flags &&
         mark_pool::mark_count(v, marks) == 0;
}
struct ReflowRow {
  int used, wide, base, count;
};
// Determine padding and wide-cell presence with coalesced parallel reads.
__global__ void inspect_reflow_rows(const DeviceState *s, ReflowRow *info) {
  int y = blockIdx.x;
  if (y >= s->history_count + s->rows) return;
  int used = 0, wide = 0;
  for (int x = threadIdx.x; x < s->cols; x += blockDim.x) {
    Cell v = primary_cell(*s, y, x);
    if (!reflow_blank(v, s->marks)) used = dmax(used, x + 1);
    wide |= v.flags & (WIDE | TAIL);
  }
  for (int delta = 16; delta; delta >>= 1) {
    used = dmax(used, __shfl_down_sync(0xffffffffu, used, delta));
    wide |= __shfl_down_sync(0xffffffffu, wide, delta);
  }
  __shared__ int lengths[8], widths[8];
  if (!(threadIdx.x & 31)) { lengths[threadIdx.x / 32] = used; widths[threadIdx.x / 32] = wide; }
  __syncthreads();
  if (threadIdx.x == 0) {
    used = wide = 0;
    for (int i = 0; i < 8; ++i) { used = dmax(used, lengths[i]); wide |= widths[i]; }
    info[y] = {used, wide, 0, 0};
  }
}
__device__ int reflow_position(const ReflowRow *info, const int *map,
                                int row, int col, int old_cols) {
  if (col >= info[row].count) return -1;
  return info[row].wide ? map[row * old_cols + col] : info[row].base + col;
}
// Row planning is serial; single-width rows map arithmetically in the scatter.
// Only rows containing wide pairs need the per-cell planning fallback.
// Scratch is bounded by the input cells plus the retained output row count.
__global__ void plan_reflow(const DeviceState *s, int cols, int rows,
                            int *map, int *wrap, ReflowRow *info, ReflowPlan *p) {
  int cr = s->history_count + (s->alt_active ? s->main_row : s->row);
  int cc = s->alt_active ? s->main_col + s->main_wrap : s->col + s->wrap_pending;
  int sr = s->history_count + s->saved_row;
  int sc = s->saved_col + s->saved_pending;
  int last = dmax(cr, s->alt_active ? cr : sr);
  for (int y = s->history_count; y < s->history_count + s->rows; ++y)
    if (info[y].used) last = dmax(last, y);
  for (int i = 0; i < s->graphics->visible_count; ++i) {
    const auto &im = s->graphics->images[s->graphics->visible[i]];
    if (im.visible && !im.screen && im.py >= 0)
      last = dmax(last, dmin(s->history_count + s->rows - 1,
                            s->history_count + im.py / s->cell_height));
  }
  p->source_rows = last + 1;
  p->cursor_pos = p->saved_pos = p->view_pos = 0;
  p->cursor_edge = p->saved_edge = 0;
  int row = 0, col = 0, cap = HISTORY_CAP + rows, old_screen_pos = 0;
  for (int y = 0; y <= last; ++y) {
    int joined = primary_wrap(*s, y);
    int n = joined ? dmin(joined, s->cols) : info[y].used;
    if (!joined) {
      if (y == cr) n = dmax(n, cc);
      if (!s->alt_active && y == sr) n = dmax(n, sc);
    }
    for (int i = 0; i < s->graphics->visible_count; ++i) {
      const auto &im = s->graphics->images[s->graphics->visible[i]];
      int iy = im.py / s->cell_height - (im.py % s->cell_height < 0);
      if (im.visible && !im.screen && s->history_count + iy == y && im.px >= 0)
        n = dmax(n, dmin(s->cols, im.px / s->cell_width + 1));
    }
    if (y == s->history_count) old_screen_pos = row * cols + col;
    if (y == s->history_count - s->view_offset) p->view_pos = row * cols + col;
    info[y].base = row * cols + col;
    info[y].count = n;
    if (!info[y].wide) {
      if (y == cr && cc < n) p->cursor_pos = info[y].base + cc;
      if (!s->alt_active && y == sr && sc < n) p->saved_pos = info[y].base + sc;
      if (n) {
        int last_row = row + (col + n - 1) / cols;
        // Only the last retained wrap slots matter for an enormous line.
        for (int k = dmax(row, last_row - cap); k < last_row; ++k) wrap[k % cap] = cols;
        col = (col + n - 1) % cols + 1;
        row = last_row;
      }
    } else for (int x = 0; x < n; ++x) {
      Cell v = primary_cell(*s, y, x);
      if (v.flags & TAIL) continue;
      int width = (v.flags & WIDE) && cols > 1 ? 2 : 1;
      if (col + width > cols) {
        wrap[row % cap] = col;
        ++row; col = 0;
      }
      int pos = row * cols + col;
      if (y == cr && x == cc) p->cursor_pos = pos;
      if (!s->alt_active && y == sr && x == sc) p->saved_pos = pos;
      map[y * s->cols + x] = pos;
      if ((v.flags & WIDE) && x + 1 < n) {
        if (cols > 1) map[y * s->cols + x + 1] = pos + 1;
        if (y == cr && cc == x + 1) p->cursor_pos = pos + width - 1;
        if (!s->alt_active && y == sr && sc == x + 1) p->saved_pos = pos + width - 1;
      }
      col += width;
    }
    if (y == cr && cc >= n) { p->cursor_pos = row * cols + col; p->cursor_edge = col == cols; }
    if (!s->alt_active && y == sr && sc >= n) { p->saved_pos = row * cols + col; p->saved_edge = col == cols; }
    // Blank trailing cells remain coordinate anchors, but aren't scattered.
    if (!joined || y == last) {
      wrap[row % cap] = 0;
      ++row; col = 0;
    }
  }
  p->output_rows = row;
  // Keep existing blank space below the primary cursor. Widening must not
  // pull history into that space and move an otherwise stationary prompt.
  int anchor = dmax(0, old_screen_pos / cols - dmax(0, rows - s->rows));
  p->screen_start = dmax(dmax(0, row - rows), anchor);
}
__global__ void scatter_reflow(const DeviceState *s, const int *map,
                               const ReflowPlan *p, const ReflowRow *info, int cols, int rows,
                               Cell *a, Cell *b, Cell *history) {
  Cell *primary = s->alt_active ? b : a;
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= p->source_rows * s->cols) return;
  int pos = reflow_position(info, map, i / s->cols, i % s->cols, s->cols);
  if (pos < 0) return;
  int y = pos / cols, x = pos % cols;
  int start = p->screen_start, first = dmax(0, start - HISTORY_CAP);
  if (y < first) return;
  Cell v = primary_cell(*s, i / s->cols, i % s->cols);
  if (cols == 1 && (v.flags & WIDE)) { v.cp = 0xfffd; v.flags &= ~WIDE; }
  if (y < start) history[(y - first) * cols + x] = v;
  else primary[(y - start) * cols + x] = v;
}
__device__ void reflow_cursor_position(int pos, int edge, int cols, int rows, int start,
                                      int &row, int &col, int &pending) {
  pending = edge;
  row = pos / cols - pending - start;
  col = pending ? cols - 1 : pos % cols;
  if (row < 0 || row >= rows) pending = 0;
  row = dmax(0, dmin(row, rows - 1));
}
__global__ void initialize_reflow(const DeviceState *s, Cell *a, Cell *b,
                                  Cell *history, int cols, int rows, int capacity) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  Cell blank = {32, DEFAULT_FG, DEFAULT_BG, 0};
  if (i < capacity * cols) history[i] = blank;
  if (i >= rows * cols) return;
  Cell alternate = blank;
  int y = i / cols, x = i % cols;
  if (y < s->rows && x < s->cols) {
    alternate = s->alt_active ? s->grid[at(*s, y, x)]
                             : s->alt[s->alt_rowmap[y] * s->cols + x];
    if (x == cols - 1 && (alternate.flags & WIDE)) alternate = blank;
  }
  a[i] = s->alt_active ? alternate : blank;
  b[i] = s->alt_active ? blank : alternate;
}
__global__ void commit_reflow(DeviceState *s, Cell *a, Cell *b, Cell *h,
                              int *rw, int *arw, int *hw, const int *wrap,
                              const int *map, const ReflowPlan *p, const ReflowRow *info,
                              int cols, int rows, int capacity) {
  int start = p->screen_start, first = dmax(0, start - HISTORY_CAP);
  int count = start - first;
  for (int y = 0; y < count; ++y) hw[y] = wrap[(first + y) % (HISTORY_CAP + rows)];
  for (int y = 0; y < rows; ++y) {
    int primary = start + y < p->output_rows ? wrap[(start + y) % (HISTORY_CAP + rows)] : 0;
    int alternate = y < s->rows ? (s->alt_active ? s->row_wrap[s->rowmap[y]]
                                      : s->alt_row_wrap[s->alt_rowmap[y]]) : 0;
    if (alternate > cols) alternate = cols;
    rw[y] = s->alt_active ? alternate : primary;
    arw[y] = s->alt_active ? primary : alternate;
  }
  // Images retain pixel allocations and intra-cell offsets. Evicted anchors
  // become hidden, just as they do when scrolling out of retained history.
  auto &g = *s->graphics;
  g.visible_count = 0;
  for (int i = 0; i < IMAGE_SLOTS; ++i) {
    auto &im = g.images[i];
    if (im.visible && im.screen == 0) {
      int y = im.py / s->cell_height - (im.py % s->cell_height < 0);
      int x = im.px / s->cell_width - (im.px % s->cell_width < 0);
      int source = s->history_count + y;
      int pos = source >= 0 && source < p->source_rows && x >= 0 && x < s->cols
                  ? reflow_position(info, map, source, x, s->cols) : -1;
      if (pos < 0 || pos / cols < first) im.visible = 0;
      else {
        im.px = (pos % cols) * s->cell_width + im.px - x * s->cell_width;
        im.py = (pos / cols - start) * s->cell_height + im.py - y * s->cell_height;
      }
    }
    if (im.visible) g.visible[g.visible_count++] = i;
  }
  if (s->alt_active) {
    reflow_cursor_position(p->cursor_pos, p->cursor_edge, cols, rows, start,
                           s->main_row, s->main_col, s->main_wrap);
    s->row = dmin(s->row, rows - 1); s->col = dmin(s->col, cols - 1);
    if (cols != s->cols) s->wrap_pending = 0;
    s->saved_row = dmin(s->saved_row, rows - 1); s->saved_col = dmin(s->saved_col, cols - 1);
    if (cols != s->cols) s->saved_pending = 0;
  } else {
    reflow_cursor_position(p->cursor_pos, p->cursor_edge, cols, rows, start,
                           s->row, s->col, s->wrap_pending);
    reflow_cursor_position(p->saved_pos, p->saved_edge, cols, rows, start,
                           s->saved_row, s->saved_col, s->saved_pending);
  }
  s->view_offset = s->view_offset ? dmax(0, dmin(count, start - p->view_pos / cols)) : 0;
  s->grid = a; s->alt = b; s->history = h;
  s->row_wrap = rw; s->alt_row_wrap = arw; s->history_wrap = hw;
  for (int i = 0; i < rows; ++i) s->rowmap[i] = s->alt_rowmap[i] = i;
  s->cols = s->history_cols = cols; s->rows = rows;
  s->history_count = count; s->history_capacity = capacity; s->history_head = count % capacity;
  s->top = s->main_top = 0; s->bottom = s->main_bottom = rows - 1;
  s->selection_active = 0;
}
