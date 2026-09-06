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
