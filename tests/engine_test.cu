#include "engine.cuh"

#include <cuda_runtime.h>

#include <cstdio>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using ct::Cell;
using ct::Engine;
using ct::Snapshot;

void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}

Cell cell(const Engine &e, int row, int col) {
  auto &mutable_engine = const_cast<Engine &>(e);
  Snapshot s = mutable_engine.snapshot();
  auto cells = mutable_engine.cells();
  return cells[static_cast<size_t>(row * s.cols + col)];
}

void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

bool same_cells(const std::vector<Cell> &a, const std::vector<Cell> &b) {
  if (a.size() != b.size())
    return false;
  for (size_t i = 0; i < a.size(); ++i)
    if (a[i].cp != b[i].cp || a[i].fg != b[i].fg || a[i].bg != b[i].bg ||
        a[i].flags != b[i].flags)
      return false;
  return true;
}

void require_cell(const Engine &e, int row, int col, uint32_t cp,
                  uint32_t fg = 0xFFFFFF, uint32_t bg = 0x000000,
                  uint32_t flags = 0) {
  Cell c = cell(e, row, col);
  require(c.cp == cp && c.fg == fg && c.bg == bg && c.flags == flags,
          "unexpected screen cell");
}

void cursor_params() {
  Engine e(8, 3);
  feed(e, "A\x1b[2;3HB");
  require_cell(e, 0, 0, 'A');
  require_cell(e, 1, 2, 'B');
  feed(e, "\x1b[;H");
  auto s = e.snapshot();
  require(s.row == 0 && s.col == 0,
          "empty cursor parameters must default to one");
  feed(e, "\x1b[2C\x1b[2B\x1b[3GZ");
  require_cell(e, 2, 2, 'Z');
}

void erase_defaults() {
  Engine e(6, 2);
  feed(e, "abcdef\r\nUVWXYZ\x1b[1;3H\x1b[J");
  require_cell(e, 0, 0, 'a');
  require_cell(e, 0, 1, 'b');
  require_cell(e, 0, 2, 32);
  require_cell(e, 1, 0, 32);
  feed(e, "\x1b[1;2H12\x1b[K");
  require_cell(e, 0, 1, '1');
  require_cell(e, 0, 2, '2');
  require_cell(e, 0, 5, 32);
}

void streaming_sequences() {
  Engine e(8, 2);
  feed(e, "A\x1b[");
  feed(e, "31mB");
  require_cell(e, 0, 0, 'A');
  require_cell(e, 0, 1, 'B', 0x800000);

  feed(e, "\r\n");
  const std::string euro = "\xE2\x82\xAC";
  feed(e, euro.substr(0, 1));
  feed(e, euro.substr(1, 1));
  feed(e, euro.substr(2));
  require_cell(e, 1, 0, 0x20AC, 0x800000);
}

void malformed_utf8() {
  Engine e(8, 2);
  const unsigned char bytes[] = {'X', 0xE2, 'Y', 0xFF, 'Z'};
  e.feed(bytes, sizeof(bytes));
  require_cell(e, 0, 0, 'X');
  require_cell(e, 0, 1, 0xFFFD);
  require_cell(e, 0, 2, 'Y');
  require_cell(e, 0, 3, 0xFFFD);
  require_cell(e, 0, 4, 'Z');
}

void sgr_colors() {
  Engine e(10, 2);
  feed(e, "\x1b[38;5;196mA\x1b[48;5;25mB\x1b[38;2;1;2;3mC");
  require_cell(e, 0, 0, 'A', 0xFF0000);
  require_cell(e, 0, 1, 'B', 0xFF0000, 0x005FAF);
  require_cell(e, 0, 2, 'C', 0x010203, 0x005FAF);
}

void delayed_wrap() {
  Engine e(2, 2);
  feed(e, "AB\x1b[31mC");
  require_cell(e, 0, 0, 'A');
  require_cell(e, 0, 1, 'B');
  require_cell(e, 1, 0, 'C', 0x800000);
}

void margin_scroll() {
  Engine e(4, 5);
  feed(e, "0\r\n1\r\n2\r\n3\r\n4");
  feed(e, "\x1b[2;4r\x1b[4;1H\n");
  require_cell(e, 0, 0, '0');
  require_cell(e, 1, 0, '2');
  require_cell(e, 2, 0, '3');
  require_cell(e, 3, 0, 32);
  require_cell(e, 4, 0, '4');

  feed(e, "\x1b[5;1H\n");
  auto s = e.snapshot();
  require(s.row == 4, "LF below the scrolling margin must clamp safely");
}

