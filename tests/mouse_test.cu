#include "engine.cuh"

#include <cstdio>
#include <stdexcept>
#include <string>

namespace {
using ct::Engine;

constexpr int Shift = 4, Alt = 8, Ctrl = 16;

void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}
void check(bool ok, const char *what) {
  if (!ok)
    throw std::runtime_error(what);
}
void mode(Engine &e, int n, bool on) {
  feed(e, "\033[?" + std::to_string(n) + (on ? "h" : "l"));
}
void expect_mode_splits(const std::string &setup, const std::string &expected) {
  for (size_t split = 0; split <= setup.size(); ++split) {
    Engine e(12, 4);
    feed(e, setup.substr(0, split));
    feed(e, setup.substr(split));
    check(e.mouse(0, 1, 2, Shift | Alt | Ctrl, 0),
          "split mouse mode tracking");
    check(e.take_replies() == expected, "split mouse mode sequence");
  }
}
std::string legacy(int button, int col, int row, int modifiers = 0,
                   bool motion = false) {
  return std::string("\033[M") +
         std::string(1, static_cast<char>(32 + button + modifiers +
                                           (motion ? 32 : 0))) +
         std::string(1, static_cast<char>(33 + col)) +
         std::string(1, static_cast<char>(33 + row));
}

void sgr_press_release_and_modifiers() {
  Engine e(12, 4);
  mode(e, 1000, true);
  mode(e, 1006, true);
  check(e.mouse(0, 1, 2, Shift | Alt | Ctrl, 0), "SGR press tracking");
  check(e.take_replies() == "\033[<28;3;2M", "SGR modified press");
  check(e.mouse(0, 1, 2, Shift | Alt | Ctrl, 1), "SGR release tracking");
  check(e.take_replies() == "\033[<28;3;2m", "SGR modified release");
  check(e.mouse(64, 0, 0, 0, 0), "SGR wheel tracking");
  check(e.take_replies() == "\033[<64;1;1M", "SGR wheel up");
  check(e.mouse(65, 0, 0, 0, 1), "SGR wheel release tracking");
  check(e.take_replies().empty(), "wheel release suppressed");
}

void legacy_and_split_sequences() {
  expect_mode_splits("\033[?1000;1006h", "\033[<28;3;2M");
  const std::string setup = "\033[?1000h";
  expect_mode_splits(setup, legacy(0, 2, 1, 28));
  Engine e(12, 4);
  feed(e, setup);
  check(e.mouse(0, 1, 2, Shift | Alt | Ctrl, 0), "legacy press tracking");
  check(e.take_replies() == legacy(0, 2, 1, 28), "legacy modified press");
  check(e.mouse(0, 1, 2, Shift, 1), "legacy release tracking");
  check(e.take_replies() == legacy(3, 2, 1, Shift), "legacy release");
}

void motion_modes_and_dedup() {
  Engine e(12, 4);
  mode(e, 1002, true);
  check(e.mouse(3, 0, 0, 0, 2), "1002 owns unpressed motion");
  check(e.take_replies().empty(), "1002 suppresses unpressed motion");
  check(e.mouse(0, 1, 1, 0, 0), "button motion press tracking");
  check(e.take_replies() == legacy(0, 1, 1), "button motion press");
  check(e.mouse(0, 1, 2, 0, 2), "button motion active tracking");
  check(e.take_replies() == legacy(0, 2, 1, 0, true),
        "button motion event");
  check(e.mouse(0, 1, 2, 0, 2), "deduplicated motion tracking");
  check(e.take_replies().empty(), "same-cell motion deduplication");
  check(e.mouse(0, 1, 3, 0, 2), "button motion moved tracking");
  check(e.take_replies() == legacy(0, 3, 1, 0, true),
        "button motion moved event");

  Engine all(12, 4);
  mode(all, 1003, true);
  check(all.mouse(3, 2, 2, 0, 2), "all motion tracking");
  check(all.take_replies() == legacy(3, 2, 2, 0, true),
        "all motion without button");
}

void sgr_mode_and_legacy_coordinates() {
  Engine e(300, 2);
  mode(e, 1000, true);
  check(e.mouse(0, 0, 222, 0, 0), "legacy maximum coordinate");
  check(e.take_replies() == legacy(0, 222, 0), "legacy maximum coordinate bytes");
  check(e.mouse(0, 0, 223, 0, 0), "legacy out of range tracking");
  check(e.take_replies().empty(), "legacy out of range suppressed");
  mode(e, 1006, true);
  check(e.mouse(0, 1, 299, 0, 0), "SGR coordinate tracking");
  check(e.take_replies() == "\033[<0;300;2M", "SGR coordinate encoding");
  e.resize(4, 2);
  check(e.mouse(0, 99, 99, 0, 0), "mouse coordinate clamp tracking");
  check(e.take_replies() == "\033[<0;4;2M", "mouse coordinate clamp");
}

