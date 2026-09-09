// Included in the engine device namespace. Scratch exists only during search.
struct SearchWork {
  uint32_t query[512];
  int length, step, cells;
  unsigned long long start, total, rank, token;
  SearchMatch match;
};
__device__ Cell search_cell(const DeviceState &s, int row, int col) {
  return viewed_cell(s, row - (s.alt_active ? 0 : s.history_count) + s.view_offset, col);
}
__device__ int search_wrap(const DeviceState &s, int row) {
  return viewed_wrap(s, row - (s.alt_active ? 0 : s.history_count) + s.view_offset);
}
__device__ bool search_at(const DeviceState &s, const SearchWork &q, unsigned long long token,
                          int &end_row, int &end_col) {
  int cell = int(token >> 32), row = cell / s.cols, col = cell % s.cols;
  uint32_t mark = uint32_t(token);
  int rows = (s.alt_active ? 0 : s.history_count) + s.rows;
  for (int j = 0; j < q.length; ++j) {
    if (row >= rows) return false;
    int wrap = search_wrap(s, row);
    if (col >= (wrap ? wrap : s.cols)) return false;
    Cell v = search_cell(s, row, col);
    if (v.flags & TAIL) return false;
    uint32_t cp = v.cp;
    if (mark && !mark_pool::mark_at(v, s.marks, mark - 1, cp)) return false;
    if (!cp || cp != q.query[j]) return false;
    end_row = row; end_col = col + ((v.flags & WIDE) ? 1 : 0);
    if (j + 1 == q.length) return true;
    if (mark < mark_pool::mark_count(v, s.marks)) { ++mark; continue; }
    mark = 0;
    col += (v.flags & WIDE) ? 2 : 1;
    if (col >= (wrap ? wrap : s.cols)) {
      if (!wrap) return false;
      ++row; col = 0;
    }
  }
  return false;
}
__device__ void consider_search(const DeviceState &s, SearchWork &q,
                                  unsigned long long token, uint32_t cp) {
  if (cp != q.query[0]) return;
  unsigned long long rank = q.step > 0 ? (token + q.total - q.start) % q.total
                                     : (q.start + q.total - token) % q.total;
  int er, ec;
  if (search_at(s, q, token, er, ec)) atomicMin(&q.rank, rank);
}
__global__ void find_search(const DeviceState *s, SearchWork *q) {
  int cell = blockIdx.x * blockDim.x + threadIdx.x;
  if (cell >= q->cells) return;
  Cell v = search_cell(*s, cell / s->cols, cell % s->cols);
  if (v.flags & TAIL) return;
  unsigned long long token = (unsigned long long)cell << 32;
  consider_search(*s, *q, token, v.cp);
  for (int i = 0; i < 3 && v.combining[i]; ++i)
    consider_search(*s, *q, token + i + 1, v.combining[i]);
  uint32_t ref = mark_pool::head(v);
  uint32_t ordinal = mark_pool::mark_count(v, s->marks);
  while (ref) {
    if (ref > *s->marks.used || s->marks.nodes[ref - 1].parent >= ref) {
      *s->marks.status = mark_pool::MALFORMED; return;
    }
    const auto node = s->marks.nodes[ref - 1];
    consider_search(*s, *q, token + ordinal--, node.cp);
    ref = node.parent;
  }
}
__global__ void commit_search(DeviceState *s, SearchWork *q) {
  s->selection_active = 0;
  q->match = {false, false, 0, 0, 0, 0, s->view_offset};
  q->token = ~0ull;
  if (q->rank == ~0ull) return;
  auto token = q->step > 0 ? (q->start + q->rank) % q->total
                           : (q->start + q->total - q->rank) % q->total;
  int cell = int(token >> 32), sr = cell / s->cols, sc = cell % s->cols, er, ec;
  if (!search_at(*s, *q, token, er, ec)) return;
  int history = s->alt_active ? 0 : s->history_count;
  // Keep a fitting match above the prompt row whenever possible.
  int visible = dmax(1, s->rows - 1);
  int top = dmax(0, dmin(sr, er - visible + 1));
  s->view_offset = dmax(0, dmin(history, history - top));
  int origin = history - s->view_offset;
  s->selection_start_row = sr - origin; s->selection_start_col = sc;
  s->selection_end_row = er - origin; s->selection_end_col = ec;
  s->selection_rectangle = 0;
  s->selection_active = 1;
  q->token = token;
  q->match = {true, false, sr - origin, sc, er - origin, ec, s->view_offset};
}
__device__ bool prompt_zwj_lookahead(const uint32_t *text, int i, int length) {
  if (!grapheme_extended_pictographic(text[i])) return false;
  int j = i + 1;
  while (j < length && grapheme_extend(text[j])) ++j;
  return j + 1 < length && text[j] == 0x200d &&
         grapheme_extended_pictographic(text[j + 1]);
}
__global__ void search_prompt_cells(const DeviceState *s, const uint32_t *text,
                                    int length, Cell *cells, bool count_only) {
  if (!count_only) for (int x = 0; x < MAX_COLS; ++x) cells[x] = {32, DEFAULT_BG, DEFAULT_FG, 0};
  int x = 0, marks = 0;
  uint32_t needed = 0;
  bool modifier_ready = false;
  bool ep_extend_suffix = false, zwj_joinable = false;
  for (int i = 0; i < length; ++i) {
    uint32_t cp = text[i];
    int width = s->text_widths[cp];
    // Prompt input is complete, so determine presentation before truncation.
    if (width == 1 && i + 1 < length && text[i + 1] == 0xfe0f &&
        emoji_vs16_base(cp)) width = 2;
    bool zwj_join = grapheme_extended_pictographic(cp) && zwj_joinable;
    if (zwj_join) width = 0;
    if (!zwj_join && prompt_zwj_lookahead(text, i, length)) width = 2;
    bool modifier_tone = cp >= 0x1f3fb && cp <= 0x1f3ff && modifier_ready;
    if (modifier_tone) {
      width = 0;
      modifier_ready = false;
    } else if (cp == 0xfe0f && modifier_ready) {
    } else {
      int next = i + 1;
      if (next < length && text[next] == 0xfe0f) ++next;
      modifier_ready = next < length && text[next] >= 0x1f3fb &&
                       text[next] <= 0x1f3ff && emoji_modifier_base(cp);
    }
    if (width == 1 && modifier_ready) width = 2;
    if (!width) {
      if (x > 0) {
        if (marks++ >= 3) ++needed;
        if (!count_only) {
          int base = x - 1;
          if (cells[base].flags & TAIL) --base;
          if (!mark_pool::append_mark(cells[base], cp, s->marks)) return;
        }
      }
    } else {
      if (x + width > s->cols) {
        if (!count_only && x < s->cols) cells[x] = {0x2026, DEFAULT_BG, DEFAULT_FG, 0};
        break;
      }
      if (!count_only) {
        cells[x] = {cp, DEFAULT_BG, DEFAULT_FG, width == 2 ? WIDE : 0};
        if (width == 2) cells[x + 1] = {32, DEFAULT_BG, DEFAULT_FG, TAIL};
      }
      x += width; marks = 0;
    }
    if (cp == 0x200d) {
      zwj_joinable = ep_extend_suffix;
      ep_extend_suffix = false;
    }
    else {
      if (!grapheme_extend(cp)) ep_extend_suffix = grapheme_extended_pictographic(cp);
      zwj_joinable = false; // Extend after ZWJ cannot satisfy GB11.
    }
  }
  if (count_only) *s->marks.status = needed;
}
