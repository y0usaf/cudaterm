#include "engine.cuh"

#include <cuda_runtime.h>

#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using ct::Cell;
using ct::Engine;

void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}

void check(bool ok, const char *message) {
  if (!ok)
    throw std::runtime_error(message);
}

std::vector<uint32_t> pixels(Engine &e, int width, int height) {
  uint32_t *device = nullptr;
  check(cudaMalloc(&device, static_cast<size_t>(width * height) *
                                sizeof(uint32_t)) == cudaSuccess,
        "scrollback render allocation");
  e.render(device, width, height);
  std::vector<uint32_t> result(static_cast<size_t>(width * height));
  check(cudaMemcpy(result.data(), device, result.size() * sizeof(uint32_t),
                   cudaMemcpyDeviceToHost) == cudaSuccess,
        "scrollback render copy");
  cudaFree(device);
  return result;
}

std::string view_text(Engine &e, int rows, int cols) {
  e.select(0, 0, rows - 1, cols - 1);
  const std::string text = e.selected_text();
  e.clear_selection();
  return text;
}

std::string view_row(Engine &e, int row, int cols) {
  e.select(row, 0, row, cols - 1);
  const std::string text = e.selected_text();
  e.clear_selection();
  return text;
}

std::string repeat(const std::string &s, int count) {
  std::string out;
  for (int i = 0; i < count; ++i)
    out += s;
  return out;
}

void basic_history_and_follow() {
  Engine e(8, 3);
  feed(e, "one\r\ntwo\r\nthree\r\nfour");
  check(e.snapshot().history_rows == 1, "basic history row count");
  check(e.snapshot().view_offset == 0, "initially following output");
  e.scroll_view(1);
  check(e.snapshot().view_offset == 1, "scrolling to history");
  check(view_text(e, 3, 8) == "one\ntwo\nthree", "basic viewed rows");
  const auto live = e.cells();
  bool live_four = false;
  for (const Cell &cell : live)
    live_four |= cell.cp == static_cast<unsigned>('f');
  check(live_four, "scrolling replaced live cells");
  feed(e, "\r\nfive");
  check(e.snapshot().view_offset == 2, "anchored view follows history growth");
  check(view_text(e, 3, 8) == "one\ntwo\nthree", "anchored viewed rows");
  e.follow_output();
  check(e.snapshot().view_offset == 0, "follow output resets view");
}

void bulk_and_bytewise_have_the_same_history(const std::string &name,
                                             const std::string &payload,
                                             int cols = 17, int rows = 5,
                                             const std::string &setup = "") {
  Engine bulk(cols, rows), bytes(cols, rows);
  feed(bulk, setup);
  feed(bytes, setup);
  feed(bulk, payload);
  for (unsigned char byte : payload)
    bytes.feed(&byte, 1);
  const auto a = bulk.snapshot(), b = bytes.snapshot();
  check(a.history_rows == b.history_rows, name.c_str());
  check(a.view_offset == b.view_offset, name.c_str());
  for (int offset = 0; offset <= a.history_rows; ++offset) {
    bulk.follow_output();
    bytes.follow_output();
    bulk.scroll_view(offset);
    bytes.scroll_view(offset);
    check(view_text(bulk, rows, cols) == view_text(bytes, rows, cols),
          name.c_str());
    check(pixels(bulk, cols * 8, rows * 16) ==
              pixels(bytes, cols * 8, rows * 16),
          name.c_str());
  }
}

void growing_history_preserves_view() {
  Engine e(8, 2);
  feed(e, "old\r\nnew\r\n");
  e.resize(12, 2);
  e.scroll_view(1);
  const auto before = pixels(e, 96, 32);
  // Nonprinting input grows the conservative reservation without adding rows.
  feed(e, std::string(1000, '\0'));
  check(e.snapshot().history_rows == 1 && e.snapshot().view_offset == 1,
        "history growth changed anchored view");
  check(view_row(e, 0, 12) == "old", "history growth lost old row");
  check(pixels(e, 96, 32) == before, "history growth changed pixels");
  e.resize(6, 2);
  feed(e, std::string(1500, '\0'));
  check(view_row(e, 0, 6) == "old", "second growth after resize lost row");
  feed(e, "last\r\n");
  check(e.snapshot().history_rows == 2 && e.snapshot().view_offset == 2,
        "history append after growth lost anchor");
  check(view_row(e, 0, 6) == "old", "history append after growth lost old row");
}

