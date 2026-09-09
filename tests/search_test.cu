#include "engine.cuh"
#include <cuda_runtime.h>
#include <algorithm>
#include <random>
#include <utility>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>
using ct::Engine;
using ct::SearchDirection;
static void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}
static void check(bool value, const char *message) {
  if (!value) throw std::runtime_error(message);
}
static void unicode_and_boundaries() {
  Engine e(4, 3);
  feed(e, "abc中e\xCC\x81" "def");
  check(e.search("中e\xCC\x81", SearchDirection::Backward, true).found, "wrapped Unicode search");
  check(e.selected_text() == "中e\xCC\x81", "wide/combining copied match");
  check(!e.search("中é", SearchDirection::Backward, true).found, "exact codepoints, no normalization");
  Engine hard(8, 3);
  feed(hard, "abc\r\ndef");
  check(!hard.search("cde", SearchDirection::Backward, true).found, "hard break barrier");
  Engine long_match(1, 2);
  std::string query(256, 'x');
  feed(long_match, query);
  check(long_match.search(query, SearchDirection::Backward, true).found, "match longer than viewport");
  check(long_match.selected_text() == query, "copy entire offscreen match");
}
static void repeat_and_invalidation() {
  Engine e(8, 3);
  feed(e, "x x x");
  for (int col : {4, 2, 0, 4}) {
    auto m = e.search("x", SearchDirection::Backward);
    check(m.found && m.start_col == col, "backward order and wrap");
  }
  check(e.search("x", SearchDirection::Forward).start_col == 0, "reverse direction wraps");
  check(e.search("x", SearchDirection::Forward).start_col == 2, "forward order");
  feed(e, "needle");
  check(e.search("x", SearchDirection::Backward).invalidated, "feed invalidation");
  check(e.search("needle", SearchDirection::Backward, true).found, "restart after feed");
  e.resize(4, 3);
  check(e.search("needle", SearchDirection::Backward).invalidated, "resize invalidation");
  check(e.search("needle", SearchDirection::Backward, true).found, "restart after reflow");
  e.clear_search();
  check(e.selected_text().empty(), "clear highlight");
}
static void history_and_alternate() {
  Engine e(8, 3);
  feed(e, "primary\r\n" + std::string(80, 'x'));
  auto m = e.search("primary", SearchDirection::Backward, true);
  check(m.found && m.view_offset > 0, "primary history search");
  check(!e.search("Primary", SearchDirection::Backward, true).found, "case sensitive");
  feed(e, "\x1b[?1049h\x1b[Haltneedle");
  check(e.search("altneedle", SearchDirection::Backward, true).found, "alternate active grid");
  check(!e.search("primary", SearchDirection::Backward, true).found, "alternate excludes primary history");
  feed(e, "\x1b[?1049l");
  check(e.search("primary", SearchDirection::Backward, true).found, "primary survives alternate");
  std::string flood;
  for (int i = 0; i < 6000; ++i) flood += "x\r\n";
  feed(e, flood);
  check(!e.search("primary", SearchDirection::Backward, true).found, "evicted history absent");
}
static void prompt_and_cleanup() {
  Engine e(80, 24);
  feed(e, "content");
  auto cells = e.cells();
  auto baseline = e.memory_usage().device_bytes;
  std::vector<uint32_t> before(80 * 8 * 24 * 16), after(before.size());
  uint32_t *pixels = nullptr;
  check(cudaMalloc(&pixels, before.size() * 4) == cudaSuccess, "pixel allocation");
  e.search("content", SearchDirection::Backward, true);
  e.render(pixels, 80 * 8, 24 * 16);
  check(cudaMemcpy(before.data(), pixels, before.size() * 4, cudaMemcpyDeviceToHost) == cudaSuccess, "baseline render");
  e.set_search_prompt("Search: content 中e\xCC\x81");
  e.render(pixels, 80 * 8, 24 * 16);
  check(cudaMemcpy(after.data(), pixels, after.size() * 4, cudaMemcpyDeviceToHost) == cudaSuccess, "prompt render");
  size_t boundary = 80 * 8 * 23 * 16;
  check(std::memcmp(before.data(), after.data(), boundary * 4) == 0, "prompt only overlays bottom row");
  check(std::memcmp(before.data() + boundary, after.data() + boundary, (before.size() - boundary) * 4) != 0, "prompt visible in CUDA pixels");
  e.set_search_prompt("  X");
  e.render(pixels, 80 * 8, 24 * 16);
  check(cudaMemcpy(before.data(), pixels, before.size() * 4, cudaMemcpyDeviceToHost) == cudaSuccess, "prompt marker reference");
  for (const std::string text : {std::string("\u2764\ufe0fX"), std::string("1\ufe0f\u20e3X"), std::string("👍🏽X"),
                                 std::string("☝🏽X"), std::string("☝️🏽X"),
                                 std::string("👩‍💻X"), std::string("👩́‍💻X"),
                                 std::string("❤‍🔥X"), std::string("©‍®X")}) {
    e.set_search_prompt(text);
    e.render(pixels, 80 * 8, 24 * 16);
    check(cudaMemcpy(after.data(), pixels, after.size() * 4, cudaMemcpyDeviceToHost) == cudaSuccess, "emoji prompt render");
    for (int y = 23 * 16; y < 24 * 16; ++y)
      for (int x = 2 * 8; x < 4 * 8; ++x)
        check(before[y * 80 * 8 + x] == after[y * 80 * 8 + x],
              "prompt places following X after two-cell emoji sequence");
  }
  e.set_search_prompt("    X"); e.render(pixels, 80 * 8, 24 * 16);
  check(cudaMemcpy(before.data(), pixels, before.size() * 4, cudaMemcpyDeviceToHost) == cudaSuccess,
        "negative GB11 reference render");
  for (const std::string text : {std::string("👩‍́💻X"), std::string("👩‍‍💻X")}) {
    e.set_search_prompt(text); e.render(pixels, 80 * 8, 24 * 16);
    check(cudaMemcpy(after.data(), pixels, after.size() * 4, cudaMemcpyDeviceToHost) == cudaSuccess,
          "negative GB11 prompt render");
    for (int y = 23 * 16; y < 24 * 16; ++y)
      for (int x = 4 * 8; x < 6 * 8; ++x)
        check(before[y * 80 * 8 + x] == after[y * 80 * 8 + x], "negative GB11 prompt width");
  }
  e.set_search_prompt(std::string(79, ' ') + "…"); e.render(pixels, 80 * 8, 24 * 16);
  check(cudaMemcpy(before.data(), pixels, before.size() * 4, cudaMemcpyDeviceToHost) == cudaSuccess,
        "GB11 prompt truncation reference");
  e.set_search_prompt(std::string(79, ' ') + "©‍®X"); e.render(pixels, 80 * 8, 24 * 16);
  check(cudaMemcpy(after.data(), pixels, after.size() * 4, cudaMemcpyDeviceToHost) == cudaSuccess,
        "GB11 prompt truncation render");
  check(std::memcmp(before.data(), after.data(), before.size() * 4) == 0,
        "narrow GB11 prompt reserves width before truncation");
  auto final_cells = e.cells();
  check(std::memcmp(cells.data(), final_cells.data(), cells.size() * sizeof(ct::Cell)) == 0, "search/prompt leave terminal cells unchanged");
  e.set_search_prompt("");
  e.clear_search();
  check(e.memory_usage().device_bytes == baseline, "search and prompt allocations released");
  cudaFree(pixels);
}
static void invalid_queries() {
  Engine e(4, 2);
  for (const std::string &q : {std::string("\x80"), std::string("\xED\xA0\x80"),
       std::string("\xF4\x90\x80\x80"), std::string("\xE0\x80\x80"), std::string(513, 'x')}) {
    bool threw = false;
    try { e.search(q, SearchDirection::Forward, true); }
    catch (const std::invalid_argument &) { threw = true; }
    check(threw, "reject invalid/oversized query");
  }
  check(!e.search("", SearchDirection::Backward, true).found, "empty query clears");
}
static std::string encode(const std::vector<uint32_t> &points) {
  std::string text;
  for (uint32_t cp : points) {
    if (cp < 128) text += char(cp);
    else if (cp < 2048) {
      text += char(0xc0 | cp >> 6); text += char(0x80 | (cp & 63));
    } else {
      text += char(0xe0 | cp >> 12); text += char(0x80 | (cp >> 6 & 63));
      text += char(0x80 | (cp & 63));
    }
  }
  return text;
}
// The oracle searches original logical strings with std::search, not GPU cell
// traversal. Layout uses only known widths in this deliberately small alphabet.
static void logical_corpus_oracle() {
  struct Line {
    std::vector<uint32_t> points;
    std::vector<std::pair<int, int>> positions;
  };
  Engine e(17, 5);
  std::mt19937 random(4219);
  std::vector<Line> lines;
  std::string output;
  int row = 0;
  for (int n = 0; n < 40; ++n) {
    Line line;
    int col = 0;
    for (int i = 0; i < 53; ++i) {
      uint32_t cp = "abce"[random() % 4];
      if (random() % 4 == 0) cp = 0x4e2d;
      int width = cp == 0x4e2d ? 2 : 1;
      if (col + width > 17) { ++row; col = 0; }
      line.points.push_back(cp); line.positions.emplace_back(row, col);
      if (cp == 'e') {
        line.points.push_back(0x301); line.positions.emplace_back(row, col);
      }
      col += width;
    }
    output += encode(line.points) + "\r\n";
    lines.push_back(std::move(line)); ++row;
  }
  feed(e, output);
  const std::vector<std::vector<uint32_t>> queries = {
    {'a','b'}, {0x4e2d,'a'}, {'e',0x301,'a'}, {'a','a','a','a'}, {'Q'}
  };
  for (const auto &query : queries) {
    std::vector<std::pair<int, int>> expected;
    for (const auto &line : lines) {
      auto begin = line.points.begin();
      while (begin != line.points.end()) {
        auto match = std::search(begin, line.points.end(), query.begin(), query.end());
        if (match == line.points.end()) break;
        expected.push_back(line.positions[match - line.points.begin()]);
        begin = match + 1;
      }
    }
    std::string text = encode(query);
    for (auto direction : {SearchDirection::Backward, SearchDirection::Forward}) {
      e.follow_output();
      // Forward starts at the oldest visible row, so explicitly browse to the
      // oldest retained row before requesting its first match.
      if (direction == SearchDirection::Forward) e.scroll_view(4096);
      for (size_t i = 0; i <= expected.size(); ++i) {
        auto match = e.search(text, direction, i == 0);
        check(match.found == !expected.empty(), "logical oracle found status");
        if (expected.empty()) break;
        size_t index = direction == SearchDirection::Backward
          ? expected.size() - 1 - i % expected.size() : i % expected.size();
        auto snapshot = e.snapshot();
        int absolute_row = snapshot.history_rows - match.view_offset + match.start_row;
        check(std::make_pair(absolute_row, match.start_col) == expected[index],
              "logical oracle match order/coordinates");
        check(e.selected_text() == text, "logical oracle copied codepoints");
      }
    }
  }
}

