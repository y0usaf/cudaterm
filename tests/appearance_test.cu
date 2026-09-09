#include "engine.cuh"
#include <cuda_runtime.h>
#include <stdexcept>
#include <string>
#include <vector>
#include <fstream>
#include <cstring>
#include <unistd.h>

static void check(bool ok, const char *why) { if (!ok) throw std::runtime_error(why); }
static std::string feed(ct::Engine &e, const std::string &text, size_t split) {
  std::string replies;
  for (size_t i = 0; i < text.size(); i += split)
    replies += e.feed_and_replies((const unsigned char *)text.data() + i,
                                  std::min(split, text.size() - i));
  return replies;
}
int main() {
  {
    // A deterministic half-covered glyph verifies alpha, physical cell scaling,
    // configured/default backgrounds, and release of a replaced face atlas.
    std::vector<unsigned char> face(24 + 384 + 4352 * 4 + 256 * 4, 255);
    std::memcpy(face.data(), "CTFACE01", 8);
    uint32_t header[] = {8,24,1,1}, zero = 0;
    std::memcpy(face.data() + 8, header, 16);
    std::fill(face.begin() + 24, face.begin() + 408, 128);
    std::memcpy(face.data() + 408, &zero, 4);
    std::memcpy(face.data() + 408 + 4352 * 4 + 'A' * 4, &zero, 4);
    char path[] = "/tmp/cudaterm-face-XXXXXX";
    int fd = mkstemp(path); check(fd >= 0, "create face fixture"); close(fd);
    { std::ofstream out(path, std::ios::binary); out.write((const char *)face.data(), face.size()); }
    ct::Engine e(4,2);
    e.load_face(path);
    auto retained = e.memory_usage().device_bytes;
    e.load_face(path);
    check(e.memory_usage().device_bytes == retained, "replaced font retained allocations");
    unlink(path);
    e.set_cell_size(12,36);
    e.set_background_opacity(0.5f);
    auto theme = ct::default_theme(); theme.colors[256] = 0xff0000; theme.colors[257] = 0x0000ff;
    e.set_theme(theme);
    check(feed(e, "\033[16t\033[?25lA\033[44m ", 1) == "\033[6;36;12t", "cell query not scaled");
    uint32_t *device; check(cudaMalloc(&device, 48 * 72 * 4) == cudaSuccess, "allocate face raster");
    e.render(device,48,72);
    std::vector<uint32_t> pixels(48 * 72);
    check(cudaMemcpy(pixels.data(), device, pixels.size()*4, cudaMemcpyDeviceToHost) == cudaSuccess,
          "read face raster");
    cudaFree(device);
    check(pixels[0] == 0xc0400080 && pixels[35*48+11] == 0xc0400080, "font alpha/scale incorrect");
    check(pixels[12] == 0xff800000, "explicit background became transparent");
    check(pixels[24] == 0x80800000, "default background opacity incorrect");
    feed(e,"\033[?1000h\033[?1016h",1);
    e.mouse(0,1,1,0,0,10000,10000);
    check(e.take_replies() == "\033[<0;48;72M", "pixel mouse bounds ignored cell size");
  }
  {
    ct::Engine e(4, 2);
    auto theme = ct::default_theme();
    theme.colors[256] = 0xffffff; theme.colors[257] = 0;
    e.set_theme(theme);
    e.set_presentation(3, 5, 2);
    uint32_t *device; check(cudaMalloc(&device, 38 * 42 * 4) == cudaSuccess, "allocate cursor pixels");
    auto pixels = [&] {
      e.render(device, 38, 42);
      std::vector<uint32_t> out(38 * 42);
      check(cudaMemcpy(out.data(), device, out.size() * 4, cudaMemcpyDeviceToHost) == cudaSuccess, "cursor pixels");
      return out;
    };
    for (int style = 1; style <= 6; ++style) {
      auto sequence = std::string("\033[") + std::to_string(style) + " q";
      for (size_t split = 1; split <= sequence.size(); ++split) {
        feed(e, sequence, split);
        check(e.snapshot().cursor_style == style, "split DECSCUSR ignored");
      }
      e.set_cursor_phase(true, true);
      auto out = pixels();
      int ink = 0;
      for (auto pixel : out) ink += pixel != 0xff000000;
      check(ink == (style <= 2 ? 128 : style <= 4 ? 16 : 32), "cursor shape area");
      check(out[0] == 0xff000000 && out[4 * 38 + 3] == 0xff000000, "padding painted as cursor");
      e.set_cursor_phase(false, true);
      out = pixels(); ink = 0; for (auto pixel : out) ink += pixel != 0xff000000;
      check(ink == (style & 1 ? 0 : style <= 2 ? 128 : style <= 4 ? 16 : 32), "blink vs steady cursor");
    }
    e.set_cursor_position(0.5f, 0);
    e.set_cursor_phase(true, true);
    auto moving = pixels();
    check(moving[5 * 38 + 7] == 0xffffffff && moving[5 * 38 + 3] == 0xff000000, "fractional cursor position");
    e.set_cursor_position(0, 0);
    e.set_cursor_phase(true, false);
    auto out = pixels(); int ink = 0; for (auto pixel : out) ink += pixel != 0xff000000;
    check(ink == 44, "unfocused cursor outline");
    feed(e, "\033[99 q", 1); check(e.snapshot().cursor_style == 6, "invalid cursor style accepted");
    feed(e, "\033[?25l\033[3;9;8mX\033[23;29;28mY", 1);
    auto cells = e.cells();
    check((cells[0].flags & (64 | 128 | 256)) == (64 | 128 | 256) &&
          !(cells[1].flags & (64 | 128 | 256)), "text style set/reset");
    out = pixels();
    for (int y = 5; y < 21; ++y) for (int x = 3; x < 11; ++x)
      check(out[y * 38 + x] == 0xff000000, "hidden text rendered");
    feed(e, "\033c", 1); check(e.snapshot().cursor_style == 2, "RIS cursor default");
    theme.customized = 12; theme.colors[260] = 0xffffff; theme.colors[261] = 0x344865;
    e.set_theme(theme);
    feed(e, "\033[?25l\033[2;4mA", 1); e.select(0,0,0,0);
    out = pixels();
    check(out[19 * 38 + 3] == 0xffffffff, "dim text reduced configured selection contrast");
    auto selected = out;
    e.set_copy_flash(true);
    auto flashed = pixels();
    bool yellow = false;
    for (auto pixel : flashed) yellow |= pixel == 0xffafffff;
    check(yellow, "copy flash background");
    check(flashed[5 * 38 + 11] == selected[5 * 38 + 11], "copy flash escaped selection");
    e.set_copy_flash(false);
    check(pixels() == selected, "copy flash did not restore selection styling");
    e.set_copy_flash(true);
    e.select(0, 0, 0, 0);
    check(pixels() == selected, "new selection inherited copy flash");

    cudaFree(device);
  }
  for (size_t split : {size_t(1), size_t(7), size_t(65536)}) {
    ct::Engine e(40, 12);
    auto theme = ct::default_theme();
    theme.colors[256] = 0xaabbcc; theme.colors[257] = 0x112233;
    theme.colors[1] = 0x445566;
    e.set_theme(theme);
    check(feed(e, "\033]10;?\007\033]11;?\033\\\033]4;1;?\007", split) ==
      "\033]10;rgb:aaaa/bbbb/cccc\007\033]11;rgb:1111/2222/3333\033\\"
      "\033]4;1;rgb:4444/5555/6666\007", "theme query mismatch");
    feed(e, "\033[?25lA\033[31mB\033[38;2;68;85;102mC\033[0mD", split);
    feed(e, "\033]4;1;#ff0000\007\033]10;rgb:0/f/0\033\\\033]11;#123456\007", split);
    auto cells = e.cells();
    check(cells[0].fg == 0x00ff00 && cells[0].bg == 0x123456 &&
          cells[1].fg == 0xff0000 && cells[2].fg == 0x445566 && cells[3].fg == 0x00ff00,
          "existing indexed/default/truecolor cells recolored incorrectly");
    uint32_t *pixels;
    check(cudaMalloc(&pixels, 320 * 192 * 4) == cudaSuccess, "allocate raster");
    e.render(pixels, 320, 192);
    uint32_t last;
    check(cudaMemcpy(&last, pixels + 320 * 192 - 1, 4, cudaMemcpyDeviceToHost) == cudaSuccess,
          "read raster");
    cudaFree(pixels);
    check(last == 0xff563412, "GPU raster did not resolve new background");
    e.resize(50, 14);
    feed(e, "\033[?1049h\033[31mZ\033[?1049l", split);
    check(e.cells()[1].fg == 0xff0000, "palette references lost across screen/resize");
    feed(e, "\033]104;1\007\033]110\033\\\033]111\007", split);
    check(e.cells()[0].fg == 0xaabbcc && e.cells()[0].bg == 0x112233 && e.cells()[1].fg == 0x445566,
          "configured palette reset failed");
    feed(e, "\033]2;Finix — Neovim\033\\", split);
    std::string title;
    check(e.take_title(title) && title == "Finix — Neovim" && !e.take_title(title),
          "title metadata mismatch");
    for (const auto &bad : {std::string("\033]2;bad\030"), std::string("\033]2;\xff\007"),
          std::string("\033]2;") + std::string(600, 'x') + "\007"}) {
      feed(e, bad, split);
      check(!e.take_title(title), "malformed title accepted");
    }
    feed(e, "\033]4;1;#zz0000\007\033]10;rgb:1//2\007", split);
    check(e.cells()[1].fg == 0x445566, "malformed OSC changed palette");
    feed(e, "\033]4;1;#abc\007\033c\033[31mR", split);
    check(e.cells()[0].fg == 0x445566 && e.cells()[0].bg == 0x112233,
          "RIS did not preserve configured theme");
    std::string styled;
    for (int i = 0; i < 100; ++i) styled += "\033[31mX\033[0mY\r\n";
    feed(e, styled, split);
    feed(e, "\033]4;1;#123456\007", split);
    bool found = false;
    for (auto c : e.cells()) if (c.cp == 'X') {
      check(c.fg == 0x123456, "styled path flattened palette reference"); found = true;
    }
    check(found, "styled output missing");
  }
}
