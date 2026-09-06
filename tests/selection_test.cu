#include "engine.cuh"

#include <cuda_runtime.h>

#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using ct::Engine;

void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}

void check(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

void expect_text(Engine &e, const std::string &expected) {
  check(e.selected_text() == expected, "unexpected selected text");
}

std::vector<uint32_t> render(Engine &e, int width, int height) {
  uint32_t *device = nullptr;
  check(cudaMalloc(&device, static_cast<size_t>(width * height) *
                                sizeof(uint32_t)) == cudaSuccess,
        "selection render allocation");
  e.render(device, width, height);
  std::vector<uint32_t> pixels(static_cast<size_t>(width * height));
  check(cudaMemcpy(pixels.data(), device, pixels.size() * sizeof(uint32_t),
                   cudaMemcpyDeviceToHost) == cudaSuccess,
        "selection render copy");
  cudaFree(device);
  return pixels;
}

void forward_reverse_and_clamp() {
  Engine e(8, 3);
  feed(e, "abcdefgh\r\nijklmnop\r\nqrstuvwx");

  e.select(0, 1, 1, 2);
  expect_text(e, "bcdefgh\nijk");
  e.select(1, 2, 0, 1);
  expect_text(e, "bcdefgh\nijk");

  e.select(-10, -20, 50, 40);
  expect_text(e, "abcdefgh\nijklmnop\nqrstuvwx");
  e.clear_selection();
  expect_text(e, "");

  Engine padded(8, 1);
  feed(padded, "abc   ");
  padded.select(0, 0, 0, 7);
  expect_text(padded, "abc");

  Engine marked(8, 1);
  feed(marked, "a \xCC\x81");
  marked.select(0, 0, 0, 7);
  expect_text(marked, "a \xCC\x81");
}

void word_and_line_selection() {
  using ct::SelectionMode;
  Engine e(24, 3);
  feed(e, "alpha_beta:: e\xCC\x81\xE4\xB8\xAD end\r\nsecond line");
  e.select(0, 4, 0, 4, SelectionMode::Word);
  expect_text(e, "alpha_beta");
  e.select(0, 10, 0, 10, SelectionMode::Word);
  expect_text(e, "::");
  e.select(0, 15, 0, 15, SelectionMode::Word);
  expect_text(e, "e\xCC\x81\xE4\xB8\xAD");
  e.select(0, 13, 0, 4, SelectionMode::Word);
  expect_text(e, "alpha_beta:: e\xCC\x81\xE4\xB8\xAD");
  e.select(1, 3, 0, 18, SelectionMode::Word);
  expect_text(e, "end\nsecond");
  e.select(1, 3, 0, 18, SelectionMode::Line);
  expect_text(e, "alpha_beta:: e\xCC\x81\xE4\xB8\xAD end\nsecond line");
  e.select(0, 12, 0, 12, SelectionMode::Word);
  expect_text(e, ""); // Existing copy policy trims unmarked spaces.
  Engine history(16, 2);
  feed(history, "old word\r\nnext line\r\nlast");
  history.scroll_view(1);
  history.select(0, 5, 0, 5, SelectionMode::Word);
  expect_text(history, "word");
  history.select(0, 5, 0, 5, SelectionMode::Line);
  expect_text(history, "old word");
  Engine tiny(1, 1);
  feed(tiny, "X");
  tiny.select(-1, -1, 9, 9, SelectionMode::Word);
  expect_text(tiny, "X");
}

void rowmap_is_used_for_text() {
  Engine e(4, 3);
  feed(e, "A\r\nB\r\nC\r\nD");
  e.select(0, 0, 2, 0);
  expect_text(e, "B\nC\nD");
}

void wrapped_copy_preserves_logical_lines() {
  Engine soft(4, 2);
  feed(soft, "abcdef");
  soft.select(0, 0, 1, 3);
  expect_text(soft, "abcdef");
  soft.select(0, 0, 0, 2);
  expect_text(soft, "abc");
  soft.select(1, 0, 1, 3);
  expect_text(soft, "ef");

  Engine crlf(4, 2);
  feed(crlf, "abcd\r\nef");
  crlf.select(0, 0, 1, 3);
  expect_text(crlf, "abcd\nef");

  Engine pending(4, 2);
  feed(pending, "abcd");
  feed(pending, "\r\n");
  feed(pending, "ef");
  pending.select(0, 0, 1, 3);
  expect_text(pending, "abcd\nef");

  Engine spaces(4, 2);
  feed(spaces, "ab  cd");
  spaces.select(0, 0, 1, 3);
  expect_text(spaces, "ab  cd");

  // A wide glyph at the last column creates a synthetic padding cell; copy
  // must use the logical row length and omit that padding.
  Engine wide(4, 2);
  feed(wide, "abc\xE4\xB8\xad");
  wide.select(0, 0, 1, 3);
  expect_text(wide, "abc\xE4\xB8\xad");
  wide.select(1, 0, 1, 0);
  expect_text(wide, "\xE4\xB8\xad");
}

void wrapped_history_resize_and_chunking() {
  Engine e(4, 2);
  feed(e, "old0old1\r\nnew0new1\r\nlast");
  check(e.snapshot().history_rows > 0, "wrapped history was not retained");
  e.scroll_view(999);
  check(e.snapshot().view_offset == e.snapshot().history_rows,
        "history scroll did not clamp");
  e.resize(8, 3);
  check(e.snapshot().view_offset <= e.snapshot().history_rows,
        "history view exceeded resized history");
  e.scroll_view(999);
  check(e.snapshot().view_offset == e.snapshot().history_rows,
        "resized history scroll did not clamp");
  e.select(0, 0, 2, 7);
  expect_text(e, "old0old1\nnew0new1\nlast");
  e.clear_selection();

  Engine narrow(8, 2);
  feed(narrow, "abcdef\r\nz");
  narrow.scroll_view(999);
  narrow.select(0, 0, 0, 7);
  expect_text(narrow, "abcdef");
  narrow.clear_selection();
  narrow.resize(4, 2);
  narrow.scroll_view(999);
  narrow.select(0, 0, 0, 3);
  expect_text(narrow, "abcd");

  const std::string ascii = std::string(700, 'x') + "\r\nend";
  const std::string styled = std::string("\x1b[31m") +
                             std::string(300, 'r') + "\x1b[0m\r\nend";
  for (const std::string &payload : {ascii, styled}) {
    Engine bulk(7, 3), bytes(7, 3);
    feed(bulk, payload);
    for (unsigned char byte : payload)
      bytes.feed(&byte, 1);
    check(bulk.snapshot().history_rows == bytes.snapshot().history_rows,
          "bulk and byte feeds disagree on wrapped history count");
    for (int offset = 0; offset <= bulk.snapshot().history_rows; ++offset) {
      bulk.follow_output();
      bytes.follow_output();
      bulk.scroll_view(offset);
      bytes.scroll_view(offset);
      bulk.select(0, 0, 2, 6);
      bytes.select(0, 0, 2, 6);
      expect_text(bulk, bytes.selected_text());
      bulk.clear_selection();
      bytes.clear_selection();
    }
  }
}

void changes_invalidate_selection() {
  Engine e(8, 2);
  feed(e, "main\r\nline");
  e.select(0, 0, 0, 3);
  feed(e, "");
  expect_text(e, "main");
  feed(e, "!");
  expect_text(e, "");

  e.select(0, 0, 1, 3);
  e.resize(10, 2);
  expect_text(e, "");

  e.select(0, 0, 1, 3);
  feed(e, "\x1b[?1049halt\x1b[?1049l");
  expect_text(e, "");

  e.select(0, 0, 0, 3);
  feed(e, "\x1b"
          "c");
  expect_text(e, "");
}

void wrap_metadata_controls() {
  Engine screens(4, 3);
  feed(screens, "abcdef");
  feed(screens, "\x1b[?47h\x1b[HUVWXYZ\x1b[?47l");
  screens.select(0, 0, 1, 3);
  expect_text(screens, "abcdef");
  feed(screens, "\x1b[?47h");
  screens.select(0, 0, 1, 3);
  expect_text(screens, "UVWXYZ");
  feed(screens, "\x1b[?47l");
  screens.select(0, 0, 1, 3);
  expect_text(screens, "abcdef");

  Engine saved(4, 3);
  feed(saved, "abcdef\x1b[?1049h\x1b[HUVWXYZ\x1b[?1049l");
  saved.select(0, 0, 1, 3);
  expect_text(saved, "abcdef");
  feed(saved, "\x1b[?1049h");
  saved.select(0, 0, 1, 3);
  expect_text(saved, "\n"); // 1049 clears the alternate grid on entry.

  Engine ris(4, 3);
  feed(ris, "abcdef\x1b" "c");
  ris.select(0, 0, 0, 3);
  expect_text(ris, "");

  Engine partial(8, 2);
  feed(partial, "abcdefghij\x1b[1;3H\x1b[1X");
  partial.select(0, 0, 1, 7);
  expect_text(partial, "ab defghij");

  Engine edge(8, 2);
  feed(edge, "abcdefghij\x1b[1;8H\x1b[K");
  edge.select(0, 0, 1, 7);
  expect_text(edge, "abcdefg\nij");

  Engine ich(8, 2);
  feed(ich, "abcdefghij\x1b[1;3H\x1b[2@");
  ich.select(0, 0, 1, 7);
  expect_text(ich, "ab  cdef\nij");

  Engine dch(8, 2);
  feed(dch, "abcdefghij\x1b[1;3H\x1b[2P");
  dch.select(0, 0, 1, 7);
  expect_text(dch, "abefgh\nij");
}

void wrap_metadata_resize_and_history_growth() {
  Engine resized(4, 2);
  feed(resized, "abcdef\x1b[?47h\x1b[HUVWXYZ\x1b[?47l");
  resized.resize(8, 2);
  resized.select(0, 0, 0, 7);
  expect_text(resized, "abcdef");
  feed(resized, "\x1b[?47h");
  resized.select(0, 0, 1, 7);
  expect_text(resized, "UVWXYZ");

  Engine history(4, 2);
  for (int i = 0; i < 80; ++i)
    feed(history, "abcde\r\n");
  check(history.snapshot().history_rows > 128,
        "history metadata growth was not exercised");
  history.scroll_view(999);
  history.select(0, 0, 1, 3);
  expect_text(history, "abcde");
}

void wrap_metadata_row_rotation_boundaries() {
  Engine e(4, 3);
  feed(e, "abcdef");
  feed(e, "\x1b[2;1H\x1b[L");
  e.select(0, 0, 2, 3);
  expect_text(e, "abcd\n\nef");
}

void history_eviction_clears_recycled_wraps() {
  // Seed a soft continuation, then evict more than the ring capacity with
  // hard rows.  A stale positive history_wrap would join the first two rows.
  Engine e(8, 2);
  // Fill every history slot with true soft continuations first.  This makes
  // the oldest retained rows a direct check of metadata copied by eviction.
  feed(e, std::string(8 * 4200, 'a'));
  e.scroll_view(999999);
  e.select(0, 0, 1, 7);
  expect_text(e, std::string(16, 'a'));
  e.scroll_view(-999999);

  std::string payload;
  for (int i = 0; i < 5000; ++i)
    payload += "HARD\r\n";
  feed(e, payload);
  e.scroll_view(999999);
  e.select(0, 0, 1, 7);
  expect_text(e, "HARD\nHARD");
}

void unicode_roundtrip_and_wide_endpoints() {
  Engine e(12, 2);
  feed(e, "e\xCC\x81\xE4\xB8\xAD\xF0\x9F\x98\x80\r\nx");

  e.select(0, 0, 0, 0);
  expect_text(e, "e\xCC\x81");
  e.select(0, 2, 0, 4);
  expect_text(e, "\xE4\xB8\xAD\xF0\x9F\x98\x80");
  e.select(0, 1, 0, 3);
  expect_text(e, "\xE4\xB8\xAD\xF0\x9F\x98\x80");

  Engine wide(3, 1);
  feed(wide, "\xE4\xB8\xAD");
  const auto before = render(wide, 24, 16);
  wide.select(0, 1, 0, 1);
  const auto after = render(wide, 24, 16);
  for (int half = 0; half < 2; ++half) {
    bool changed = false;
    for (int y = 0; y < 16; ++y)
      for (int x = half * 8; x < (half + 1) * 8; ++x)
        changed |= before[static_cast<size_t>(y * 24 + x)] !=
                   after[static_cast<size_t>(y * 24 + x)];
    check(changed, "wide selection did not highlight both cells");
  }
}

void output_workspace_grows() {
  Engine e(2, 1);
  feed(e, "ab");
  e.select(0, 0, 0, 1);
  expect_text(e, "ab");
  e.resize(512, 256);
  feed(e, "\x1b[H");
  feed(e, std::string(512 * 256, 'X'));
  e.select(0, 0, 255, 511);
  std::string expected(512 * 256, 'X');
  expect_text(e, expected);
  e.resize(2, 1);
  feed(e, "\x1b[Hyz");
  e.select(0, 0, 0, 1);
  expect_text(e, "yz");
}
void selected_pixels_are_inverted() {
  Engine e(2, 1);
  feed(e, "\x1b[?25l\x1b[38;2;255;0;0mA ");
  const auto before = render(e, 16, 16);
  e.select(0, 0, 0, 0);
  const auto after = render(e, 16, 16);

  constexpr uint32_t red = 0xFF0000FFu;
  constexpr uint32_t black = 0xFF000000u;
  for (int y = 0; y < 16; ++y)
    for (int x = 0; x < 8; ++x)
      check(after[static_cast<size_t>(y * 16 + x)] ==
                (before[static_cast<size_t>(y * 16 + x)] == red ? black : red),
            "selection did not swap selected colors exactly");
  for (int y = 0; y < 16; ++y)
    for (int x = 8; x < 16; ++x)
      check(before[static_cast<size_t>(y * 16 + x)] ==
                after[static_cast<size_t>(y * 16 + x)],
            "selection changed an unselected cell");
}
} // namespace

int main() {
  struct Test {
    const char *name;
    void (*run)();
  } tests[] = {
      {"forward_reverse_and_clamp", forward_reverse_and_clamp},
      {"word_and_line_selection", word_and_line_selection},
      {"rowmap_is_used_for_text", rowmap_is_used_for_text},
      {"wrapped_copy_preserves_logical_lines",
       wrapped_copy_preserves_logical_lines},
      {"wrapped_history_resize_and_chunking",
       wrapped_history_resize_and_chunking},
      {"changes_invalidate_selection", changes_invalidate_selection},
      {"wrap_metadata_controls", wrap_metadata_controls},
      {"wrap_metadata_resize_and_history_growth",
       wrap_metadata_resize_and_history_growth},
      {"wrap_metadata_row_rotation_boundaries",
       wrap_metadata_row_rotation_boundaries},
      {"history_eviction_clears_recycled_wraps",
       history_eviction_clears_recycled_wraps},
      {"unicode_roundtrip_and_wide_endpoints",
       unicode_roundtrip_and_wide_endpoints},
      {"selected_pixels_are_inverted", selected_pixels_are_inverted},
      {"output_workspace_grows", output_workspace_grows},
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