static std::string marked(int n) {
  const char *marks[] = {"\xcc\x81", "\xcc\x88", "\xcc\xa3", "\xcc\xb2"};
  std::string text = "A";
  for (int i = 0; i < n; ++i) text += marks[i % 4];
  return text;
}
static void variable_mark_search() {
  Engine e(8, 3);
  auto four = marked(4);
  feed(e, four + "B" + four.substr(1));
  for (int col : {0, 1, 0}) {
    auto m = e.search("\xcc\xb2", SearchDirection::Forward);
    check(m.found && m.start_col == col, "overflow-only search order and wrap");
  }
  check(e.search("\xcc\xb2", SearchDirection::Backward).start_col == 1,
        "overflow-only search direction reversal");
  check(e.search("\xcc\x88\xcc\xa3\xcc\xb2" "B", SearchDirection::Forward, true).found,
        "search crosses inline marks, overflow, and following cell");
  e.clear_search();
  const auto text = marked(256);
  feed(e, "\033c" + text);
  check(e.search(text, SearchDirection::Backward, true).found && e.selected_text() == text,
        "full 257-codepoint marked-cell query");
  auto short_copy = e.selected_text();
  feed(e, "\r\n" + std::string(40, 'x'));
  e.resize(4, 4);
  check(e.search(text, SearchDirection::Backward, true).found && e.selected_text() == short_copy,
        "search marked history after reflow");
}
static void variable_mark_prompt() {
  Engine e(8, 3); feed(e, "\033[?25l");
  constexpr int W = 64, H = 48;
  uint32_t *pixels = nullptr;
  check(cudaMalloc(&pixels, W * H * sizeof(uint32_t)) == cudaSuccess, "mark prompt pixels");
  auto capture = [&](const std::string &text) {
    e.set_search_prompt(text); e.render(pixels, W, H);
    std::vector<uint32_t> out(W * H);
    check(cudaMemcpy(out.data(), pixels, out.size() * sizeof(uint32_t), cudaMemcpyDeviceToHost) == cudaSuccess,
          "mark prompt capture");
    return out;
  };
  auto first = capture(marked(3));
  auto fourth = capture("A\xcc\xb2");
  auto all = capture(marked(4));
  bool adds_ink = false;
  for (int y = 32; y < H; ++y) for (int x = 0; x < 8; ++x) {
    int i = y * W + x;
    check(all[i] == (first[i] & fourth[i]), "overflow prompt equals union of inline glyph coverage");
    adds_ink |= all[i] != first[i];
  }
  check(adds_ink, "fourth mark contributes independent visible coverage");
  auto long_prompt = capture(marked(256));
  for (int i = 0; i < 16; ++i) feed(e, "\r" + marked(256));
  e.render(pixels, W, H);
  std::vector<uint32_t> after(W * H);
  check(cudaMemcpy(after.data(), pixels, after.size() * sizeof(uint32_t), cudaMemcpyDeviceToHost) == cudaSuccess,
        "prompt after pool compaction");
  for (int y = 32; y < H; ++y) for (int x = 0; x < W; ++x)
    check(after[y * W + x] == long_prompt[y * W + x], "prompt root survives main-grid allocation and GC");
  e.set_search_prompt(""); e.clear_search(); feed(e, "\033c");
  check(e.memory_usage().mark_bytes == 0, "cleared prompt and reset release pool");
  cudaFree(pixels);
}

int main() {
  try {
    unicode_and_boundaries(); repeat_and_invalidation(); history_and_alternate();
    prompt_and_cleanup(); invalid_queries(); logical_corpus_oracle();
    variable_mark_search(); variable_mark_prompt();
  } catch (const std::exception &e) { std::fprintf(stderr, "%s\n", e.what()); return 1; }
}
