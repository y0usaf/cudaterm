#include "engine.cuh"

#include <cstdio>
#include <stdexcept>
#include <string>

namespace {
using ct::Cell;
using ct::Engine;
bool compare_reference = true;
bool equal_cell(const Cell &a, const Cell &b) {
  if (a.cp != b.cp || a.fg != b.fg || a.bg != b.bg || a.flags != b.flags ||
      a.reserved != b.reserved)
    return false;
  for (int i = 0; i < 3; ++i)
    if (a.combining[i] != b.combining[i])
      return false;
  return true;
}
void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}
void check(bool ok, const char *msg) {
  if (!ok)
    throw std::runtime_error(msg);
}
void equivalent(const char *name, int cols, int rows, const std::string &setup,
                std::string payload) {
  const std::string pattern = payload;
  while (payload.size() < 512)
    payload += pattern;
  Engine bulk(cols, rows), bytes(cols, rows);
  feed(bulk, setup);
  feed(bytes, setup);
  feed(bulk, payload);
  if (!compare_reference) {
    feed(bulk, "Z\x1b[6n");
    bulk.cells();
    bulk.snapshot();
    bulk.take_replies();
    return;
  }
  for (unsigned char c : payload)
    bytes.feed(&c, 1);
  feed(bulk, "Z\x1b[6n");
  feed(bytes, "Z\x1b[6n");
  const auto a = bulk.cells(), b = bytes.cells();
  check(a.size() == b.size(), name);
  for (size_t i = 0; i < a.size(); ++i)
    if (!equal_cell(a[i], b[i]))
      check(false, name);
  const auto sa = bulk.snapshot(), sb = bytes.snapshot();
  check(sa.row == sb.row && sa.col == sb.col &&
            sa.cursor_visible == sb.cursor_visible &&
            sa.application_cursor == sb.application_cursor &&
            sa.bracketed_paste == sb.bracketed_paste,
        name);
  check(bulk.take_replies() == bytes.take_replies(), name);
}
std::string repeat(const char *text, int count) {
  std::string out;
  for (int i = 0; i < count; ++i)
    out += text;
  return out;
}