void disabled_and_history_view() {
  Engine e(8, 2);
  check(!e.mouse(0, 0, 0, 0, 0), "mouse disabled");
  check(e.take_replies().empty(), "disabled mouse reply");
  mode(e, 1006, true);
  check(!e.mouse(0, 0, 0, 0, 0), "SGR alone does not enable tracking");
  mode(e, 1000, true);
  mode(e, 1000, false);
  check(!e.mouse(0, 0, 0, 0, 0), "DEC reset disables tracking");
  mode(e, 1000, true);
  feed(e, "a\r\nb\r\nc");
  e.scroll_view(100);
  check(!e.mouse(0, 0, 0, 0, 0), "history mouse return state");
  check(e.take_replies().empty(), "history mouse suppressed");
  e.follow_output();
  check(e.mouse(0, 0, 0, 0, 0), "live mouse return state");
}

void ris_clears_tracking() {
  Engine e(8, 2);
  mode(e, 1000, true);
  feed(e, "\033c");
  check(!e.mouse(0, 0, 0, 0, 0), "RIS clears mouse tracking");
  check(e.take_replies().empty(), "RIS mouse reply");
}
void ekko_modes() {
  {
    Engine e(12, 4);
    const std::string first = "\033[?2026hA\033[?2026l";
    const std::string next = "\033[?2026hB\033[?2026l";
    const std::string batch = first + next;
    auto r = e.feed_frame(reinterpret_cast<const unsigned char *>(batch.data()), batch.size());
    check(r.frame_complete && r.consumed == first.size(), "stop before next coalesced frame");
    e.take_replies();
    check(!e.synchronized_updates() && e.snapshot().col == 1, "completed frame retained");
    r = e.feed_frame(reinterpret_cast<const unsigned char *>(batch.data()+r.consumed), next.size());
    check(r.frame_complete && r.consumed == next.size(), "consume second frame once");
    check(e.snapshot().col == 2, "second frame state");
    for (size_t split = 1; split < first.size(); ++split) {
      r = e.feed_frame(reinterpret_cast<const unsigned char *>(first.data()), split);
      check(!r.frame_complete && r.consumed == split, "split frame prefix");
      r = e.feed_frame(reinterpret_cast<const unsigned char *>(first.data()+split), first.size()-split);
      check(r.frame_complete && r.consumed == first.size()-split, "split frame end");
    }
  }
  const std::string setup = "\033[?1003;1006;1016;1004;2026h\033[16t";
  for (size_t split = 0; split <= setup.size(); ++split) {
    Engine e(12, 4);
    feed(e, setup.substr(0, split));
    feed(e, setup.substr(split));
    check(e.take_replies() == "\033[6;16;8t", "cell pixel dimensions");
    check(e.synchronized_updates() && e.snapshot().synchronized_updates,
          "synchronized update enabled");
    e.mouse(0, 1, 2, 0, 0, 19, 23);
    check(e.take_replies() == "\033[<0;20;24M", "pixel press");
    e.mouse(66, 1, 2, 0, 0, 19, 23);
    e.mouse(67, 1, 2, 0, 0, 19, 23);
    check(e.take_replies() == "\033[<66;20;24M\033[<67;20;24M", "horizontal wheel");
    e.mouse(0, 1, 2, 0, 2, 20, 23);
    check(e.take_replies() == "\033[<32;21;24M", "within-cell pixel motion");
    e.focus(false); e.focus(true);
    check(e.take_replies() == "\033[O\033[I", "focus reports");
    feed(e, "\033[?1016;1004;2026l");
    e.focus(false);
    check(e.take_replies().empty() && !e.synchronized_updates(), "mode reset");
    e.mouse(0, 1, 2, 0, 0, 19, 23);
    check(e.take_replies() == "\033[<0;3;2M", "cell reports restored");
    feed(e, setup + "\033c"); e.take_replies();
    e.focus(true);
    check(e.take_replies().empty() && !e.synchronized_updates(), "RIS modes");
  }
}
} // namespace

int main() {
  struct Test {
    const char *name;
    void (*run)();
  } tests[] = {{"sgr_press_release_and_modifiers",
                sgr_press_release_and_modifiers},
               {"legacy_and_split_sequences", legacy_and_split_sequences},
               {"motion_modes_and_dedup", motion_modes_and_dedup},
               {"sgr_mode_and_legacy_coordinates",
                sgr_mode_and_legacy_coordinates},
               {"disabled_and_history_view", disabled_and_history_view},
               {"ris_clears_tracking", ris_clears_tracking},
               {"ekko_modes", ekko_modes}};
  int failures = 0;
  for (const auto &test : tests) {
    try {
      test.run();
    } catch (const std::exception &e) {
      std::fprintf(stderr, "%s: %s\n", test.name, e.what());
      ++failures;
    }
  }
  return failures ? 1 : 0;
}
