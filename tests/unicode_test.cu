#include "engine.cuh"

#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr uint32_t WIDE = 16, TAIL = 32;
using ct::Cell;
using ct::Engine;
void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}
void check(bool ok, const char *msg) {
  if (!ok)
    throw std::runtime_error(msg);
}
Cell at(Engine &e, int r, int c) {
  auto s = e.snapshot();
  return e.cells()[static_cast<size_t>(r * s.cols + c)];
}
void cell_is(Engine &e, int r, int c, uint32_t cp, uint32_t flags = 0) {
  Cell z = at(e, r, c);
  check(z.cp == cp && z.flags == flags, "unexpected Unicode cell");
}
void no_orphans(Engine &e) {
  auto s = e.snapshot();
  auto cells = e.cells();
  for (int r = 0; r < s.rows; ++r)
    for (int c = 0; c < s.cols; ++c) {
      const Cell &z = cells[static_cast<size_t>(r * s.cols + c)];
      if (z.flags & WIDE)
        check(c + 1 < s.cols &&
                  (cells[static_cast<size_t>(r * s.cols + c + 1)].flags & TAIL),
              "orphan wide base");
      if (z.flags & TAIL)
        check(c > 0 &&
                  (cells[static_cast<size_t>(r * s.cols + c - 1)].flags & WIDE),
              "orphan wide tail");
    }
}
void utf8_and_combining() {
  Engine e(12, 2);
  feed(e, "\xC3\xA9");
  cell_is(e, 0, 0, 0xE9);
  Engine c(12, 1);
  feed(c, "e\xCC\x81");
  Cell z = at(c, 0, 0);
  check(z.cp == 'e' && z.combining[0] == 0x301, "combining mark attaches");
  Engine split(12, 1);
  feed(split, "e\xCC");
  feed(split, "\x81");
  z = at(split, 0, 0);
  check(z.cp == 'e' && z.combining[0] == 0x301, "split UTF-8 combining");
}
void utf8_boundaries() {
  for (const std::string sample : {std::string("é中😀é"),
                                   std::string("\xE0\x80\x80"
                                               "X"),
                                   std::string("\xED\xA0\x80"
                                               "X"),
                                   std::string("\xF4\x90\x80\x80"
                                               "X"),
                                   std::string("\xE2\x82"
                                               "Y"),
                                   std::string("\x80"
                                               "X"),
                                   std::string("\xE2\x82\x1b[31mX")}) {
    Engine whole(20, 2);
    feed(whole, sample);
    const auto expected = whole.cells();
    const auto cursor = whole.snapshot();
    if (static_cast<unsigned char>(sample[0]) != 0xC3)
      check(expected[0].cp == 0xFFFD, "invalid UTF-8 yields replacement");
    for (size_t split = 0; split <= sample.size(); ++split) {
      Engine chunked(20, 2);
      feed(chunked, sample.substr(0, split));
      feed(chunked, sample.substr(split));
      auto actual = chunked.cells();
      for (size_t i = 0; i < actual.size(); ++i) {
        check(actual[i].cp == expected[i].cp &&
                  actual[i].flags == expected[i].flags &&
                  actual[i].fg == expected[i].fg &&
                  actual[i].bg == expected[i].bg,
              "UTF-8 split cells");
        for (int m = 0; m < 3; ++m)
          check(actual[i].combining[m] == expected[i].combining[m],
                "UTF-8 split marks");
      }
      auto pos = chunked.snapshot();
      check(pos.row == cursor.row && pos.col == cursor.col,
            "UTF-8 split cursor");
    }
  }
}
void emoji_presentation() {
  const std::string heart = "\u2764\ufe0f", keycap = "1\ufe0f\u20e3";
  for (const auto &text : {heart, keycap}) {
    for (int start : {0, 6, 7}) {
      const std::string prefix = "\x1b[1;" + std::to_string(start + 1) + "H";
      Engine whole(8, 3);
      feed(whole, prefix + text);
      const int row = start == 7 ? 1 : 0, col = start == 7 ? 0 : start;
      Cell base = at(whole, row, col);
      check(base.cp == (text == heart ? 0x2764u : uint32_t('1')) &&
                (base.flags & WIDE) && base.combining[0] == 0xfe0f,
            "emoji presentation retains base and VS16 in wide cell");
      if (text == keycap) check(base.combining[1] == 0x20e3, "keycap mark retained");
      no_orphans(whole);
      whole.select(row, col, row, col + 1);
      check(whole.selected_text() == text, "emoji exact UTF-8 selection");
      whole.clear_selection();
      auto match = whole.search(text, ct::SearchDirection::Forward, true);
      check(match.found && whole.selected_text() == text, "emoji exact UTF-8 search");
      whole.clear_search();
      feed(whole, "X");
      auto expected = whole.cells();
      auto cursor = whole.snapshot();
      for (size_t split = 0; split <= text.size(); ++split) {
        Engine chunked(8, 3);
        feed(chunked, prefix + text.substr(0, split));
        feed(chunked, text.substr(split) + "X");
        auto actual = chunked.cells();
        for (size_t i = 0; i < actual.size(); ++i) {
          check(actual[i].cp == expected[i].cp && actual[i].flags == expected[i].flags,
                "emoji split cells and wide pairs");
          for (int m = 0; m < 3; ++m)
            check(actual[i].combining[m] == expected[i].combining[m], "emoji split marks");
        }
        auto pos = chunked.snapshot();
        check(pos.row == cursor.row && pos.col == cursor.col, "emoji split cursor");
      }
      check(cursor.row == (start == 0 ? 0 : 1) &&
                cursor.col == (start == 0 ? 3 : start == 6 ? 1 : 3),
            "emoji following ASCII exposes wrap state");
    }
    Engine bottom(8, 2);
    feed(bottom, "top\r\nabcdefg" + text);
    check(bottom.snapshot().history_rows == 1 && at(bottom, 0, 7).cp == 32,
          "emoji bottom promotion clears old base before row rotation");
    no_orphans(bottom);
    bottom.select(0, 0, 1, 1);
    check(bottom.selected_text() == "abcdefg" + text, "emoji bottom-scroll copy joins soft wrap");
    Engine reflow(8, 3);
    feed(reflow, "abcdefg" + text + "X");
    reflow.resize(5, 4);
    no_orphans(reflow);
    reflow.select(0, 0, 1, 4);
    check(reflow.selected_text() == "abcdefg" + text + "X", "emoji reflow preserves UTF-8");
    reflow.resize(12, 3);
    no_orphans(reflow);
    reflow.select(0, 0, 0, 10);
    check(reflow.selected_text() == "abcdefg" + text + "X", "emoji wider reflow preserves UTF-8");
  }
  Engine immediate(8, 2);
  feed(immediate, "\u2764");
  check(at(immediate, 0, 0).cp == 0x2764 && immediate.snapshot().col == 1,
        "lone candidate is emitted immediately");
  Engine invalid(8, 2);
  feed(invalid, "A\ufe0f");
  check(!(at(invalid, 0, 0).flags & WIDE) && invalid.snapshot().col == 1,
        "VS16 does not widen an unsupported ASCII base");
  Engine interrupted(8, 2);
  feed(interrupted, "\u2764\ufe0e\ufe0f");
  check(interrupted.snapshot().col == 1, "VS16 after VS15 is not an immediate emoji variation sequence");
  Engine inserted(8, 2);
  feed(inserted, "abcdef\x1b[1;2H\x1b[4h" + heart);
  inserted.select(0, 0, 0, 7);
  check(inserted.selected_text() == "a" + heart + "bcdef", "emoji insert shifts the extra cell");
  no_orphans(inserted);
  Engine inserted_wrap(8, 2);
  feed(inserted_wrap, "\x1b[2;1Habc\x1b[1;8H\x1b[4h" + heart);
  inserted_wrap.select(1, 0, 1, 4);
  check(inserted_wrap.selected_text() == heart + "abc", "emoji wrapped insert preserves next row");
  no_orphans(inserted_wrap);

  Engine repeated(8, 2);
  feed(repeated, heart + "\ufe0f");
  check(repeated.snapshot().col == 2, "repeated VS16 does not widen twice");
  no_orphans(repeated);
  Engine suffix(20, 4);
  feed(suffix, "\u2764");
  std::string suffix_bulk = "\ufe0fX\r\n";
  for (int i = 0; i < 40; ++i) suffix_bulk += "abcdef\r\n";
  feed(suffix, suffix_bulk);
  auto suffix_match = suffix.search(heart, ct::SearchDirection::Forward, true);
  check(suffix_match.found && suffix_match.end_col == 1 && suffix.selected_text() == heart,
        "bulk suffix-start feed promotes the prior feed base in history");
  const std::string line = "abc" + heart + " " + keycap + "\r\n";
  std::string bulk;
  for (int i = 0; i < 40; ++i) bulk += line;
  Engine fast(20, 4), streaming(20, 4);
  feed(fast, bulk);
  for (char c : bulk) feed(streaming, std::string(1, c));
  auto a = fast.cells(), b = streaming.cells();
  for (size_t i = 0; i < a.size(); ++i) {
    check(a[i].cp == b[i].cp && a[i].flags == b[i].flags, "emoji bulk versus scalar cells");
    for (int m = 0; m < 3; ++m)
      check(a[i].combining[m] == b[i].combining[m], "emoji bulk versus scalar marks");
  }
  check(fast.snapshot().history_rows == streaming.snapshot().history_rows,
        "emoji bulk versus scalar history");
}
void skin_tones() {
  auto same = [](Engine &a, Engine &b) {
    auto x = a.cells(), y = b.cells();
    check(x.size() == y.size(), "tone cell count");
    for (size_t i = 0; i < x.size(); ++i) {
      check(x[i].cp == y[i].cp && x[i].flags == y[i].flags &&
            x[i].fg == y[i].fg && x[i].bg == y[i].bg, "tone feed cell equivalence");
      for (int m = 0; m < 3; ++m)
        check(x[i].combining[m] == y[i].combining[m], "tone feed mark equivalence");
    }
    auto u = a.snapshot(), v = b.snapshot();
    check(u.row == v.row && u.col == v.col && u.history_rows == v.history_rows,
          "tone feed cursor/history equivalence");
    no_orphans(a); no_orphans(b);
  };
  for (const std::string text : {std::string("👍🏽"), std::string("☝🏽"), std::string("☝️🏽")}) {
    for (int start : {0, 6, 7}) {
      std::string prefix = "\033[1;" + std::to_string(start + 1) + "H";
      Engine whole(8, 3); feed(whole, prefix + text);
      int row = start == 7 ? 1 : 0, col = start == 7 ? 0 : start;
      check(at(whole, row, col).flags & WIDE, "tone sequence is wide");
      whole.select(row, col, row, col + 1);
      check(whole.selected_text() == text, "tone exact selected UTF-8");
      whole.clear_selection();
      auto match = whole.search(text, ct::SearchDirection::Forward, true);
      check(match.found && whole.selected_text() == text, "tone exact search/copy");
      whole.clear_search(); feed(whole, "X");
      check(whole.snapshot().row == (start == 0 ? 0 : 1) &&
            whole.snapshot().col == (start == 0 ? 3 : start == 6 ? 1 : 3),
            "tone following ASCII cursor");
      for (size_t split = 0; split <= text.size(); ++split) {
        Engine chunks(8, 3); feed(chunks, prefix + text.substr(0, split));
        feed(chunks, text.substr(split) + "X"); same(whole, chunks);
      }
    }
    Engine bottom(8, 2); feed(bottom, "top\r\nabcdefg" + text);
    check(bottom.snapshot().history_rows == 1 && at(bottom, 0, 7).cp == 32,
          "tone early wide bottom scroll padding");
    bottom.select(0, 0, 1, 1);
    check(bottom.selected_text() == "abcdefg" + text, "tone history copy");
    bottom.clear_selection(); bottom.resize(5, 4); no_orphans(bottom);
    check(bottom.search("abcdefg" + text, ct::SearchDirection::Forward, true).found &&
          bottom.selected_text() == "abcdefg" + text, "tone reflow exact search/copy");
    Engine inserted(8, 2); feed(inserted, "abcdef\033[1;2H\033[4h" + text);
    inserted.select(0, 0, 0, 7);
    check(inserted.selected_text() == "a" + text + "bcdef", "tone insert shift");
    no_orphans(inserted);
  }
  Engine controls(12, 3);
  feed(controls, "👍\033[31m🏽X");
  check(controls.snapshot().col == 3 && at(controls,0,0).combining[0] == 0x1f3fd,
        "tone preserves SGR adjacency");
  feed(controls, "\033c👍\033[1;3H🏽X");
  check(controls.snapshot().col == 3, "tone preserves same-cursor CUP adjacency");
  feed(controls, "\033c👍\r🏽");
  check(at(controls,0,0).cp == 0x1f3fd && !at(controls,0,0).combining[0],
        "tone at column zero is standalone after CR");
  feed(controls, "\033c👍\b🏽");
  check(controls.snapshot().col == 3 && at(controls,0,1).cp == 0x1f3fd,
        "tone inside old wide pair is standalone after BS");
  for (const std::string text : {std::string("🏽"),std::string("A🏽"),
                                std::string("❤🏽"),std::string("👍🏽🏽")}) {
    feed(controls, "\033c" + text);
    int expected = text == "🏽" ? 2 : text == "👍🏽🏽" ? 4 : 3;
    check(controls.snapshot().col == expected, "tone unsupported/lone/repeated scalar behavior");
    no_orphans(controls);
  }
  Engine clipped(2, 1);
  feed(clipped, "\033[?7l☝☝🏽");
  clipped.select(0, 0, 0, 1);
  check(clipped.selected_text() == "☝�" && !at(clipped,0,0).combining[0],
        "clipped no-wrap cursor does not attach tone to an earlier base");
  for (int cols : {1, 8, 20}) {
    std::string bulk;
    for (int i = 0; i < 32; ++i) bulk += "\033[32m👍🏽☝🏽☝️🏽\033[0mX\r\n";
    Engine fast(cols, 4), streaming(cols, 4);
    feed(fast, bulk);
    for (char c : bulk) feed(streaming, std::string(1,c));
    same(fast, streaming);

  }
}

