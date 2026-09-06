#include "engine.cuh"

#include <vterm.h>

#include <algorithm>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr int Rows = 4, Cols = 12;
using ct::Cell;
using ct::Engine;

struct Reference {
  VTerm *vt = nullptr;
  VTermState *state = nullptr;
  VTermScreen *screen = nullptr;
  Reference() {
    vt = vterm_new(Rows, Cols);
    if (!vt)
      throw std::runtime_error("vterm_new failed");
    vterm_set_utf8(vt, 1);
    state = vterm_obtain_state(vt);
    screen = vterm_obtain_screen(vt);
    vterm_screen_enable_altscreen(screen, 1);
    vterm_state_set_bold_highbright(state, 0);
    VTermColor fg, bg;
    vterm_color_rgb(&fg, 255, 255, 255);
    vterm_color_rgb(&bg, 0, 0, 0);
    vterm_state_set_default_colors(state, &fg, &bg);
    static const uint32_t palette[] = {0x000000, 0x800000, 0x008000, 0x808000,
                                       0x000080, 0x800080, 0x008080, 0xC0C0C0,
                                       0x808080, 0xFF0000, 0x00FF00, 0xFFFF00,
                                       0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF};
    for (int i = 0; i < 16; ++i) {
      VTermColor c;
      vterm_color_rgb(&c, palette[i] >> 16, (palette[i] >> 8) & 255,
                      palette[i] & 255);
      vterm_state_set_palette_color(state, i, &c);
    }
    vterm_screen_reset(screen, 1);
  }
  ~Reference() {
    if (vt)
      vterm_free(vt);
  }
  void feed(const std::string &s) {
    if (vterm_input_write(vt, s.data(), s.size()) != s.size())
      throw std::runtime_error("vterm_input_write short write");
    vterm_screen_flush_damage(screen);
  }
};

void check(bool ok, const std::string &message) {
  if (!ok)
    throw std::runtime_error(message);
}
void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}
uint32_t rgb(const VTermColor &c) {
  VTermColor z = c;
  if (VTERM_COLOR_IS_DEFAULT_FG(&z))
    return 0xFFFFFF;
  if (VTERM_COLOR_IS_DEFAULT_BG(&z))
    return 0;
  return (uint32_t(z.rgb.red) << 16) | (uint32_t(z.rgb.green) << 8) |
         z.rgb.blue;
}
std::string cell_name(int r, int c) {
  return "cell (" + std::to_string(r) + "," + std::to_string(c) + ")";
}
void compare(Engine &engine, Reference &reference, const char *fixture,
             int chunk) {
  auto s = engine.snapshot();
  auto cells = engine.cells();
  for (int r = 0; r < Rows; ++r) {
    for (int c = 0; c < Cols; ++c) {
      VTermScreenCell v{};
      check(vterm_screen_get_cell(reference.screen, {r, c}, &v),
            std::string(fixture) + " reference cell read");
      const Cell &z = cells[size_t(r * Cols + c)];
      std::string where = std::string(fixture) +
                          " chunk=" + std::to_string(chunk) + " " +
                          cell_name(r, c);
      bool wide = v.width == 2;
      VTermScreenCell prev{};
      bool tail = c > 0 &&
                  vterm_screen_get_cell(reference.screen, {r, c - 1}, &prev) &&
                  prev.width == 2;
      uint32_t cp = v.chars[0] ? v.chars[0] : 32;
      if (tail)
        cp = 0;
      check(z.cp == cp, where + " codepoint expected=" + std::to_string(cp) +
                            " actual=" + std::to_string(z.cp));
      check(((z.flags & 16) != 0) == wide, where + " wide flag");
      check(((z.flags & 32) != 0) == tail, where + " tail flag");
      for (int m = 0; m < 3; ++m)
        check(z.combining[m] == (tail ? 0 : v.chars[m + 1]),
              where + " combining");
      // libvterm tails carry a sentinel and stale pen; their visible pen is
      // the preceding wide cell. Engine stores that pen on both cells.
      VTermScreenCell q = tail ? prev : v;
      vterm_screen_convert_color_to_rgb(reference.screen, &q.fg);
      vterm_screen_convert_color_to_rgb(reference.screen, &q.bg);
      check(z.fg == rgb(q.fg),
            where + " foreground expected=" + std::to_string(rgb(q.fg)) +
                " actual=" + std::to_string(z.fg));
      check(z.bg == rgb(q.bg),
            where + " background expected=" + std::to_string(rgb(q.bg)) +
                " actual=" + std::to_string(z.bg));
      check(((z.flags & 1) != 0) == !!q.attrs.bold, where + " bold");
      check(((z.flags & 2) != 0) == (q.attrs.underline != 0),
            where + " underline");
      check(((z.flags & 4) != 0) == !!q.attrs.reverse, where + " reverse");
    }
  }
  VTermPos pos{};
  vterm_state_get_cursorpos(reference.state, &pos);
  check(s.row == pos.row && s.col == pos.col,
        std::string(fixture) + " cursor chunk=" + std::to_string(chunk) +
            " expected=" + std::to_string(pos.row) + "," +
            std::to_string(pos.col) + " actual=" + std::to_string(s.row) + "," +
            std::to_string(s.col));
}

