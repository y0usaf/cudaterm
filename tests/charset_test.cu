#include "engine.cuh"
#include <cstdio>
#include <cuda_runtime.h>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
void check(bool ok, const char *message) {
  if (!ok)
    throw std::runtime_error(message);
}
void feed(ct::Engine &e, const std::string &s) {
  e.feed((const unsigned char *)s.data(), s.size());
}
std::vector<uint32_t> pixels(ct::Engine &e, int cols, int rows) {
  uint32_t *device = nullptr;
  check(cudaMalloc(&device, cols * rows * 8 * 16 * sizeof(uint32_t)) ==
            cudaSuccess,
        "pixel allocation");
  e.render(device, cols * 8, rows * 16);
  std::vector<uint32_t> out(cols * rows * 8 * 16);
  check(cudaMemcpy(out.data(), device, out.size() * sizeof(uint32_t),
                   cudaMemcpyDeviceToHost) == cudaSuccess,
        "pixel copy");
  cudaFree(device);
  return out;
}
void mapping_and_designation() {
  ct::Engine e(40, 2);
  const std::u32string expected = U"\u00a0◆▒␉␌␍␊°±␤␋┘┐┌└┼⎺⎻─⎼⎽├┤┴┬│≤≥π≠£·";
  std::string bytes;
  for (int c = 0x5f; c <= 0x7e; ++c)
    bytes += char(c);
  feed(e, "\x1b(0" + bytes);
  auto cells = e.cells();
  for (size_t i = 0; i < expected.size(); ++i)
    check(cells[i].cp == expected[i] && !(cells[i].flags & 48),
          "DEC graphic mapping and width");
  feed(e, "\x1b(Bq");
  check(e.cells()[32].cp == 'q', "ASCII designation restored");
}
void streaming_and_shifts() {
  const std::string input = "\x1b)0q\x0eq\x0fq\x1b(0x\x1b(Bq";
  for (size_t split = 0; split <= input.size(); ++split) {
    ct::Engine e(10, 2);
    feed(e, input.substr(0, split));
    feed(e, input.substr(split));
    const std::u32string expected = U"q─q│q";
    auto cells = e.cells();
    for (size_t i = 0; i < expected.size(); ++i)
      check(cells[i].cp == expected[i], "streaming G0/G1 shifts");
  }
  ct::Engine e(10, 2);
  feed(e, "\x1b(\x18q\x1b(\x1a"
          "q\x1b(\x1b(Bq\x1b(\x07"
          "0q\x1b(Zq");
  auto c = e.cells();
  check(c[0].cp == 'q' && c[1].cp == 'q' && c[2].cp == 'q' &&
            c[3].cp == 0x2500 && c[4].cp == 0x2500,
        "designation cancellation C0 and unknown set");
}
void designation_ignores_delete() {
  ct::Engine e(4, 1);
  feed(e, "\x1b(\x7f"
          "0q");
  check(e.cells()[0].cp == 0x2500, "DEL does not cancel designation");
}
void saved_and_reset() {
  for (const auto &pair : {std::pair<std::string, std::string>{"\x1b"
                                                               "7",
                                                               "\x1b"
                                                               "8"},
                           {"\x1b[?1048h", "\x1b[?1048l"}}) {
    ct::Engine e(10, 2);
    feed(e, "\x1b)0\x0e" + pair.first + "\x1b)B\x0f" + pair.second + "q");
    check(e.cells()[0].cp == 0x2500, "saved designations and invoked set");
  }
  ct::Engine e(10, 2);
  feed(e, "\x1b(0\x1b[?1049h\x1b(Bq\x1b[?1049lq");
  check(e.cells()[0].cp == 0x2500, "main charset restored after alternate");
  feed(e, "\x1b"
          "cq");
  check(e.cells()[0].cp == 'q', "RIS resets charsets");
}
void parallel_paths_and_history() {
  for (const std::string &pattern :
       {std::string("lqqk\r\nx  x\r\nmqqj\r\n"),
        std::string("\x1b[31mlqqk\x1b[0m é中\r\n")}) {
    ct::Engine bulk(20, 5), bytes(20, 5);
    feed(bytes, "\x1b(0");
    std::string payload;
    for (int i = 0; i < 30; ++i)
      payload += pattern;
    feed(bulk, "\x1b(0" + payload);
    for (unsigned char byte : payload)
      bytes.feed(&byte, 1);
    auto a = bulk.cells(), b = bytes.cells();
    check(a.size() == b.size(), "bulk cells size");
    for (size_t i = 0; i < a.size(); ++i)
      check(a[i].cp == b[i].cp && a[i].fg == b[i].fg &&
                a[i].flags == b[i].flags,
            "bulk graphics cells");
    int history = bulk.snapshot().history_rows;
    check(history == bytes.snapshot().history_rows, "graphics history count");
    for (int offset = 0; offset <= history; offset += 3) {
      bulk.follow_output();
      bytes.follow_output();
      bulk.scroll_view(offset);
      bytes.scroll_view(offset);
      check(pixels(bulk, 20, 5) == pixels(bytes, 20, 5),
            "bulk history graphics raster");
    }
  }
  ct::Engine dec(8, 3), unicode(8, 3);
  feed(dec, "\x1b[?25l\x1b(0lqqk\r\nx  x\r\nmqqj");
  feed(unicode, "\x1b[?25l┌──┐\r\n│  │\r\n└──┘");
  check(pixels(dec, 8, 3) == pixels(unicode, 8, 3),
        "DEC border matches Unicode raster");
  dec.select(0, 0, 2, 3);
  check(dec.selected_text() == "┌──┐\n│  │\n└──┘",
        "graphics clipboard Unicode");
}
} // namespace
int main() {
  try {
    mapping_and_designation();
    streaming_and_shifts();
    designation_ignores_delete();
    saved_and_reset();
    parallel_paths_and_history();
  } catch (const std::exception &e) {
    std::fprintf(stderr, "%s\n", e.what());
    return 1;
  }
}
