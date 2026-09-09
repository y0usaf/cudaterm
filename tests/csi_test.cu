#include "engine.cuh"

#include <algorithm>
#include <algorithm>
#include <cstdio>
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
void fail(const char *s) { throw std::runtime_error(s); }
bool same(const Cell &a, const Cell &b) {
  if (a.cp != b.cp || a.fg != b.fg || a.bg != b.bg || a.flags != b.flags ||
      a.reserved != b.reserved)
    return false;
  for (int i = 0; i < 3; ++i)
    if (a.combining[i] != b.combining[i])
      return false;
  return true;
}
void check(bool ok, const char *s) {
  if (!ok)
    fail(s);
}
void expect_cell(Engine &e, int row, int col, uint32_t cp,
                 uint32_t fg = 0xFFFFFF) {
  auto s = e.snapshot();
  auto c = e.cells()[static_cast<size_t>(row * s.cols + col)];
  check(c.cp == cp && c.fg == fg, "unexpected CSI result cell");
}
void invariant(const char *name, const std::string &input) {
  Engine whole(12, 4);
  feed(whole, input);
  const auto expected = whole.cells();
  const auto base = whole.snapshot();
  const auto replies = whole.take_replies();
  for (size_t split = 0; split <= input.size(); ++split) {
    Engine e(12, 4);
    feed(e, input.substr(0, split));
    feed(e, input.substr(split));
    const auto got = e.cells();
    check(got.size() == expected.size(), name);
    for (size_t i = 0; i < got.size(); ++i)
      if (!same(got[i], expected[i]))
        fail(name);
    const auto s = e.snapshot();
    check(s.row == base.row && s.col == base.col &&
              s.cursor_visible == base.cursor_visible &&
              s.application_cursor == base.application_cursor &&
              s.bracketed_paste == base.bracketed_paste,
          name);
    check(e.take_replies() == replies, name);
  }
}
void sgr_defaults() {
  const std::string s = "A\x1b[mB\x1b[31mC\x1b[;mD\x1b[6n";
  invariant("SGR empty/default split", s);
  Engine e(12, 4);
  feed(e, s);
  expect_cell(e, 0, 0, 'A');
  expect_cell(e, 0, 1, 'B');
  expect_cell(e, 0, 2, 'C', 0x800000);
  expect_cell(e, 0, 3, 'D');
  check(e.take_replies() == "\x1b[1;5R", "CSI DSR reply");
}
void device_status_reports() {
  invariant("CSI 5n split", "\x1b[5n");
  Engine status(12, 4);
  feed(status, "\x1b[5n");
  check(status.take_replies() == "\x1b[0n", "CSI 5n status reply");

  for (const std::string &input : {std::string("\x1b[?5n"),
                                    std::string("\x1b[>5n"),
                                    std::string("\x1b[5:n")}) {
    invariant("CSI 5n malformed/private silence", input);
    Engine e(12, 4);
    feed(e, input);
    check(e.take_replies().empty(), "malformed/private CSI 5n replied");
  }

  const std::string overflow = "\x1b[5;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;5n";
  invariant("CSI 5n parameter overflow silence", overflow);
  Engine malformed(12, 4);
  feed(malformed, overflow);
  check(malformed.take_replies().empty(), "overflow CSI 5n replied");

  Engine cursor(12, 4);
  feed(cursor, "\x1b[2;3H\x1b[6n");
  check(cursor.take_replies() == "\x1b[2;3R", "CSI 6n cursor reply changed");
}
void cup_defaults() {
  const std::string s = "A\x1b[;HBC\x1b[2;3HDE";
  invariant("CUP empty/default split", s);
  Engine e(12, 4);
  feed(e, s);
  expect_cell(e, 0, 0, 'B');
  expect_cell(e, 1, 2, 'D');
  expect_cell(e, 1, 3, 'E');
}
void control_string_recovery() {
  for (char introducer : {']', 'P', '_', '^', 'X'}) {
    for (char cancel : {'\x18', '\x1a'}) {
      const std::string input = std::string("A\033") + introducer +
                                "hidden\033" + cancel + "B\033[6n";
      invariant("control string cancellation split", input);
      Engine e(12, 4);
      feed(e, input);
      expect_cell(e, 0, 0, 'A');
      expect_cell(e, 0, 1, 'B');
      expect_cell(e, 0, 2, ' ');
      check(e.take_replies() == "\033[1;3R", "cancelled string query");
    }
  }
  const std::string input = "A\033Xhidden\033\\B\033[6n";
  invariant("SOS terminator split", input);
  Engine e(12, 4);
  feed(e, input);
  expect_cell(e, 0, 1, 'B');
  check(e.take_replies() == "\033[1;3R", "SOS query");
}
void private_modes() {
  const std::string s = "\x1b[?25l\x1b[?1h\x1b[?2004hX\x1b[?1l\x1b[?2004l";
  invariant("private mode split", s);
  Engine e(12, 4);
  feed(e, s);
  auto state = e.snapshot();
  check(!state.cursor_visible && !state.application_cursor &&
            !state.bracketed_paste,
        "private modes");
}
void overflow_and_clamp() {
  const std::string limit = "\x1b[0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;31mX";
  invariant("CSI sixteen parameter split", limit);
  Engine sixteen(12, 4);
  feed(sixteen, limit);
  expect_cell(sixteen, 0, 0, 'X', 0x800000);
  const std::string many = "\x1b[1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17mX";
  invariant("CSI parameter overflow split", many);
  Engine e(12, 4);
  feed(e, many);
  expect_cell(e, 0, 0, 'X');
  const std::string huge = "\x1b[999999999;999999999H@\x1b[999999999C!";
  invariant("CSI huge parameter split", huge);
  Engine h(12, 4);
  feed(h, huge);
  expect_cell(h, 3, 11, '!');
}
void cancellation_and_controls() {
  invariant("C0 embedded in CSI", "A\x1b[31\x07mB");
  invariant("ESC cancels CSI before new CSI", "A\x1b[31\x1b[2JX");
  invariant("CAN cancels CSI", "A\x1b[31\x18mB");
}
void reply_capacity_and_reset() {
  Engine e(12, 4);
  std::string queries, expected;
  for (int i = 0; i < 700; ++i) {
    queries += "\x1b[6n";
    expected += "\x1b[1;1R";
  }
  feed(e, queries);
  check(e.take_replies() == expected.substr(0, 4096),
        "reply capacity retains bounded prefix");
  check(e.take_replies().empty(), "reply capacity drain resets both counts");
  feed(e, "\x1b[6n\x1b" "c");
  e.resize(14, 5);
  check(e.take_replies() == "\x1b[1;1R", "RIS and resize preserve pending replies");
  feed(e, "\x1b[2;3H\x1b[6n");
  check(e.take_replies() == "\x1b[2;3R", "reply buffer accepts fresh output");
}
void combined_feed_replies() {
  auto combined = [](Engine &e, const std::string &s) {
    return e.feed_and_replies(
        reinterpret_cast<const unsigned char *>(s.data()), s.size());
  };
  for (const std::string prefix : {std::string(), std::string(300, 'x'),
                                   std::string(5000, 'x'),
                                   std::string("\x1b[31m") + std::string(300, 'x')}) {
    for (size_t split = 0; split <= 4; ++split) {
      Engine e(12, 4);
      check(combined(e, prefix + "\x1b[2;3H").empty(),
            "combined feed without replies");
      const std::string query = "\x1b[6n";
      std::string reply = combined(e, query.substr(0, split));
      reply += combined(e, query.substr(split));
      check(reply == "\x1b[2;3R", "combined split query completes once");
      check(combined(e, "X\x1b[6n") == "\x1b[2;4R",
            "combined feed observes preceding reset");
      check(e.take_replies().empty(), "combined feed drains reply buffer");
      expect_cell(e, 1, 2, 'X', prefix.rfind("\x1b[31m", 0) == 0 ? 0x800000 : 0xFFFFFF);
      feed(e, "\x1b[6n");
      check(combined(e, "") == "\x1b[2;4R",
            "empty combined feed drains earlier replies");
    }
  }
  Engine partial(12, 4);
  feed(partial, "\x1b[");
  check(combined(partial, "2;3H" + std::string(300, 'x') + "\x1b[H\x1b[6n") ==
            "\x1b[1;1R", "combined feed resumes parser then bulk input");
}
void short_feed_replies_consistency() {
  auto combined = [](Engine &e, const std::string &s) {
    return e.feed_and_replies(
        reinterpret_cast<const unsigned char *>(s.data()), s.size());
  };
  auto payload = [](size_t n) {
    const std::string pattern = "abcXYZ0123456789";
    std::string s;
    for (size_t i = 0; i < n; ++i)
      s += pattern[i % pattern.size()];
    return s;
  };
  auto compare = [](Engine &actual, Engine &expected, const char *message) {
    auto ac = actual.cells();
    auto ec = expected.cells();
    check(ac.size() == ec.size(), message);
    for (size_t i = 0; i < ac.size(); ++i)
      check(same(ac[i], ec[i]), message);
    const auto a = actual.snapshot();
    const auto e = expected.snapshot();
    check(a.cols == e.cols && a.rows == e.rows && a.row == e.row &&
              a.col == e.col && a.history_rows == e.history_rows &&
              a.view_offset == e.view_offset &&
              a.cursor_visible == e.cursor_visible &&
              a.application_cursor == e.application_cursor &&
              a.bracketed_paste == e.bracketed_paste,
          message);
  };
  auto drain = [](Engine &actual, Engine &expected, const char *message) {
    check(actual.take_replies() == expected.take_replies(), message);
  };

  Engine actual(12, 4), expected(12, 4);
  const size_t lengths[] = {1, 4, 7, 63, 255};
  for (size_t i = 0; i < sizeof(lengths) / sizeof(lengths[0]); ++i) {
    const std::string s = payload(lengths[i]);
    if (i % 3 == 0) {
      feed(actual, s);
      feed(expected, s);
      drain(actual, expected, "short feed reply drain");
    } else if (i % 3 == 1) {
      feed(expected, s);
      check(combined(actual, s) == expected.take_replies(),
            "short combined reply");
    } else {
      feed(expected, s + "\x1b[6n");
      feed(actual, s + "\x1b[6n");
      check(combined(actual, "") == expected.take_replies(),
            "empty combined feed drains queued reply");
    }
    compare(actual, expected, "short feed state");
  }

  for (size_t n : {1u, 4u, 7u, 63u, 255u, 1u}) {
    feed(actual, "\033[6n");
    feed(expected, "\033[6n");
    const auto s = payload(n);
    feed(expected, s);
    check(combined(actual, s) == expected.take_replies(),
          "variable short length preserves queued replies");
    compare(actual, expected, "variable short length state");
  }
  const std::string csi = "\x1b[2;3HQ\x1b[6n";
  for (size_t offset = 0; offset < csi.size();) {
    const size_t n = lengths[offset % (sizeof(lengths) / sizeof(lengths[0]))];
    const size_t count = std::min(n, csi.size() - offset);
    const std::string part = csi.substr(offset, count);
    feed(expected, part);
    const std::string got = combined(actual, part);
    check(got == expected.take_replies(), "partial CSI short feed reply");
    offset += count;
    compare(actual, expected, "partial CSI short feed state");
  }

  const std::string bulk(256, 'k');
  feed(expected, bulk);
  check(combined(actual, bulk) == expected.take_replies(),
        "256-byte path reply parity");
  compare(actual, expected, "256-byte path state");

  actual.select(0, 0, 0, 1);
  expected.select(0, 0, 0, 1);
  feed(expected, "Z");
  check(combined(actual, "Z").empty(), "selection short feed reply");
  check(actual.selected_text().empty() == expected.selected_text().empty(),
        "selection cleared by short feed");
  compare(actual, expected, "selection short feed state");

  actual.resize(14, 5);
  expected.resize(14, 5);
  feed(expected, "resize");
  check(combined(actual, "resize") == expected.take_replies(),
        "resize short feed reply");
  compare(actual, expected, "resize short feed state");

  const std::string mouse_mode = "\x1b[?1000h\x1b[?1006h";
  feed(expected, mouse_mode);
  check(combined(actual, mouse_mode) == expected.take_replies(),
        "mouse mode short feed");
  const bool ah = actual.mouse(0, 1, 2, 0, 0);
  const bool eh = expected.mouse(0, 1, 2, 0, 0);
  check(ah == eh, "mouse handling parity");
  drain(actual, expected, "mouse reply parity");
}