void fragmented_paths_match() {
  bulk_and_bytewise_have_the_same_history(
      "invalid UTF-8 can scroll twice on one byte",
      repeat("\xe4X", 150), 1, 1, "A");
  bulk_and_bytewise_have_the_same_history(
      "repeated carriage returns before newline",
      repeat("\x1b[42mé中\r\r\n\r\r\r\nabcdefghijklmnopq\r\r\n", 30));
  bulk_and_bytewise_have_the_same_history(
      "carriage return before overwritten text still falls back",
      repeat("original\r\rnew\r\n", 30));
  bulk_and_bytewise_have_the_same_history(
      "incomplete carriage return run",
      repeat("line\r\r\n", 40) + "tail\r\r");
  bulk_and_bytewise_have_the_same_history(
      "plain history chunks",
      "first\r\nsecond\r\nthird\r\nfourth\r\n" + std::string(300, 'x'));
  bulk_and_bytewise_have_the_same_history(
      "styled Unicode history chunks",
      "\x1b[31mred é 中 😀\x1b[0m\r\n\x1b[38;2;1;2;3mblue\r\n" +
          repeat("wide 中\r\n", 80));
  bulk_and_bytewise_have_the_same_history("long wrapping history chunks",
                                          std::string(700, 'w') + "\r\nend");
  bulk_and_bytewise_have_the_same_history(
      "history fill uses row creation colors",
      repeat("\x1b[41mred\t中\r\n\x1b[42mgreen\r\n"
             "\x1b[0m\tdefault\r\n", 30));
  bulk_and_bytewise_have_the_same_history(
      "fallback and control fragments",
      repeat("a\x1b]title\x07"
             "b\x1bPignored\x1b\\c\t\r\nd\r\n",
             30));
}

void edited_wide_rows_enter_history() {
  const std::string setup = "中中Q\r\nsecond\r\nthird\x1b[1;2H";
  bulk_and_bytewise_have_the_same_history("plain edits before history",
                                          std::string(600, 'A'), 17, 5, setup);
  bulk_and_bytewise_have_the_same_history("styled edits before history",
                                          repeat("\x1b[31mé中é\x1b[0m\r\n", 30),
                                          17, 5, setup);
}
void history_erasure_and_wide_resize() {
  Engine e(4, 2);
  feed(e, "A中\r\nnext\r\nlast");
  check(e.snapshot().history_rows == 1, "wide resize fixture");
  e.resize(2, 2);
  e.scroll_view(999999);
  e.select(0, 0, 1, 1);
  check(e.selected_text() == "A中", "resize lost wide logical line");
  e.resize(8, 2);
  e.select(0, 0, 0, 7);
  check(e.selected_text() == "A中", "resize failed to reflow wide line");
  const int before_ed2 = e.snapshot().history_rows;
  feed(e, "\x1b[2J");
  check(e.snapshot().history_rows == before_ed2, "ED2 preserves scrollback");
  feed(e, "\x1b"
          "c");
  check(!e.snapshot().history_rows && !e.snapshot().view_offset,
        "RIS clears scrollback");
}
void tabbed_lines_preserve_layout() {
  bulk_and_bytewise_have_the_same_history("parallel tabs",
                                          repeat("column\tvalue\r\n", 60));
  bulk_and_bytewise_have_the_same_history(
      "custom tabs and styled Unicode",
      repeat("\x1b[31ma\tb\té中\tZ\x1b[0m\r\n", 30), 17, 5,
      "\x1b[3g\x1b[1;4H\x1bH\x1b[1;10H\x1bH\x1b[H");
  bulk_and_bytewise_have_the_same_history("tab cancels delayed wrap",
                                          repeat("12345678\tZ\r\n", 40), 8, 3);
  bulk_and_bytewise_have_the_same_history("leading trailing and empty tabs",
                                          repeat("\t\t\r\nX\t\r\n\tY\r\n", 40),
                                          17, 5);
  bulk_and_bytewise_have_the_same_history("inherited delayed wrap then tab",
                                          "\tX\r\n" + repeat("a\tb\r\n", 60), 8,
                                          3, "12345678");
  ct::Engine literal(20, 3);
  feed(literal, repeat("a\tb\tc\r\n", 60));
  const auto cells = literal.cells();
  check(cells[0].cp == 'a' && cells[8].cp == 'b' && cells[16].cp == 'c' &&
            cells[7].cp == 32 && cells[15].cp == 32,
        "literal default tab columns");
}
void capacity_discards_oldest_rows() {
  Engine e(32, 3);
  std::string payload;
  for (int i = 0; i < 4100; ++i) {
    const char *padding = i < 10 ? "000" : i < 100 ? "00" : i < 1000 ? "0" : "";
    payload += std::string("L") + padding + std::to_string(i) + "\r\n";
  }
  feed(e, payload);
  const auto s = e.snapshot();
  check(s.history_rows == 4096, "history capacity");
  e.scroll_view(4096);
  check(view_text(e, 3, 32).find("L0002") == 0, "oldest retained row");
}

