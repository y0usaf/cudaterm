#include "engine.cuh"

#include <cstdio>
#include <stdexcept>
#include <string>

namespace {
using ct::Cell;
using ct::Engine;
void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}
void check(bool ok, const char *msg) {
  if (!ok)
    throw std::runtime_error(msg);
}
Cell cell(Engine &e, int row, int col) {
  auto s = e.snapshot();
  return e.cells()[static_cast<size_t>(row * s.cols + col)];
}
void expect_ascii_screen(Engine &e, size_t count, uint32_t cp) {
  auto s = e.snapshot();
  auto cells = e.cells();
  int remainder = count % static_cast<size_t>(s.cols);
  int written = remainder ? remainder : s.cols;
  for (size_t i = 0; i < cells.size(); ++i) {
    uint32_t expected =
        i / static_cast<size_t>(s.cols) < static_cast<size_t>(s.rows - 1) ||
                i % s.cols < static_cast<size_t>(written)
            ? cp
            : 32;
    check(cells[i].cp == expected && cells[i].fg == 0xFFFFFF &&
              cells[i].bg == 0 && cells[i].flags == 0,
          "unexpected full-screen cell");
  }
  check(s.row == s.rows - 1 && s.col == (remainder ? remainder : s.cols - 1),
        "unexpected cursor after bulk feed");
}
std::string ascii(size_t n, char c = 'A') { return std::string(n, c); }
void boundary_feeds() {
  Engine e(80, 24);
  const size_t sizes[] = {65520, 65535, 65536, 65537, 131073, 1u << 20};
  for (size_t n : sizes) {
    feed(e, "\x1b"
            "c");
    feed(e, ascii(n));
    expect_ascii_screen(e, n, 'A');
  }
}
void scratch_reuse() {
  Engine e(80, 24);
  std::string line = "\x1b[38;5;196mé α 中 😀\x1b[0m\r\n";
  std::string large;
  while (large.size() <= 65536)
    large += line;
  feed(e, large);
  check(cell(e, 22, 0).cp == 0xE9 && cell(e, 22, 0).fg == 0xFF0000,
        "large colored Unicode output");
  check(cell(e, 22, 4).cp == 0x4E2D && cell(e, 22, 5).flags == 32,
        "large wide output");
  check(cell(e, 22, 7).cp == 0x1F600 && cell(e, 22, 8).flags == 32,
        "large supplementary output");
  feed(e, "\x1b"
          "c");
  std::string smaller;
  for (int i = 0; i < 32; ++i)
    smaller += line;
  feed(e, smaller);
  check(cell(e, 22, 4).cp == 0x4E2D, "smaller scan reuses workspace");
  feed(e, "\x1b"
          "c\x1b[32mZ");
  Cell z = cell(e, 0, 0);
  check(z.cp == 'Z' && z.fg == 0x008000,
        "small feed after large styled Unicode feed");
  auto s = e.snapshot();
  check(s.row == 0 && s.col == 1, "cursor after scratch reuse");
  feed(e, "\x1b"
          "cQ");
  z = cell(e, 0, 0);
  check(z.cp == 'Q' && z.fg == 0xFFFFFF, "second RIS after scratch reuse");
}
} // namespace

int main() {
  struct Test {
    const char *name;
    void (*run)();
  } tests[] = {{"boundary_feeds", boundary_feeds},
               {"scratch_reuse", scratch_reuse}};
  int failures = 0;
  for (const auto &test : tests)
    try {
      test.run();
    } catch (const std::exception &e) {
      std::fprintf(stderr, "%s: %s\n", test.name, e.what());
      ++failures;
    }
  return failures ? 1 : 0;
}
