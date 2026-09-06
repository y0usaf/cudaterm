// Included in the engine device namespace. Scratch exists only during search.
struct SearchWork {
  uint32_t query[256];
  int length, start, step, total;
  unsigned rank;
  int token;
  SearchMatch match;
};
__device__ Cell search_cell(const DeviceState &s, int row, int col) {
  return viewed_cell(s, row - (s.alt_active ? 0 : s.history_count) + s.view_offset, col);
}
__device__ int search_wrap(const DeviceState &s, int row) {
  return viewed_wrap(s, row - (s.alt_active ? 0 : s.history_count) + s.view_offset);
}
__device__ bool search_at(const DeviceState &s, const SearchWork &q, int token,
                          int &end_row, int &end_col) {
  int row = token / (s.cols * 4), col = token / 4 % s.cols, mark = token % 4;
  int rows = (s.alt_active ? 0 : s.history_count) + s.rows;
  for (int j = 0; j < q.length; ++j) {
    if (row >= rows) return false;
    int wrap = search_wrap(s, row);
    if (col >= (wrap ? wrap : s.cols)) return false;
    Cell v = search_cell(s, row, col);
    if (v.flags & TAIL) return false;
    uint32_t cp = mark ? v.combining[mark - 1] : v.cp;
    if (!cp || cp != q.query[j]) return false;
    end_row = row; end_col = col + ((v.flags & WIDE) ? 1 : 0);
    if (j + 1 == q.length) return true;
    if (mark < 3 && v.combining[mark]) { ++mark; continue; }
    mark = 0;
    col += (v.flags & WIDE) ? 2 : 1;
    if (col >= (wrap ? wrap : s.cols)) {
      if (!wrap) return false;
      ++row; col = 0;
    }
  }
  return false;
}
__global__ void find_search(const DeviceState *s, SearchWork *q) {
  int token = blockIdx.x * blockDim.x + threadIdx.x;
  if (token >= q->total) return;
  unsigned rank = q->step > 0 ? (token - q->start + q->total) % q->total
                              : (q->start - token + q->total) % q->total;
  int er, ec;
  if (search_at(*s, *q, token, er, ec)) atomicMin(&q->rank, rank);
}
__global__ void commit_search(DeviceState *s, SearchWork *q) {
  s->selection_active = 0;
  q->match = {false, false, 0, 0, 0, 0, s->view_offset};
  q->token = -1;
  if (q->rank == 0xffffffffu) return;
  int token = (q->start + q->step * int(q->rank) + q->total) % q->total;
  int sr = token / (s->cols * 4), sc = token / 4 % s->cols, er, ec;
  if (!search_at(*s, *q, token, er, ec)) return;
  int history = s->alt_active ? 0 : s->history_count;
  // Keep a fitting match above the prompt row whenever possible.
  int visible = dmax(1, s->rows - 1);
  int top = dmax(0, dmin(sr, er - visible + 1));
  s->view_offset = dmax(0, dmin(history, history - top));
  int origin = history - s->view_offset;
  s->selection_start_row = sr - origin; s->selection_start_col = sc;
  s->selection_end_row = er - origin; s->selection_end_col = ec;
  s->selection_active = 1;
  q->token = token;
  q->match = {true, false, sr - origin, sc, er - origin, ec, s->view_offset};
}
__global__ void search_prompt_cells(const DeviceState *s, const uint32_t *text,
                                    int length, Cell *cells) {
  for (int x = 0; x < MAX_COLS; ++x) cells[x] = {32, DEFAULT_BG, DEFAULT_FG, 0};
  int x = 0;
  for (int i = 0; i < length; ++i) {
    uint32_t cp = text[i];
    int width = s->text_widths[cp];
    if (!width) {
      int base = x - 1;
      if (base >= 0 && (cells[base].flags & TAIL)) --base;
      if (base >= 0) for (int m = 0; m < 3; ++m)
        if (!cells[base].combining[m]) { cells[base].combining[m] = cp; break; }
      continue;
    }
    if (x + width > s->cols) {
      if (x < s->cols) cells[x] = {0x2026, DEFAULT_BG, DEFAULT_FG, 0};
      break;
    }
    cells[x] = {cp, DEFAULT_BG, DEFAULT_FG, width == 2 ? WIDE : 0};
    if (width == 2) cells[x + 1] = {32, DEFAULT_BG, DEFAULT_FG, TAIL};
    x += width;
  }
}