void kitty_keyboard_modes() {
  auto feed = [](Engine &e, const std::string &s) {
    e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
  };
  auto split = [&](const std::string &s, auto check_state) {
    for (size_t cut = 0; cut <= s.size(); ++cut) {
      Engine e(12, 4);
      feed(e, s.substr(0, cut));
      feed(e, s.substr(cut));
      check_state(e);
    }
  };

  Engine e(12, 4);
  check(e.snapshot().keyboard_flags == 0, "Kitty keyboard defaults enabled");
  split("\033[?u", [](Engine &state) {
    check(state.take_replies() == "\033[?0u", "Kitty keyboard zero query");
  });
  feed(e, "\033[=31u");
  check(e.snapshot().keyboard_flags == 1,
        "unsupported Kitty flags must not be advertised");
  feed(e, "\033[?u");
  check(e.take_replies() == "\033[?1u", "Kitty keyboard masked query");

  feed(e, "\033[=0;2u");
  check(e.snapshot().keyboard_flags == 1, "Kitty keyboard OR preserves flags");
  feed(e, "\033[=0;3u");
  check(e.snapshot().keyboard_flags == 1, "Kitty keyboard NOT ignores clear zero");
  feed(e, "\033[=1;2u");
  check(e.snapshot().keyboard_flags == 1, "Kitty keyboard OR sets disambiguation");
  feed(e, "\033[=1;3u");
  check(e.snapshot().keyboard_flags == 0, "Kitty keyboard NOT clears disambiguation");

  feed(e, "\033[=1u\033[>0u");
  check(e.snapshot().keyboard_flags == 0, "Kitty keyboard push value");
  feed(e, "\033[<u");
  check(e.snapshot().keyboard_flags == 1, "Kitty keyboard omitted pop count");
  feed(e, "\033[<0u");
  check(e.snapshot().keyboard_flags == 1, "Kitty keyboard explicit zero pop no-op");
  feed(e, "\033[>0 u");
  check(e.snapshot().keyboard_flags == 1, "Kitty keyboard intermediate rejected");

  // Popping eight saved levels is valid and restores the value below the
  // stack. A larger request has no predecessor and resets it.
  feed(e, "\033[=1u");
  for (int i = 0; i < 8; ++i)
    feed(e, "\033[>0u");
  feed(e, "\033[<8u");
  check(e.snapshot().keyboard_flags == 1, "Kitty keyboard full-depth pop");
  for (int i = 0; i < 9; ++i)
    feed(e, "\033[>1u");
  feed(e, "\033[<9u");
  check(e.snapshot().keyboard_flags == 0, "Kitty keyboard over-pop resets");

  feed(e, "\033[=1u\033[?1049h");
  check(e.snapshot().alternate_screen && e.snapshot().keyboard_flags == 0,
        "Kitty keyboard alternate stack starts independently");
  feed(e, "\033[=1u\033[?1049l");
  check(!e.snapshot().alternate_screen && e.snapshot().keyboard_flags == 1,
        "Kitty keyboard primary stack survives alternate screen");
  feed(e, "\033c");
  check(e.snapshot().keyboard_flags == 0, "RIS clears Kitty keyboard modes");
  feed(e, "\033[?1049h\033[?u");
  check(e.take_replies() == "\033[?0u" && e.snapshot().keyboard_flags == 0,
        "RIS clears alternate Kitty keyboard modes");
}
} // namespace

int main() {
  struct Test {
    const char *name;
    void (*run)();
  } tests[] = {{"reply_capacity", reply_capacity_and_reset},
               {"combined_feed_replies", combined_feed_replies},
               {"sgr_defaults", sgr_defaults},
               {"device_status_reports", device_status_reports},
               {"cup_defaults", cup_defaults},
               {"control_string_recovery", control_string_recovery},
               {"private_modes", private_modes},
               {"overflow_and_clamp", overflow_and_clamp},
               {"cancellation_and_controls", cancellation_and_controls},
               {"kitty_keyboard_modes", kitty_keyboard_modes},
               {"short_feed_replies_consistency", short_feed_replies_consistency}};
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