std::string mark_text(int count) {
  const char *marks[] = {"\xcc\x81", "\xcc\x88", "\xcc\xa3", "\xcc\xb2"};
  std::string result = "A";
  for (int i = 0; i < count; ++i) result += marks[i % 4];
  return result;
}
std::string copy_cell_text(Engine &e, int row = 0, int col = 0) {
  e.select(row, col, row, col);
  auto text = e.selected_text(); e.clear_selection(); return text;
}
void variable_marks() {
  static_assert(sizeof(Cell) == 32, "variable marks must not enlarge ASCII cells");
  Engine lazy(8, 4); feed(lazy, mark_text(3));
  check(lazy.memory_usage().mark_bytes == 0, "three inline marks need no arena");
  for (int count : {4, 16, 256}) {
    const auto text = mark_text(count);
    Engine whole(8, 4); feed(whole, text);
    check(copy_cell_text(whole) == text && whole.snapshot().col == 1,
          "variable marks exact text and width");
    check(whole.search(text, ct::SearchDirection::Forward, true).found &&
          whole.selected_text() == text, "variable marks exact search");
    whole.clear_search();
    for (size_t split = 0; split <= text.size(); ++split) {
      Engine chunks(8, 4); feed(chunks, text.substr(0, split));
      feed(chunks, text.substr(split));
      check(copy_cell_text(chunks) == text && chunks.snapshot().col == 1,
            "variable marks every UTF8 feed boundary");
    }
    whole.resize(1, 4);
    check(copy_cell_text(whole) == text, "narrow marked cell survives one-column reflow");
    whole.resize(8, 4);
    check(whole.search(text, ct::SearchDirection::Backward, true).found &&
          whole.selected_text() == text, "variable marks reflow search");
    Engine margin(8, 3); feed(margin, "\033[1;8H" + text + "B");
    margin.select(0, 7, 1, 0);
    check(margin.selected_text() == text + "B", "overflow marks at pending wrap");
    Engine controls(8, 3);
    feed(controls, text.substr(0, 7) + "\033[31m" + text.substr(7));
    check(copy_cell_text(controls) == text, "mark allocation retains SGR adjacency");
  }
  const auto text = mark_text(256);
  Engine history(8, 3); feed(history, text + "\r\n");
  feed(history, std::string(80, 'x'));
  check(history.search(text, ct::SearchDirection::Backward, true).found &&
        history.selected_text() == text, "overflow marks retained in history");
  history.clear_search(); feed(history, "\033[?1049h\033[H" + text);
  check(copy_cell_text(history) == text, "alternate has its own marked root");
  for (int i = 0; i < 12; ++i) feed(history, "\r" + text);
  feed(history, "\033[?1049l");
  check(history.search(text, ct::SearchDirection::Backward, true).found &&
        history.selected_text() == text, "primary history root survives alternate GC");
  Engine overwritten(8, 3);
  for (int i = 0; i < 32; ++i) {
    feed(overwritten, "\r" + text);
    check(copy_cell_text(overwritten) == text, "overwrite/compact cycles preserve all marks");
  }
  check(overwritten.memory_usage().mark_bytes <= (8u << 20), "mark arena bounded");
  feed(overwritten, "\033c");
  check(overwritten.memory_usage().mark_bytes == 0, "reset releases unused mark arena");
  Engine inserted(8, 3); feed(inserted, text + "B\r\033[4hX");
  check(copy_cell_text(inserted, 0, 1) == text, "insert moves immutable mark reference");
  Engine leading(8, 4); feed(leading, mark_text(3) + "\r");
  std::string leading_batch = "\xcc\xb2\r\n";
  for (int i = 0; i < 32; ++i) leading_batch += "plain\r\n";
  feed(leading, leading_batch);
  check(leading.search(mark_text(4), ct::SearchDirection::Backward, true).found &&
        leading.selected_text() == mark_text(4), "styled leading mark preserves an earlier-feed base");
  for (int count : {4, 256}) {
    Engine framed(8, 3);
    std::string first = "\033[?2026h" + mark_text(count) + "\033[?2026l";
    std::string batch = first + "B";
    auto result = framed.feed_frame(reinterpret_cast<const unsigned char *>(batch.data()), batch.size());
    check(result.frame_complete && result.consumed == first.size() &&
          copy_cell_text(framed) == mark_text(count), "arena retry preserves frame byte boundary");
    feed(framed, batch.substr(result.consumed));
    framed.select(0, 0, 0, 1);
    check(framed.selected_text() == mark_text(count) + "B", "next frame is consumed once after arena retry");
  }
  std::string bulk;
  for (int i = 0; i < 32; ++i) bulk += "\033[32m" + mark_text(16) + "\033[0mB\r\n";
  Engine fast(8, 4), streamed(8, 4); feed(fast, bulk);
  for (char c : bulk) feed(streamed, std::string(1, c));
  for (Engine *e : {&fast, &streamed}) {
    check(e->search(mark_text(16) + "B", ct::SearchDirection::Backward, true).found &&
          e->selected_text() == mark_text(16) + "B", "styled fallback keeps complete marked text");
  }
}

