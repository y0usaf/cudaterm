#include "engine.cuh"

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
void require(bool ok, const char *what) {
  if (!ok)
    throw std::runtime_error(what);
}
std::string screen(Engine &e) {
  const auto s = e.snapshot();
  const auto cells = e.cells();
  std::string out;
  for (int r = 0; r < s.rows; ++r) {
    if (r)
      out += '/';
    for (int c = 0; c < s.cols; ++c)
      out +=
          cells[static_cast<size_t>(r * s.cols + c)].cp < 128
              ? static_cast<char>(cells[static_cast<size_t>(r * s.cols + c)].cp)
              : '?';
  }
  return out;
}
void require_screen(Engine &e, const char *expected, const char *name) {
  const auto got = screen(e);
  require(got == expected, name);
}
void rows(Engine &e, const char *a, const char *b, const char *c,
          const char *d = nullptr) {
  feed(e, "\x1b[1;1H");
  feed(e, a);
  feed(e, "\x1b[2;1H");
  feed(e, b);
  feed(e, "\x1b[3;1H");
  feed(e, c);
  if (d) {
    feed(e, "\x1b[4;1H");
    feed(e, d);
  }
}

void ich_dch_ech() {
  Engine e(8, 1);
  feed(e, "ABCDEFGH\x1b[1;3H\x1b[2@");
  require_screen(e, "AB  CDEF", "ICH shifts and clips");
  Engine d(8, 1);
  feed(d, "ABCDEFGH\x1b[1;3H\x1b[2P");
  require_screen(d, "ABEFGH  ", "DCH shifts and clips");
  Engine x(8, 1);
  feed(x, "ABCDEFGH\x1b[1;3H\x1b[999X");
  require_screen(x, "AB      ", "ECH huge parameter clips");
}
void insert_delete_lines() {
  Engine e(4, 4);
  rows(e, "1111", "2222", "3333", "4444");
  feed(e, "\x1b[2;3r\x1b[2;1H\x1b[1L");
  require_screen(e, "1111/    /2222/4444", "IL respects margins");
  feed(e, "\x1b[2;1H\x1b[1M");
  require_screen(e, "1111/2222/    /4444", "DL respects margins");
}
void scroll_up_down_and_reverse_index() {
  Engine e(4, 4);
  rows(e, "1111", "2222", "3333", "4444");
  feed(e, "\x1b[2;3r\x1b[2;1H\x1b[99S");
  require_screen(e, "1111/    /    /4444", "SU clips to margins");
  feed(e, "\x1b[99T");
  require_screen(e, "1111/    /    /4444", "SD clips to margins");
  feed(e, "\x1b[2;1HZZZZ\x1b[2;1H\x1bM");
  require_screen(e, "1111/    /ZZZZ/4444", "reverse index inserts at margin");
}
void origin_and_autowrap() {
  Engine e(5, 4);
  rows(e, "AAAAA", "BBBBB", "CCCCC", "DDDDD");
  feed(e, "\x1b[2;3r\x1b[?6h\x1b[1;1HX");
  require_screen(e, "AAAAA/XBBBB/CCCCC/DDDDD", "origin maps CUP to margin");
  feed(e, "\x1b[?6l\x1b[1;1HY");
  require_screen(e, "YAAAA/XBBBB/CCCCC/DDDDD",
                 "origin reset maps CUP to screen");
  Engine w(3, 2);
  feed(w, "\x1b[?7lABCD");
  require_screen(w, "ABD/   ", "autowrap off overwrites at right edge");
  feed(w, "\x1b[?7h\x1b[1;1HABCX");
  require_screen(w, "ABC/X  ", "autowrap on advances after edge");
}
void tabs() {
  Engine e(12, 1);
  feed(e, "\x1b[1;5H\x1bH\x1b[1;1H\x1b[IQ");
  require_screen(e, "    Q       ", "HTS and forward tab");
  feed(e, "\x1b[1;5H\x1b[g\x1b[1;1H\x1b[IR");
  require_screen(e, "    Q   R   ", "TBC clears current tab stop");
  feed(e, "\x1b[1;5H\x1bH\x1b[1;7H\x1b[ZS");
  require_screen(e, "    S   R   ", "backtab finds prior stop");
}
void saved_cursor_restores_state() {
  Engine e(8, 1);
  feed(e, "A\x1b"
          "7\x1b[31m\x1b[?25l\x1b"
          "8X");
  const auto s = e.snapshot();
  const auto c = e.cells()[1];
  require(c.cp == 'X' && c.fg == 0xFFFFFF, "saved cursor restores pen");
  require(!s.cursor_visible, "DECRC must not reset cursor visibility");
}
void ris_resets_screens_and_state() {
  Engine e(6, 2);
  feed(e, "main\x1b[2;3H\x1b[31m\x1b[?25l\x1b[?1;2004h\x1b[?1049hALT\x1b"
          "cX");
  require_screen(e, "X     /      ",
                 "RIS clears both screens and returns main");
  auto s = e.snapshot();
  require(s.row == 0 && s.col == 1 && s.cursor_visible &&
              !s.application_cursor && !s.bracketed_paste,
          "RIS resets cursor and modes");
  feed(e, "\x1b[?1049hY\x1b[?1049l");
  require_screen(e, "X     /      ", "RIS clears stale alternate state");
  require(e.cells()[0].fg == 0xFFFFFF && e.cells()[0].bg == 0 &&
              e.cells()[0].flags == 0,
          "RIS resets pen");
  require(e.snapshot().row == 0 && e.snapshot().col == 1,
          "RIS leaves clean saved main cursor");
  Engine large(1, 256);
  feed(large, "中\x1b[?1049h\x1b"
              "cX");
  require(large.cells()[0].cp == 'X', "RIS whole-grid fills fit queue");
}
void private_mode_lists() {
  // Both orders must switch screens AND apply the other listed modes.
  for (const char *modes : {"1049;25;2004;1", "25;2004;1;1049"}) {
    for (size_t split = 0; split <= std::string(modes).size() + 4; ++split) {
      Engine e(6, 2);
      feed(e, "\x1b[?25lmain");
      std::string enter = std::string("\x1b[?") + modes + "h";
      feed(e, enter.substr(0, split));
      feed(e, enter.substr(split));
      require_screen(e, "      /      ", "listed 1049 enters clear screen");
      auto snap = e.snapshot();
      require(snap.cursor_visible && snap.bracketed_paste &&
                  snap.application_cursor,
              "all listed set modes applied");
      feed(e, "\x1b[HALT\x1b[?1049;1049h");
      require_screen(e, "ALT   /      ",
                     "repeated entry preserves alternate contents");
      std::string leave = std::string("\x1b[?") + modes + "l";
      feed(e, leave.substr(0, split));
      feed(e, leave.substr(split));
      require_screen(e, "main  /      ", "listed 1049 restores main screen");
      snap = e.snapshot();
      require(!snap.cursor_visible && !snap.bracketed_paste &&
                  !snap.application_cursor && snap.row == 0 && snap.col == 4,
              "all listed reset modes applied and cursor restored");
      feed(e, "\x1b[?1049;1049lX");
      require_screen(e, "mainX /      ", "repeated exit preserves main cursor");
    }
  }
  Engine ordered(6, 4);
  feed(ordered, "\x1b[2;3r\x1b[?6;1049h\x1b[?1049;6lX");
  require(ordered.cells()[0].cp == 'X', "mode list reset executes in order");
  Engine reverse(6, 4);
  feed(reverse, "\x1b[2;3r\x1b[?6;1049h\x1b[?6;1049lX");
  require(reverse.cells()[6].cp == 'X',
          "mode list restores main origin in order");
}
void private_saved_cursor() {
  for (const char *save : {"\x1b"
                           "7",
                           "\x1b[?1048h"})
    for (const char *restore : {"\x1b"
                                "8",
                                "\x1b[?1048l"}) {
      Engine e(3, 2);
      feed(e, std::string("\x1b[31mABC") + save + "\x1b[32m\x1b[?7l\x1b[2;2H" +
                  restore + "Z");
      require_screen(e, "ABC/Z  ",
                     "private cursor restore retains delayed wrap");
      require(e.cells()[3].fg == 0x800000,
              "private cursor restore retains pen");
    }
  Engine e(6, 4);
  feed(e, "\x1b[2;3r\x1b[?6h\x1b[2;3H\x1b[?1048;25h"
          "\x1b[?6l\x1b[?25;1048l\x1b[6n");
  require(
      e.take_replies() == "\x1b[2;3R" && !e.snapshot().cursor_visible,
      "private cursor restore retains origin and respects listed visibility");
}
void cursor_line_moves() {
  for (const std::string control : {"\x1b[E", "\x1b[0E", "\x1b[2E",
                                    "\x1b[F", "\x1b[0F", "\x1b[2F"}) {
    for (size_t split = 0; split <= control.size(); ++split) {
      Engine e(6, 5);
      feed(e, "\x1b[3;4H");
      feed(e, control.substr(0, split));
      feed(e, control.substr(split));
      const int amount = control.find('2') == std::string::npos ? 1 : 2;
      require(e.snapshot().row == 2 + (control.back() == 'E' ? amount : -amount) &&
                  e.snapshot().col == 0,
              "line movement defaults/counts and split sequences");
      require_screen(e, "      /      /      /      /      ",
                     "line movement leaves cells unchanged");
    }
  }
  Engine e(6, 4);
  feed(e, "\x1b[2;3r\x1b[2;4H\x1b[99E");
  require(e.snapshot().row == 2 && e.snapshot().col == 0,
          "CNL clips at bottom margin");
  feed(e, "\x1b[3;4H\x1b[99F");
  require(e.snapshot().row == 1 && e.snapshot().col == 0,
          "CPL clips at top margin");
  feed(e, "\x1b[?6h\x1b[2;4H\x1b[99F\x1b[6n");
  require(e.take_replies() == "\x1b[1;1R", "CPL retains origin mode");
  Engine edge(3, 2);
  feed(edge, "ABC\x1b[EZ");
  require_screen(edge, "ABC/Z  ", "CNL cancels delayed wrap");
  feed(edge, "\x1b[2;1HXYZ\x1b[99EQ");
  require_screen(edge, "ABC/QYZ", "CNL at screen bottom does not scroll");
  feed(edge, "\x1b[1;1H123\x1b[FQ");
  require_screen(edge, "Q23/QYZ", "CPL at screen top cancels delayed wrap");
}
void vertical_cursor_margin_limits() {
  Engine e(6, 4);
  feed(e, "\x1b[2;3r\x1b[1;4H\x1b[99B");
  require(e.snapshot().row == 2 && e.snapshot().col == 3,
          "CUD stops at bottom margin when starting above it");
  feed(e, "\x1b[4;4H\x1b[99A");
  require(e.snapshot().row == 1 && e.snapshot().col == 3,
          "CUU stops at top margin when starting below it");
  feed(e, "\x1b[4;4H\x1b[99B");
  require(e.snapshot().row == 3, "CUD below margin stops at screen bottom");
  feed(e, "\x1b[1;4H\x1b[99A");
  require(e.snapshot().row == 0, "CUU above margin stops at screen top");
}
void alternate_entry_retains_layout() {
  Engine e(6, 4);
  feed(e, "\x1b[2;3r\x1b[?6h\x1b[2;3H\x1b[?1049hX\x1b[6n");
  require(e.cells()[14].cp == 'X' && e.take_replies() == "\x1b[2;4R",
          "1049 entry preserves cursor, origin and margins");
  feed(e, "\x1b[1;1HY");
  require(e.cells()[6].cp == 'Y', "1049 entry retains CUP origin margin");
  Engine pending(3, 2);
  feed(pending, "ABC\x1b[?1049hZ");
  require_screen(pending, "   /Z  ", "1049 entry retains delayed wrap");
}
void legacy_alternate_screens() {
  for (const char *mode : {"47", "1047"}) {
    const std::string enter = std::string("\x1b[?") + mode + "h";
    const std::string leave = std::string("\x1b[?") + mode + "l";
    for (size_t split = 0; split <= enter.size(); ++split) {
      Engine e(6, 2);
      feed(e, "MAIN\x1b[2;2H\x1b[31m");
      feed(e, enter.substr(0, split));
      feed(e, enter.substr(split));
      require_screen(e, "      /      ", "legacy alternate initially blank");
      require(e.snapshot().row == 1 && e.snapshot().col == 1,
              "legacy entry preserves cursor");
      feed(e, "A" + enter + "B\x1b[32m");
      require_screen(e, "      / AB   ", "repeated legacy entry retains text");
      feed(e, leave.substr(0, split));
      feed(e, leave.substr(split));
      feed(e, "X");
      require_screen(e, "MAIN  /   X  ",
                     "legacy exit preserves current cursor");
      require(e.cells()[9].fg == 0x008000, "legacy exit preserves current pen");
      feed(e, leave + "\x1b[?47h");
      require_screen(
          e, std::string(mode) == "47" ? "      / AB   " : "      /      ",
          "47 retains alternate; 1047 clears on exit");
      feed(e, "\x1b[?47l");
      require_screen(e, "MAIN  /   X  ", "repeated reset preserves primary");
    }
  }
  Engine mixed(6, 2);
  feed(mixed, "MAIN\x1b[?47h\x1b[2;2H\x1b[?1049lX");
  require_screen(mixed, "MAIN  / X    ",
                 "legacy entry cannot restore stale 1049 cursor");
  feed(mixed, "\x1b[?1049h\x1b[2;4H\x1b[?47lY");
  require_screen(mixed, "MAIN  / X Y  ",
                 "legacy exit does not restore 1049 cursor");
  Engine retained(4, 2);
  feed(retained, "MAIN\x1b[?47h\x1b[HOLD\x1b[?47l\x1b[?1047h");
  require_screen(retained, "OLD /    ",
                 "1047 entry retains existing alternate");
  retained.resize(3, 2);
  feed(retained, "\x1b[?1047l");
  require_screen(retained, "MAI/N  ", "resize reflows inactive primary");
  feed(retained, "\x1b[?47h");
  require_screen(retained, "   /   ", "1047 clears resized alternate");
  feed(retained, "X\x1b"
                 "c\x1b[?47h");
  require_screen(retained, "   /   ", "RIS clears legacy alternate");
}
void insert_mode() {
  for (int cols : {80, 512}) {
    for (int count : {1, 7, 32, 35, 64}) {
      Engine shifted(cols, 2);
      std::string original;
      for (int i = 0; i < cols; ++i)
        original += char('0' + i % 10);
      feed(shifted, "\033[31m" + original + "\033[1;11H\033[32m\033[4h" +
                        std::string(count, 'X'));
      const auto cells = shifted.cells();
      for (int i = 0; i < cols; ++i) {
        const bool inserted = i >= 10 && i < 10 + count;
        const uint32_t cp = inserted ? 'X' : original[i < 10 ? i : i - count];
        require(cells[i].cp == cp &&
                    cells[i].fg == (inserted ? 0x008000u : 0x800000u),
                "IRM shifts across warp boundaries without losing cells or pen");
      }
    }
  }
  Engine e(8, 2);
  feed(e, "abcdef\033[1;3H\033[4hXY\033[4lZ");
  require_screen(e, "abXYZdef/        ", "IRM inserts then replaces");
  feed(e, "\033[4h\033cabcdef\033[1;3HX");
  require_screen(e, "abXdef  /        ", "RIS resets IRM");

  Engine wide(8, 2);
  feed(wide, "AB\033[1;2H\033[4h中");
  auto cells = wide.cells();
  require(cells[1].cp == 0x4e2d && (cells[1].flags & 16) &&
              (cells[2].flags & 32) && cells[3].cp == 'B',
          "IRM inserts two cells for a wide glyph");
  feed(wide, "\033c");
  feed(wide, "abcdef中\033[H\033[4hx");
  require_screen(wide, "xabcdef /        ", "IRM repairs clipped wide pair");
  Engine tail(8, 2);
  feed(tail, "中AB\033[1;2H\033[4hx");
  require_screen(tail, " x AB   /        ", "IRM repairs split wide pair");

  Engine wrap(4, 2);
  feed(wrap, "abcdEFGH\033[4hIJ");
  require_screen(wrap, "EFGH/IJ  ", "IRM wraps and scrolls before inserting");
  wrap.scroll_view(1);
  wrap.select(0, 0, 0, 3);
  require(wrap.selected_text() == "abcd", "IRM wrap preserves evicted history");
}
void run_tests() {
  struct Test {
    const char *name;
    void (*run)();
  } tests[] = {{"ich_dch_ech", ich_dch_ech},
               {"insert_mode", insert_mode},
               {"insert_delete_lines", insert_delete_lines},
               {"scroll_reverse_index", scroll_up_down_and_reverse_index},
               {"origin_autowrap", origin_and_autowrap},
               {"tabs", tabs},
               {"saved_cursor", saved_cursor_restores_state},
               {"ris_reset", ris_resets_screens_and_state},
               {"private_mode_lists", private_mode_lists},
               {"private_saved_cursor", private_saved_cursor},
               {"legacy_alternate", legacy_alternate_screens},
               {"alternate_entry_layout", alternate_entry_retains_layout},
               {"vertical_cursor_margins", vertical_cursor_margin_limits},
               {"cursor_line_moves", cursor_line_moves}};
  int failures = 0;
  for (const auto &test : tests)
    try {
      test.run();
    } catch (const std::exception &e) {
      std::fprintf(stderr, "%s: %s\n", test.name, e.what());
      ++failures;
    }
  if (failures)
    throw std::runtime_error("VT regressions failed");
}
} // namespace

int main() {
  try {
    run_tests();
    return 0;
  } catch (const std::exception &e) {
    std::fprintf(stderr, "%s\n", e.what());
    return 1;
  }
}