void alternate_screen() {
  Engine e(6, 3);
  feed(e, "main\x1b[2;4H\x1b[?1049h");
  auto entered = e.snapshot();
  require(entered.row == 1 && entered.col == 3,
          "1049 entry must preserve cursor position");
  require_cell(e, 0, 0, 32);
  feed(e, "alt\x1b[?1049l");
  auto restored = e.snapshot();
  require(restored.row == 1 && restored.col == 3,
          "1049 must restore main cursor");
  require_cell(e, 0, 0, 'm');
}

void modes_and_replies() {
  Engine e(8, 2);
  feed(e, "\x1b[?25l\x1b[?1h\x1b[?2004h");
  auto s = e.snapshot();
  require(!s.cursor_visible && s.application_cursor && s.bracketed_paste,
          "private cursor and bracketed paste modes");
  feed(e, "\x1b[?1l\x1b[?2004l");
  s = e.snapshot();
  require(!s.application_cursor && !s.bracketed_paste, "mode resets");

  feed(e, "\x1b[6n");
  require(e.take_replies() == "\x1b[1;1R", "DSR reply must be exact");
  feed(e, "\x1b[c");
  require(e.take_replies() == "\x1b[?1;2c", "DA reply must contain no NUL");
}

void resize_preserves_grids() {
  Engine e(5, 3);
  feed(e, "main");
  feed(e, "\x1b[?1049hALT");
  e.resize(7, 4);
  feed(e, "\x1b[?1049l");
  require_cell(e, 0, 0, 'm');
  Snapshot s = e.snapshot();
  require(s.cols == 7 && s.rows == 4, "resize dimensions");
}

void invalid_dimensions() {
  bool zero = false, huge = false;
  try {
    Engine e(0, 2);
  } catch (const std::exception &) {
    zero = true;
  }
  try {
    Engine e(513, 2);
  } catch (const std::exception &) {
    huge = true;
  }
  require(zero && huge, "invalid dimensions must throw");
}

void render_pixels() {
  Engine e(2, 1);
  feed(e, "\x1b[?25l\x1b[101m A");
  uint32_t *device = nullptr;
  require(cudaMalloc(&device, 16 * 16 * sizeof(uint32_t)) == cudaSuccess,
          "cudaMalloc render buffer");
  e.render(device, 16, 16);
  std::vector<uint32_t> pixels(16 * 16);
  const auto status =
      cudaMemcpy(pixels.data(), device, pixels.size() * sizeof(uint32_t),
                 cudaMemcpyDeviceToHost);
  cudaFree(device);
  require(status == cudaSuccess, "cudaMemcpy render buffer");
  const uint32_t red = 0xFF0000FFu; // Little-endian memory bytes R,G,B,A.
  require(pixels[0] == red, "blank background must render exact red RGBA");
  bool glyph_pixel = false;
  for (size_t y = 0; y < 16; ++y)
    for (size_t x = 8; x < 16; ++x)
      glyph_pixel |= pixels[y * 16 + x] != red;
  require(glyph_pixel, "A glyph must render a non-background pixel");
}

void chunk_invariance() {
  const std::string sample = "A\x1b]0;title\x07\x1b[38;5;196m\xE2\x82\xAC"
                             "B";
  Engine whole(12, 2);
  feed(whole, sample);
  const auto expected = whole.cells();
  const auto base = whole.snapshot();
  for (size_t split = 0; split <= sample.size(); ++split) {
    Engine e(12, 2);
    feed(e, sample.substr(0, split));
    feed(e, sample.substr(split));
    require(same_cells(e.cells(), expected), "split feed changed cells");
    const auto s = e.snapshot();
    require(s.row == base.row && s.col == base.col &&
                s.cursor_visible == base.cursor_visible &&
                s.application_cursor == base.application_cursor &&
                s.bracketed_paste == base.bracketed_paste,
            "split feed changed snapshot");
  }
}

} // namespace

int main() {
  struct Test {
    const char *name;
    void (*run)();
  } tests[] = {
      {"cursor_params", cursor_params},
      {"erase_defaults", erase_defaults},
      {"streaming_sequences", streaming_sequences},
      {"malformed_utf8", malformed_utf8},
      {"sgr_colors", sgr_colors},
      {"delayed_wrap", delayed_wrap},
      {"margin_scroll", margin_scroll},
      {"alternate_screen", alternate_screen},
      {"modes_and_replies", modes_and_replies},
      {"resize_preserves_grids", resize_preserves_grids},
      {"render_pixels", render_pixels},
      {"chunk_invariance", chunk_invariance},
      {"invalid_dimensions", invalid_dimensions},
  };
  int failures = 0;
  for (const auto &test : tests) {
    try {
      test.run();
    } catch (const std::exception &ex) {
      std::cerr << test.name << ": " << ex.what() << '\n';
      ++failures;
    } catch (...) {
      std::cerr << test.name << ": unknown failure\n";
      ++failures;
    }
  }
  return failures ? 1 : 0;
}