// Frozen Foot 1.27.0 private-headless observations:
// bench/grapheme-zwj-boundary-run-20260906T153118Z/parent-reviewed-expectations.json
void zwj_boundaries() {
  struct Case { const char *name, *text; int start, row, col, xrow, xcol; };
  const Case cases[] = {
    {"woman_zwj_laptop", "\360\237\221\251\342\200\215\360\237\222\273", 1, 1, 3, 1, 4},
    {"woman_zwj_sgr_laptop", "\360\237\221\251\342\200\215\033\133\063\061\155\360\237\222\273", 1, 1, 3, 1, 4},
    {"woman_sgr_zwj_laptop", "\360\237\221\251\033\133\063\061\155\342\200\215\360\237\222\273", 1, 1, 3, 1, 4},
    {"woman_zwj_cup3_laptop", "\360\237\221\251\342\200\215\033\133\061\073\063\110\360\237\222\273", 1, 1, 5, 1, 6},
    {"woman_zwj_cr_laptop", "\360\237\221\251\342\200\215\015\360\237\222\273", 1, 1, 3, 1, 4},
    {"woman_zwj_bs_laptop", "\360\237\221\251\342\200\215\010\360\237\222\273", 1, 1, 4, 1, 5},
    {"woman_zwj_acute_laptop", "\360\237\221\251\342\200\215\314\201\360\237\222\273", 1, 1, 5, 1, 6},
    {"woman_acute_zwj_laptop", "\360\237\221\251\314\201\342\200\215\360\237\222\273", 1, 1, 3, 1, 4},
    {"woman_zwj_zwj_laptop", "\360\237\221\251\342\200\215\342\200\215\360\237\222\273", 1, 1, 5, 1, 6},
    {"heart_no_vs16_zwj_fire", "\342\235\244\342\200\215\360\237\224\245", 1, 1, 3, 1, 4},
    {"copyright_zwj_laptop", "\302\251\342\200\215\360\237\222\273", 1, 1, 3, 1, 4},
    {"copyright_zwj_registered", "\302\251\342\200\215\302\256", 1, 1, 3, 1, 4},
    {"woman_zwj_laptop_col79", "\360\237\221\251\342\200\215\360\237\222\273", 79, 1, 80, 2, 2},
    {"woman_zwj_laptop_col80", "\360\237\221\251\342\200\215\360\237\222\273", 80, 2, 3, 2, 4},
    {"heart_zwj_fire_col79", "\342\235\244\342\200\215\360\237\224\245", 79, 1, 80, 2, 2},
    {"heart_zwj_fire_col80", "\342\235\244\342\200\215\360\237\224\245", 80, 2, 3, 2, 4},
    {"copyright_zwj_laptop_col79", "\302\251\342\200\215\360\237\222\273", 79, 1, 80, 2, 2},
    {"copyright_zwj_laptop_col80", "\302\251\342\200\215\360\237\222\273", 80, 2, 3, 2, 4},
    {"copyright_zwj_registered_col79", "\302\251\342\200\215\302\256", 79, 1, 80, 2, 2},
    {"copyright_zwj_registered_col80", "\302\251\342\200\215\302\256", 80, 2, 3, 2, 4},
  };
  Engine e(80, 24);
  for (const auto &c : cases) {
    std::string text = c.text;
    for (size_t split = 0; split <= text.size(); ++split) {
      feed(e, "\033c\033[1;" + std::to_string(c.start) + "H");
      feed(e, text.substr(0, split)); feed(e, text.substr(split));
      auto s = e.snapshot();
      if (s.row + 1 != c.row || s.col + 1 != c.col)
        throw std::runtime_error(std::string(c.name) + " cursor at split " + std::to_string(split));
      no_orphans(e);
      feed(e, "X"); s = e.snapshot();
      if (s.row + 1 != c.xrow || s.col + 1 != c.xcol)
        throw std::runtime_error(std::string(c.name) + " after-X cursor at split " + std::to_string(split));
      no_orphans(e);
    }
  }
}
void zwj_storage() {
  const std::string woman = "👩", joiner = "‍", laptop = "💻";
  for (int count : {0, 4, 66, 256}) {
    std::string text = woman;
    for (int i = 0; i < count; ++i) text += "́";
    text += joiner + laptop;
    Engine e(8, 4); feed(e, text);
    check(e.snapshot().col == 2, "GB11 overflow geometry");
    check(copy_cell_text(e) == text, "GB11 overflow exact selected UTF8");
    check(e.search(text, ct::SearchDirection::Backward, true).found &&
          e.selected_text() == text, "GB11 exact search including suffix");
    e.resize(3, 4);
    check(e.search(text, ct::SearchDirection::Backward, true).found &&
          e.selected_text() == text, "GB11 reflow preserves suffix order");
    no_orphans(e);
  }
  for (const std::string text : {woman + joiner + laptop,
                                 std::string("❤‍🔥"), std::string("©‍®"),
                                 std::string("👨‍👩‍👧‍👦")}) {
    Engine margin(4, 3); feed(margin, "abc" + text + "X");
    check(margin.search(text + "X", ct::SearchDirection::Backward, true).found &&
          margin.selected_text() == text + "X", "GB11 last-column promotion exact text");
    no_orphans(margin);
    Engine bottom(4, 2); feed(bottom, "\033[2;4H" + text + "X");
    check(bottom.search(text + "X", ct::SearchDirection::Backward, true).found &&
          bottom.selected_text() == text + "X", "GB11 bottom-row promotion exact text");
    no_orphans(bottom);
  }
  Engine barrier(80, 24);
  feed(barrier, woman + joiner); feed(barrier, "\033[1;3H");
  std::string sgr_only;
  for (int i = 0; i < 100; ++i) sgr_only += "\033[31m";
  feed(barrier, sgr_only); feed(barrier, laptop);
  check(barrier.snapshot().col == 4, "SGR-only styled batch preserves cursor barrier");
  // The second feed has no ZWJ bytes: preflight must inspect the prior cell.
  Engine split_fast(80, 24);
  feed(split_fast, woman + joiner);
  std::string second = laptop + std::string(300, 'a');
  feed(split_fast, second);
  check(split_fast.search(woman + joiner + laptop, ct::SearchDirection::Backward, true).found &&
        split_fast.selected_text() == woman + joiner + laptop,
        "styled incoming EP joins prior-feed ZWJ");
  std::string bulk;
  for (int i = 0; i < 32; ++i) bulk += "\033[31m" + woman + joiner + laptop + "X\r\n";
  Engine fast(80, 24); feed(fast, bulk);
  check(fast.search(woman + joiner + laptop + "X", ct::SearchDirection::Backward, true).found &&
        fast.selected_text() == woman + joiner + laptop + "X", "styled GB11 exact text");
  auto m = fast.search("X", ct::SearchDirection::Backward, true);
  check(m.found && m.start_col == 2, "styled GB11 following-cell geometry");
}