const char *only_fixture = nullptr;
int cases_run = 0;
void run_steps(const char *name, const std::vector<std::string> &steps) {
  if (only_fixture && std::string(name) != only_fixture)
    return;
  ++cases_run;
  for (int chunk : {0, 1, 7, 256}) {
    Engine e(Cols, Rows);
    Reference ref;
    for (size_t step = 0; step < steps.size(); ++step) {
      const auto &input = steps[step];
      const size_t stride = chunk ? size_t(chunk) : input.size();
      for (size_t p = 0; p < input.size(); p += stride) {
        const auto part = input.substr(p, stride);
        feed(e, part);
        ref.feed(part);
      }
      const std::string label =
          std::string(name) + " step=" + std::to_string(step);
      compare(e, ref, label.c_str(), chunk);
      std::string expected(vterm_output_get_buffer_current(ref.vt), '\0');
      expected.resize(
          vterm_output_read(ref.vt, expected.data(), expected.size()));
      check(e.take_replies() == expected,
            label + " reference reply chunk=" + std::to_string(chunk));
    }
  }
}
void run_case(const char *name, const std::string &input) {
  run_steps(name, {input});
}

void checkpoint_fixtures() {
  run_steps("readline_checkpoints",
            {"$ echo abc", "\033[3D", "\033[2@", "XY", "\033[P", "\r", "$ ",
             "\033[K", "echo done", "\r\n", "done\r\n", "$ "});
  run_steps("margin_checkpoints",
            {"111111111111\r\n222222222222\r\n333333333333\r\n444444444444",
             "\033[2;3r", "\033[2;1H", "\033[L", "new", "\033[2;1H", "\033[M",
             "\033[3;1H", "last\n", "\033[r", "\033[1;1H", "\033[99B",
             "\033[99A"});
  run_steps("saved_pen_checkpoints",
            {"\033[31mA", "\0337", "\033[1;4;7;32m", "\033[2;3HZ", "\0338", "Q",
             "\033[0m", "R", "\033[6n"});
  run_steps("wrap_checkpoints",
            {"123456789012", "\033[31m", "Z", "\033[H", "\033[2J", "\033[4;1H",
             "123456789012", "Q", "\033[6n"});
  run_steps("cursor_line_moves",
            {"abcdef", "\033[0E", "A", "\033[3;6H", "\033[0F", "B",
             "\033[2;4H", "\033[2E", "C", "\033[4;5H", "\033[99E", "D",
             "\033[1;1H123456789012", "\033[0F", "Z", "\033[0E", "Q"});
  // Keep generated moves on full-screen margins: libvterm 0.3.3 does not
  // clamp CUU/CUD to margins with origin off. Dedicated VT tests check DEC
  // margin semantics; this independent comparison must not override them.
  // Fixed seed and bounded operation vocabulary make every prefix reproducible.
  const std::vector<std::string> operations = {
      "abc",     "0123456789AB", "\r",         "\n",          "\b",
      "\t",      "\033[H",       "\033[4;12H", "\033[2;3H",   "\033[A",
      "\033[2B", "\033[3C",      "\033[2D",    "\033[2@",     "\033[2P",
      "\033[3X", "\033[K",       "\033[1K",    "\033[2J",     "\033[L",
      "\033[M",  "\033[S",       "\033[T",     "\033[31;44m", "\033[1;4;7m",
      "\033[0m", "\033[6n"};
  std::vector<std::string> steps;
  uint32_t seed = 0x43554441u;
  for (int i = 0; i < 128; ++i) {
    seed = seed * 1664525u + 1013904223u;
    steps.push_back(operations[seed % operations.size()]);
  }
  run_steps("mixed_edit_checkpoints", steps);
}
void fixtures() {
  run_case("ascii_wrap_scroll", "0123456789AB\r\nsecond\r\nthird\r\nfourth");
  run_case("ascii_bulk_wrap_scroll",
           std::string(700, 'x') + "\r\nline-two\r\nline-three\r\nend");
  run_case("ascii_bulk_query", std::string(700, 'x') + "\033[6n");
  run_steps("ascii_bulk_short_tail",
            {std::string(700, 'x') + "\033[31m中e\xCC\x81", "Z\033[6n"});
  for (int prefix : {255, 256})
    for (int tail : {255, 256})
      run_case(("ascii_tail_boundary_" + std::to_string(prefix) + "_" +
                std::to_string(tail)).c_str(),
               std::string(prefix, 'x') + "\033[31m" +
                   std::string(tail - 5, 'y'));
  run_case("sgr_colors", "\033[31;4mred\033[0m \033[38;5;10;48;2;1;2;3mgreen");
  run_case("styled_bulk_attributes",
           "\033[1;7;4m" + std::string(700, 'A') + "\033[22;27;24m\r\nplain");
  run_case("styled_rejected_long_line",
           std::string(5000, 'x') + "\033[31m" + std::string(300, 'y') +
               "\033[6n");
  run_steps("styled_rejected_short_prefix",
            {"\033[2J" + std::string(700, 'x') + "\033[6n", "Z"});
  run_case("cursor_erase_edit_margin",
           "abcdef\033[2;3H\033[2P\033[2J\033[2;3r\033[2;1Hxy\r\nzz");
  run_case("margin_edit_persists",
           "111111111111\r\n222222222222\r\n333333333333\r\n444444444444"
           "\033[2;3r\033[2;1H\033[2L\033[2;1HAA\033[1M");
  run_case("character_insert", "abcdef\033[1;3H\033[2@XY");
  run_case("character_delete", "abcdef\033[1;3H\033[2P");
  run_case("character_erase", "abcdef\033[44m\033[1;3H\033[2X");
  run_case("alternate_1049_entry_margin",
           "\033[2;3r\033[?6h\033[2;3H\033[?1049hALT");
  run_case("alternate_1049_entry_wrap", "123456789012\033[?1049hZ");
  run_case("tabs", "a\tb\t\033[3g\033[1;1Hc\t");
  run_case("unicode", "é中e\xCC\x81 😀");
  run_case("dec_graphics", "\033)0\016lqqk\017");
  run_case("alternate_1049_entry_cursor", "main\033[2;3H\033[?1049hALT");
  run_case("alternate_1049", "main\033[2;3H\033[?1049hALT\033[?1049l");
  run_case("query", "abc\033[6n");
  run_case("string_cancel_can",
           "\033]osc-can\030OSC\033Pdcs-can\030DCS\033_apc-can\030APC"
           "\033^pm-can\030PM\033Xsos-can\030SOS\033[6n");
  run_case("string_cancel_sub",
           "\033]osc-sub\032OSC\033Pdcs-sub\032DCS\033_apc-sub\032APC"
           "\033^pm-sub\032PM\033Xsos-sub\032SOS\033[6n");
  run_steps("string_cancel_split", {"\033]split-osc", "\033",
                                      "\030OSC\033Psplit-dcs", "\033",
                                      "\032DCS\033_split-apc", "\033",
                                      "\030APC\033^split-pm", "\033",
                                      "\032PM\033Xsplit-sos", "\033",
                                      "\030SOS\033[6n"});
  run_case("string_sos_st", "\033Xhidden-sos\033\\VISIBLE\033[6n");
  std::string bulk_strings;
  for (const char *intro : {"\033]", "\033P", "\033_", "\033^", "\033X"}) {
    bulk_strings += intro;
    bulk_strings += std::string(400, 'h');
    bulk_strings += '\030';
    bulk_strings += "VISIBLE";
  }
  bulk_strings += "\033[6n";
  run_case("string_cancel_bulk_resume", bulk_strings);
  run_steps("irm_ascii", {"abc", "\033[1;2H\033[4h", "X", "Y",
                           "\033[4l", "Z"});
  run_steps("irm_bulk_disable",
            {"\033[2J\033[1;1H\033[4h", std::string(700, 'a'),
             "\033[4l", "\033[1;1HZ\033[6n"});
  run_case("irm_ris_disables", "abc\033[4h\033cabc\033[1;1HX");
  run_case("irm_global_deccsc", "abc\033[1;2H\033[4h\0337\033[4l\0338X");
  run_case("irm_global_1049",
           "abc\033[4h\033[?1049hALT\033[4l\033[?1049l\033[1;1HX");
  run_case("irm_wide_pair", "A中B\033[1;2H\033[4hX\033[4l");
  // libvterm 0.3.3 shifts one cell even for a width-two insertion. Literal VT
  // tests cover width-sized insertion, matching XTerm's visual_width handling.
  run_case("irm_combining_attaches",
           "Ae\314\201B\033[1;2H\033[4hX\314\201\033[4l");
}
} // namespace

int main(int argc, char **argv) {
  try {
    if (argc > 2)
      throw std::runtime_error("usage: reference-test [fixture]");
    if (argc == 2)
      only_fixture = argv[1];
    fixtures();
    checkpoint_fixtures();
    check(cases_run != 0, "unknown reference fixture");
  } catch (const std::exception &e) {
    std::fprintf(stderr, "reference-test: %s\n", e.what());
    return 1;
  }
  return 0;
}