void evicted_ring_survives_repeated_resize() {
  const int rows = 3;
  for (const int cols : {1, 512}) {
    Engine e(cols, rows);
    std::string payload;
    for (int i = 0; i < 4100; ++i) {
      const char marker = static_cast<char>('A' + i % 26);
      if (cols == 1) {
        payload += marker;
      } else {
        const char *padding = i < 10     ? "000"
                              : i < 100  ? "00"
                              : i < 1000 ? "0"
                                         : "";
        payload += std::string(1, marker) + "-L" + padding + std::to_string(i);
      }
      payload += "\r\n";
    }
    feed(e, payload);
    check(e.snapshot().history_rows == 4096, "resize ring history capacity");

    e.scroll_view(4096);
    const std::string oldest = view_row(e, 0, cols);
    const std::string expected_oldest = cols == 1 ? "C" : "C-L0002";
    check(oldest == expected_oldest, "resize ring oldest retained row");

    e.scroll_view(-4095);
    const std::string newest = view_row(e, 0, cols);
    const std::string expected_newest = cols == 1 ? "P" : "P-L4097";
    check(newest == expected_newest, "resize ring newest retained row");

    for (int i = 0; i < 2; ++i) {
      e.resize(1, rows);
      e.resize(cols, rows);
    }
    if (cols == 1) {
      e.scroll_view(4096);
      check(view_row(e, 0, cols) == "C",
            "resize ring oldest after narrow and widen");
      e.scroll_view(-4095);
      check(view_row(e, 0, cols) == "P",
            "resize ring newest after narrow and widen");
    } else {
      e.scroll_view(4096);
      check(view_row(e, 0, cols) == "514",
            "reflow ring oldest retained partial line");
      e.follow_output();
      e.scroll_view(1);
      check(view_row(e, 0, cols) == "Q-L4098",
            "reflow ring newest retained line");
    }

    feed(e,
         cols == 1 ? "x\r\ny\r\n\r\n\r\n" : "X-fresh\r\nY-fresh\r\n\r\n\r\n");
    e.follow_output();
    e.scroll_view(1);
    check(view_row(e, 0, cols) == (cols == 1 ? "y" : "Y-fresh"),
          "resize ring appended newest row");

    if (cols == 512) {
      feed(e, "\x1b[31m中\x1b[0m\r\n\r\n\r\n");
      e.follow_output();
      e.scroll_view(1);
      check(view_row(e, 0, cols) == "中",
            "colored wide row retained before clipping");
      e.resize(1, rows);
      e.select(0, 0, 0, 0);
      check(e.selected_text() == "�", "colored wide row lacks replacement");
      e.resize(512, rows);
      e.select(0, 0, 0, 511);
      check(e.selected_text() == "�",
            "colored wide row replacement lost after widening");
    }
  }
}