void wide_cells() {
  Engine e(6, 1);
  feed(e, "\xE4\xB8\xAD"
          "A");
  cell_is(e, 0, 0, 0x4E2D, WIDE);
  cell_is(e, 0, 1, 0, TAIL);
  cell_is(e, 0, 2, 'A');
  Engine one(1, 1);
  feed(one, "\xE4\xB8\xAD");
  cell_is(one, 0, 0, 0xFFFD);
  Engine o(5, 1);
  feed(o, "\xE4\xB8\xAD\x1b[1;2HX");
  cell_is(o, 0, 0, 32);
  cell_is(o, 0, 1, 'X');
  no_orphans(o);
  Engine b(5, 1);
  feed(b, "\xE4\xB8\xAD\x1b[1;1HX");
  cell_is(b, 0, 0, 'X');
  cell_is(b, 0, 1, 32);
  no_orphans(b);
}
void wide_wrap_resize_and_edit() {
  Engine w(3, 2);
  feed(w, "\x1b[?7h\x1b[1;3H\xE4\xB8\xAD");
  cell_is(w, 0, 2, 32);
  cell_is(w, 1, 0, 0x4E2D, WIDE);
  cell_is(w, 1, 1, 0, TAIL);
  Engine r(4, 1);
  feed(r, "\x1b[1;2H\xE4\xB8\xAD");
  r.resize(2, 1);
  cell_is(r, 0, 0, 0x4E2D, WIDE);
  cell_is(r, 0, 1, 0, TAIL);
  no_orphans(r);
  Engine insert(6, 1);
  feed(insert, "A中B\x1b[1;2H\x1b[@");
  cell_is(insert, 0, 1, 32);
  cell_is(insert, 0, 2, 0x4E2D, WIDE);
  cell_is(insert, 0, 3, 0, TAIL);
  cell_is(insert, 0, 4, 'B');
  feed(insert, "\x1b[P");
  cell_is(insert, 0, 1, 0x4E2D, WIDE);
  cell_is(insert, 0, 2, 0, TAIL);
  cell_is(insert, 0, 3, 'B');
  Engine x(5, 1);
  feed(x, "A\xE4\xB8\xAD"
          "B\x1b[1;3H\x1b[1X");
  no_orphans(x);
  feed(x, "\x1b[1;2H\x1b[1@");
  no_orphans(x);
  feed(x, "\x1b[1;2H\x1b[1P");
  no_orphans(x);
}
std::vector<uint32_t> render(Engine &e, int w, int h) {
  uint32_t *device = nullptr;
  check(cudaMalloc(&device, static_cast<size_t>(w * h) * sizeof(uint32_t)) ==
            cudaSuccess,
        "render allocation");
  e.render(device, w, h);
  std::vector<uint32_t> pixels(static_cast<size_t>(w * h));
  check(cudaMemcpy(pixels.data(), device, pixels.size() * sizeof(uint32_t),
                   cudaMemcpyDeviceToHost) == cudaSuccess,
        "render copy");
  cudaFree(device);
  return pixels;
}
void rendering() {
  Engine e(4, 1);
  feed(e, "\x1b[?25l\xCE\xB1 \xE4\xB8\xAD");
  auto p = render(e, 32, 16);
  const uint32_t bg = p[0];
  bool alpha = false, left = false, right = false;
  for (int y = 0; y < 16; ++y)
    for (int x = 0; x < 32; ++x)
      if (p[static_cast<size_t>(y * 32 + x)] != bg) {
        if (x < 8)
          alpha = true;
        if (x >= 16 && x < 24)
          left = true;
        if (x >= 24)
          right = true;
      }
  check(alpha && left && right, "Greek and both CJK halves render");
  Engine plain(2, 1);
  feed(plain, "\x1b[?25le");
  auto a = render(plain, 16, 16);
  Engine marked(2, 1);
  feed(marked, "\x1b[?25le\xCC\x81");
  auto b = render(marked, 16, 16);
  check(a != b, "combining acute changes rendering");
}
void supplementary_rendering() {
  struct Example { const char *text; int cols; uint16_t rows[16]; };
  // Literal GNU Unifont 17.0.05 upper-plane bitmaps, independent of atlas lookup.
  const Example examples[] = {
      {"😀", 2, {0x0000, 0x03e0, 0x0c18, 0x1004, 0x2002, 0x2632, 0x4631, 0x4001, 0x4001, 0x4ff9, 0x2aaa, 0x26b2, 0x13e4, 0x0c18, 0x03e0, 0x0000}},
      {"𐌀", 1, {0x0000, 0x0000, 0x0000, 0x0000, 0x6000, 0x5000, 0x4800, 0x4800, 0x4400, 0x4400, 0x7e00, 0x4200, 0x4200, 0x4200, 0x0000, 0x0000}},
      {"𠀀", 2, {0x0000, 0xfffe, 0x0080, 0x0080, 0x0080, 0x0080, 0x0080, 0x3f80, 0x2000, 0x2000, 0x2000, 0x2000, 0x2000, 0x2000, 0x3ffc, 0x0000}},
      {" 𝆅", 1, {0x0000, 0x0200, 0x0200, 0x8400, 0x7800, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000}},
  };
  for (const auto &example : examples) {
    Engine e(example.cols, 1);
    feed(e, std::string("\x1b[?25l") + example.text);
    auto actual = render(e, example.cols * 8, 16);
    for (int y = 0; y < 16; ++y)
      for (int x = 0; x < example.cols * 8; ++x)
        check(actual[y * example.cols * 8 + x] ==
                  (example.rows[y] & (0x8000u >> x) ? 0xffffffffu : 0xff000000u),
              "supplementary bitmap differs from Unifont source");
  }
  Engine missing(1, 1), replacement(1, 1);
  feed(missing, "\x1b[?25l\xf4\x8f\xbf\xbd"); // U+10FFFD, absent from atlas.
  feed(replacement, "\x1b[?25l�");
  check(render(missing, 8, 16) == render(replacement, 8, 16),
        "missing supplementary glyph must use replacement");
}
void ppm(const char *path) {
  Engine e(20, 4);
  feed(e, "\x1b[?25lα Ελληνικά / Кириллица / 中\r\n e\xCC\x81  日本語\r\n😀 𐌀 𠀀 /  𝆅");
  auto p = render(e, 160, 64);
  FILE *f = std::fopen(path, "wb");
  check(f != nullptr, "open PPM");
  std::fprintf(f, "P6\n160 64\n255\n");
  for (uint32_t v : p) {
    unsigned char rgb[] = {static_cast<unsigned char>(v),
                           static_cast<unsigned char>(v >> 8),
                           static_cast<unsigned char>(v >> 16)};
    std::fwrite(rgb, 1, 3, f);
  }
  std::fclose(f);
}
} // namespace
int main(int argc, char **argv) {
  try {
    utf8_and_combining();
    utf8_boundaries();
    emoji_presentation();
    skin_tones();
    variable_marks();
    zwj_boundaries();
    zwj_storage();
    wide_cells();
    wide_wrap_resize_and_edit();
    rendering();
    supplementary_rendering();
    if (argc == 3 && std::string(argv[1]) == "--ppm")
      ppm(argv[2]);
    else if (argc != 1)
      throw std::runtime_error("usage: unicode-test [--ppm PATH]");
    return 0;
  } catch (const std::exception &e) {
    std::fprintf(stderr, "unicode-test: %s\n", e.what());
    return 1;
  }
}