void inherited_colors_lines() {
  equivalent("RGB and inherited attribute resets", 80, 24, "\x1b[1;4;7m",
             "\x1b[38;2;7;99;255mfirst\r\n\x1b[22;27;48;5;18mnext\r\n\x1b[24;"
             "39;49mlast\r\n");
  equivalent("inherited colors across CRLF", 10, 4, "",
             "\x1b[31;44mred\r\nnext\r\n\x1b[0mplain");
}
void blank_lines_background() {
  equivalent("blank lines changing backgrounds", 8, 4, "",
             "\x1b[44m\r\n\x1b[42m\r\nX\x1b[0m");
}
void sgr_flag_transforms() {
  const std::string payload =
      "\x1b[38;2;1;2;4mA\r\n\x1b[22mB\r\n\x1b[48;5;7mC\r\n"
      "\x1b[24mD\r\n\x1b[27mE\r\n\x1b[1;2;4;7mF\r\n"
      "\x1b[0mG\r\n\x1b[38;5;1;48;2;2;4;7mH\r\n"
      "\x1b[7mI\r\n\x1b[22;24;27mJ\r\n" + std::string(512, 'x');
  // Bold=1, underline=2, inverse=4, dim=8. Color components must not
  // act as attribute parameters, including when inheriting flags across lines.
  const uint32_t expected[] = {15, 6, 6, 4, 0, 15, 0, 0, 4, 0};
  for (size_t chunk : {payload.size(), size_t(1), size_t(7)}) {
    Engine e(80, 24);
    feed(e, "\x1b[1;2;4;7m");
    for (size_t pos = 0; pos < payload.size(); pos += chunk)
      feed(e, payload.substr(pos, chunk));
    auto cells = e.cells();
    for (int row = 0; row < 10; ++row) {
      check(cells[row * 80].cp == uint32_t('A' + row), "SGR row glyph");
      check(cells[row * 80].flags == expected[row], "SGR literal flags");
    }
    check(cells[0].fg == 0x010204, "RGB flag-like components");
    check(cells[7 * 80].bg == 0x020407, "mixed indexed/RGB components");
  }
}
void colored_wrap() {
  equivalent("wrap in colored line", 7, 3, "",
             "\x1b[1;32m" + repeat("abcdef", 45) + "\x1b[0m");
}
void pending_wrap() {
  equivalent("pending wrap style transition", 3, 3, "", "ABC\x1b[31mD\x1b[0mE");
}
void partial_initial_line() {
  equivalent("partial initial line", 9, 3, "AB\x1b[38;5;196m",
             "CDE\r\nFGH\x1b[0m");
}
void scrolling_lines() {
  equivalent("scrolling styled CRLF", 6, 3, "",
             "\x1b[36m" + repeat("12345\r\n", 18) + "tail");
}
void trailing_forms() {
  equivalent("trailing no newline", 8, 3, "", "\x1b[35mhello");
  equivalent("trailing SGR", 8, 3, "", "text\x1b[31;4m");
}
void malformed_fallback() {
  equivalent("accepted styled prefix before unsupported control", 10, 3, "",
             repeat("\x1b[32mabc\r\n", 30) + "\x1b[2Jtail");
  equivalent("long line fallback", 80, 24, "",
             std::string(5000, 'A') + "\x1b[31mZ");
  equivalent("unsupported ESC fallback", 10, 3, "", "A\x1bXBC\x1b[?999zDEF");
  equivalent("partial unsupported sequence", 10, 3, "",
             "\x1b]title\x07text\x1bPignored\x1b\\tail");
}
void wide_preexisting() {
  equivalent("wide cells before styled bulk", 12, 4,
             "\x1b[1;2H\xE4\xB8\xAD\x1b[1;1H",
             "\x1b[33m" + repeat("0123456789", 28));
}
void margins_and_autowrap_fallback() {
  equivalent("margins and autowrap fallback", 9, 4,
             "\x1b[2;3r\x1b[?7l\x1b[2;1H",
             "\x1b[34m" + repeat("xy", 90) + "\x1b[?7h\x1b[0m");
}
void bulk_unicode_scalars() {
  equivalent("bulk mixed Unicode scalars", 17, 5, "",
             "\x1b[35mé α 中 😀\r\n\x1b[0mПривет ");
}
void odd_wide_colored_wrap() {
  equivalent("wide early wrap erases existing tail", 16, 64,
             "\x1b[1;15H中\x1b[1;16H", "\x1b[44m中A");
  equivalent("wide after initial pending wrap", 5, 64, "abc中", "中A\r\n");
  equivalent("colored wide glyph early wrap", 5, 5, "",
             "\x1b[1;34m中A中中B\r\n");
}
void combining_boundaries() {
  equivalent("combining line start and SGR boundary", 13, 4, "",
             "\xCC\x81"
             "e\x1b[31m\xCC\x81\xCC\x81\x1b[0m\r\nα\xCC\x81");
}
void preexisting_wide_overwrite() {
  equivalent("preexisting wide tail overwrite", 128, 16,
             "\x1b[1;3H\xE4\xB8\xAD\x1b[1;4H", "\x1b[32mX0123456789");
}
void single_column_replacement() {
  equivalent("single column wide replacement", 1, 4, "", "\x1b[33m中A");
}
void malformed_utf8_suffix() {
  equivalent("accepted Unicode prefix before truncated scalar", 12, 4, "",
             repeat("中α\r\n", 60) + "\xF0\x9F");
  equivalent("malformed UTF-8 suffix", 12, 4, "", "text\xE2");
  equivalent("truncated UTF-8 after style", 12, 4, "", "\x1b[36mα\xF0\x9F");
}
std::string multilingual_lines(int count) {
  const std::string line = "é α 中 😀 \x1b[32mПривет\x1b[0m\r\n";
  std::string out;
  for (int i = 0; i < count; ++i)
    out += line;
  return out;
}
void partial_escape_and_csi() {
  equivalent("CR run reaches line scan bound", 18, 5, "",
             "x" + std::string(4094, '\r') + "\n" + multilingual_lines(20));
  equivalent("CR run exceeds line scan bound", 18, 5, "",
             "x" + std::string(4095, '\r') + "\n" + multilingual_lines(20));
  equivalent("split repeated CR before bulk", 18, 5, "abc\r",
             "\r\n" + multilingual_lines(20));
  equivalent("split CRLF before bulk", 18, 5, "abc\r",
             "\n" + multilingual_lines(20));
  equivalent("leading tab before bulk", 18, 5, "abc",
             "\t" + multilingual_lines(20));
  equivalent("partial ESC before bulk", 18, 5, "\x1b",
             "[31m" + multilingual_lines(20));
  equivalent("partial RGB CSI before bulk", 18, 5, "\x1b[38;2;12;",
             "34;56m" + multilingual_lines(20));
}
void partial_unicode_scalars() {
  equivalent("partial two byte scalar before bulk", 18, 5, "\xC3",
             "\xA9" + multilingual_lines(20));
  equivalent("partial three byte scalar before bulk", 18, 5, "\xE4\xB8",
             "\xAD" + multilingual_lines(20));
  equivalent("partial four byte scalar before bulk", 18, 5, "\xF0\x9F",
             "\x98\x80" + multilingual_lines(20));
}
void partial_osc() {
  equivalent("OSC completes with small remainder", 18, 5, "\x1b]",
             std::string(550, 'x') + "\x07" + std::string(30, 'Y'));
  equivalent("OSC consumes whole feed", 18, 5, "\x1b]", std::string(550, 'x'));
  equivalent("OSC ESC terminator prefix", 18, 5, "\x1b]title",
             "\x1b\\" + multilingual_lines(20));
  equivalent("oversized unfinished OSC fallback", 18, 5, "\x1b]",
             multilingual_lines(300));
}
} // namespace

int main(int argc, char **argv) {
  if (argc == 2 && std::string(argv[1]) == "--bulk-only")
    compare_reference = false;
  else if (argc != 1) {
    std::fprintf(stderr, "usage: styled-test [--bulk-only]\n");
    return 1;
  }
  struct Test {
    const char *name;
    void (*run)();
  } tests[] = {{"inherited_colors_lines", inherited_colors_lines},
               {"sgr_flag_transforms", sgr_flag_transforms},
               {"blank_lines_background", blank_lines_background},
               {"colored_wrap", colored_wrap},
               {"pending_wrap", pending_wrap},
               {"partial_initial_line", partial_initial_line},
               {"scrolling_lines", scrolling_lines},
               {"trailing_forms", trailing_forms},
               {"malformed_fallback", malformed_fallback},
               {"wide_preexisting", wide_preexisting},
               {"margins_autowrap", margins_and_autowrap_fallback},
               {"bulk_unicode", bulk_unicode_scalars},
               {"odd_wide_wrap", odd_wide_colored_wrap},
               {"combining_boundaries", combining_boundaries},
               {"preexisting_wide_overwrite", preexisting_wide_overwrite},
               {"single_column_replacement", single_column_replacement},
               {"malformed_utf8_suffix", malformed_utf8_suffix},
               {"partial_escape_csi", partial_escape_and_csi},
               {"partial_unicode", partial_unicode_scalars},
               {"partial_osc", partial_osc}};
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