void follow_tracks_view_and_selection() {
  Engine e(8, 2);
  e.follow_output();
  e.scroll_view(1); // No history yet; a follow must still be harmless.
  e.follow_output();
  feed(e, "one\r\ntwo\r\nthree");
  e.scroll_view(1);
  e.resize(9, 3);
  e.follow_output();
  check(e.snapshot().view_offset == 0, "follow after scrolled resize");
  e.select(0, 0, 0, 1);
  check(!e.selected_text().empty(), "live selection exists before follow");
  e.follow_output();
  check(e.selected_text().empty(), "follow clears live selection");
  e.follow_output();
  e.scroll_view(1);
  feed(e, "\r\nfour\r\nfive");
  e.follow_output();
  check(e.snapshot().view_offset == 0, "follow after output anchors history");
}
void early_wide_wrap_captures_erasure() {
  ct::Engine e(3, 1);
  feed(e, "ABZ\x1b[1;3H中");
  check(e.snapshot().history_rows == 1, "early wrap enters history");
  e.scroll_view(1);
  check(view_text(e, 1, 3) == "AB",
        "history capture follows early-wrap erasure");
  e.follow_output();
  check(view_text(e, 1, 3) == "中", "copy completes before recycled row paint");
  feed(e, "\r\nX\r\nY");
  e.scroll_view(2);
  check(view_text(e, 1, 3) == "中", "later scrolls retain complete wide row");
}
void resize_reflows_logical_rows() {
  Engine e(12, 3);
  feed(e, "0123456789AB\r\nsecond\r\nthird\r\nfourth");
  e.scroll_view(2);
  e.resize(6, 4);
  check(e.snapshot().history_rows == 1, "resize retained history");
  check(view_text(e, 4, 6).find("0123456789AB") == 0,
        "resize failed to reflow logical rows");
}

void alternate_and_margins_do_not_enter_history() {
  Engine e(8, 3);
  feed(e, "one\r\ntwo\r\nthree\r\n");
  const int before = e.snapshot().history_rows;
  e.scroll_view(100);
  feed(e, "\x1b[?1049h" + repeat("alt\r\n", 80));
  check(e.snapshot().view_offset == 0,
        "alternate view follows alternate screen");
  e.scroll_view(100);
  check(e.snapshot().view_offset == 0, "alternate excludes history browsing");
  feed(e, "\x1b[?1049l");
  check(e.snapshot().history_rows == before,
        "alternate screen entered history");
  feed(e, "\x1b[2;3r\x1b[2;1Hmargin\r\nline");
  check(e.snapshot().history_rows == before, "margin scroll entered history");
}

void erase_scrollback_clears_history_but_keeps_screen() {
  Engine e(8, 3);
  feed(e, "old\r\ncurrent\r\nline\r\nlast");
  check(e.snapshot().history_rows > 0, "ED3 setup history");
  const auto visible = view_text(e, 3, 8);
  feed(e, "\x1b[3J");
  check(e.snapshot().history_rows == 0, "ED3 history clear");
  check(view_text(e, 3, 8) == visible, "ED3 erased visible screen");
}

void styled_history_renders_after_scrolling() {
  Engine e(8, 3);
  feed(e, "\x1b[31mRED\x1b[0m\r\nplain\r\nlast\r\nnow");
  const auto before = pixels(e, 64, 48);
  e.scroll_view(1);
  const auto after = pixels(e, 64, 48);
  check(before != after, "scrolling did not change raster view");
  check(e.snapshot().view_offset == 1, "raster scroll offset");
}
} // namespace

int main() {
  struct Test {
    const char *name;
    void (*run)();
  } tests[] = {
      {"basic_history_and_follow", basic_history_and_follow},
      {"follow_tracks_view_and_selection", follow_tracks_view_and_selection},
      {"growing_history_preserves_view", growing_history_preserves_view},
      {"early_wide_wrap_captures_erasure", early_wide_wrap_captures_erasure},
      {"fragmented_paths_match", fragmented_paths_match},
      {"tabbed_lines_preserve_layout", tabbed_lines_preserve_layout},
      {"edited_wide_rows_enter_history", edited_wide_rows_enter_history},
      {"history_erasure_and_wide_resize", history_erasure_and_wide_resize},
      {"capacity_discards_oldest_rows", capacity_discards_oldest_rows},
      {"evicted_ring_survives_repeated_resize",
       evicted_ring_survives_repeated_resize},
      {"resize_reflows_logical_rows", resize_reflows_logical_rows},
      {"alternate_and_margins_do_not_enter_history",
       alternate_and_margins_do_not_enter_history},
      {"erase_scrollback_clears_history_but_keeps_screen",
       erase_scrollback_clears_history_but_keeps_screen},
      {"styled_history_renders_after_scrolling",
       styled_history_renders_after_scrolling},
  };
  int failures = 0;
  for (const auto &test : tests) {
    try {
      test.run();
    } catch (const std::exception &ex) {
      std::fprintf(stderr, "%s: %s\n", test.name, ex.what());
      ++failures;
    }
  }
  return failures ? 1 : 0;
}
