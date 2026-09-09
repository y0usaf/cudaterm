#include "input.hpp"
#include "config.hpp"
#include "motion.hpp"
#include "uri.hpp"
#include "clipboard.hpp"

#include <cstdio>
#include <stdexcept>
#include <string>
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>

using ct::input::Alt;
using ct::input::Control;
using ct::input::Key;
using ct::input::Shift;

int main() {
  {
    auto check = [](bool ok) { if (!ok) throw std::runtime_error("OSC 52 clipboard writes"); };
    const std::string sequence = "\033]52;c;Y29waWVkIOeVjA==\033\\";
    for (size_t split = 1; split <= sequence.size(); ++split) {
      ct::ClipboardWrites parser;
      std::string copied;
      int writes = 0;
      auto write = [&](const std::string &s) { copied = s; ++writes; };
      for (size_t i = 0; i < sequence.size(); i += split)
        parser.feed(reinterpret_cast<const unsigned char *>(sequence.data() + i),
                    std::min(split, sequence.size() - i), write);
      check(copied == "copied 界" && writes == 1);
      auto feed = [&](const std::string &s) {
        parser.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size(), write);
      };
      feed("\033]52;c;?\007\033]52;c;!!!!\007\033]52;c;YQ=A\007");
      feed("\033]52;c;YQ==\030");
      feed("\033]52;c;/w==\007\033]52;c;AA==\007");
      feed("\033P" + sequence + "\033\\");
      check(writes == 1);
      feed("\033]52;;YQ==\007");
      check(copied == "a" && writes == 2);
      feed("\033]52;c;" + std::string(1400000, 'A') + "\007");
      check(writes == 2);
      feed(sequence);
      check(copied == "copied 界" && writes == 3);
      feed("\033]52;c;\007");
      check(copied.empty() && writes == 4);
    }
  }

  {
    if (ct::detected_uri("(https://example.org/a(b)).") != "https://example.org/a(b)" ||
        ct::detected_uri("file:///tmp/test") != "file:///tmp/test")
      throw std::runtime_error("URI punctuation handling");
    for (const char *bad : {"--help", "javascript:alert(1)", "https://", "https://a\ncommand", "hello"})
      if (!ct::detected_uri(bad).empty()) throw std::runtime_error("unsafe URI accepted");
  }
  {
    ct::CursorMotion motion;
    if (motion.update(0,0,0,.08,false)) throw std::runtime_error("initial cursor animated");
    motion.update(10,0,1,.08,false);
    if (!motion.update(10,0,1.04,.08,false) || motion.x <= 0 || motion.x >= 10)
      throw std::runtime_error("cursor did not interpolate");
    float before = motion.x;
    motion.update(20,0,1.04,.08,false);
    if (motion.x != before) throw std::runtime_error("retargeted cursor jumped");
    if (motion.update(20,0,2,.08,false) || motion.x != 20)
      throw std::runtime_error("cursor did not settle");
    if (motion.update(1,1,3,0,false) || motion.x != 1 || motion.y != 1)
      throw std::runtime_error("reduced motion did not snap");
  }
  {
    char name[] = "/tmp/cudaterm-theme-XXXXXX";
    int fd = mkstemp(name);
    if (fd < 0) throw std::runtime_error("theme fixture failed");
    close(fd);
    { std::ofstream out(name); out << "# Wallust\nforeground=abcdef\nbackground = #123456\n"
        "palette=15=654321\ncursor-color=123abc\nselection-background=223344\n"; }
    auto theme = ct::read_theme(name);
    if (theme.colors[256] != 0xabcdef || theme.colors[257] != 0x123456 ||
        theme.colors[15] != 0x654321 || theme.colors[258] != 0x123abc ||
        theme.colors[261] != 0x223344 || theme.customized != 9)
      throw std::runtime_error("Wallust theme mismatch");
    for (const char *bad : {"palette=256=ffffff", "foreground=12zz00", "unknown=123456"}) {
      { std::ofstream out(name); out << bad; }
      bool rejected = false;
      try { ct::read_theme(name); } catch (const std::runtime_error &) { rejected = true; }
      if (!rejected) throw std::runtime_error("malformed theme accepted");
    }
    unlink(name);
  }
  {
    char name[] = "/tmp/cudaterm-config-XXXXXX";
    int fd = mkstemp(name); if (fd < 0) throw std::runtime_error("config fixture failed"); close(fd);
    { std::ofstream out(name); out << "font-family = DejaVu Sans Mono\nfont-size = 15.5\n"
      "line-height=1.4\npadding-x=18\ncursor-style=bar\ncursor-blink=true\ntheme=light\n"; }
    auto config = ct::read_settings(name, true);
    if (config.font_family != "DejaVu Sans Mono" || config.font_size != 15.5f ||
        config.padding_x != 18 || config.cursor_style != 6 || !config.cursor_blink ||
        ct::settings_theme(config).colors[257] != 0xf5f6fa)
      throw std::runtime_error("config fields or theme mismatch");
    for (const char *bad : {"font-size=nan", "font-size=inf", "font-size=12px", "font-size=0",
      "padding-x=2.5", "cursor-style=triangle", "cursor-blink=yes", "unknown=1", "missing equal"}) {
      { std::ofstream out(name); out << "# header\n" << bad; }
      bool rejected = false;
      try { ct::read_settings(name, true); } catch (const std::runtime_error &e) {
        rejected = std::string(e.what()).find(":2:") != std::string::npos;
      }
      if (!rejected) throw std::runtime_error("invalid config lacked line diagnostic");
    }
    unlink(name);
    bool rejected = false;
    try { ct::read_settings(name, true); } catch (...) { rejected = true; }
    if (!rejected) throw std::runtime_error("missing explicit config accepted");
    ct::read_settings(name, false);
  }
  // A slow PTY consumer can force thousands of partial writes during a paste.
  // Exercise the same queue with real nonblocking pipe backpressure, including
  // input appended while an earlier paste is only partly written.
  {
    int pipefd[2];
    if (pipe2(pipefd, O_NONBLOCK | O_CLOEXEC))
      throw std::runtime_error("pipe2 failed");
    std::string expected(1024 * 1024, '\0');
    for (size_t i = 0; i < expected.size(); ++i)
      expected[i] = static_cast<char>(i * 31);
    ct::input::PendingBytes pending;
    pending.append((const unsigned char *)expected.data(), expected.size());
    std::string received;
    bool blocked = false, appended = false;
    while (!pending.empty() || received.size() < expected.size()) {
      while (!pending.empty()) {
        ssize_t n = write(pipefd[1], pending.data(), pending.size());
        if (n > 0) pending.consume(n);
        else if (n < 0 && errno == EAGAIN) { blocked = true; break; }
        else throw std::runtime_error("pipe write failed");
      }
      if (!appended && blocked) {
        std::string tail(65537, 'x');
        pending.append((const unsigned char *)tail.data(), tail.size());
        expected += tail;
        appended = true;
      }
      char buf[4093];
      ssize_t n = read(pipefd[0], buf, sizeof buf);
      if (n > 0) received.append(buf, n);
      else throw std::runtime_error("pipe read failed");
    }
    close(pipefd[0]); close(pipefd[1]);
    if (!blocked || !appended || received != expected || pending.capacity())
      throw std::runtime_error("paste ordering or allocation cleanup failed");
  }
  struct Case {
    Key key;
    unsigned mods;
    bool app;
    const char *expected;
  } cases[] = {
      {Key::Up, 0, false, "\033[A"},
      {Key::Up, 0, true, "\033OA"},
      {Key::Up, Shift, true, "\033[1;2A"},
      {Key::Left, Alt | Control, false, "\033[1;7D"},
      {Key::Home, Shift | Alt | Control, true, "\033[1;8H"},
      {Key::Insert, Control, false, "\033[2;5~"},
      {Key::PageDown, Alt, false, "\033[6;3~"},
      {Key::F1, 0, false, "\033OP"},
      {Key::F1, 0, true, "\033OP"},
      {Key::F1, Shift, true, "\033[1;2P"},
      {Key::F5, Control, false, "\033[15;5~"},
      {Key::F12, Shift | Alt | Control, false, "\033[24;8~"},
  };
  const Case baseline[] = {
      {Key::Up, 0, false, "\033[A"},      {Key::Down, 0, false, "\033[B"},
      {Key::Right, 0, false, "\033[C"},   {Key::Left, 0, false, "\033[D"},
      {Key::Home, 0, false, "\033[H"},    {Key::End, 0, false, "\033[F"},
      {Key::Insert, 0, false, "\033[2~"}, {Key::Delete, 0, false, "\033[3~"},
      {Key::PageUp, 0, false, "\033[5~"}, {Key::PageDown, 0, false, "\033[6~"},
      {Key::F1, 0, false, "\033OP"},      {Key::F2, 0, false, "\033OQ"},
      {Key::F3, 0, false, "\033OR"},      {Key::F4, 0, false, "\033OS"},
      {Key::F5, 0, false, "\033[15~"},    {Key::F6, 0, false, "\033[17~"},
      {Key::F7, 0, false, "\033[18~"},    {Key::F8, 0, false, "\033[19~"},
      {Key::F9, 0, false, "\033[20~"},    {Key::F10, 0, false, "\033[21~"},
      {Key::F11, 0, false, "\033[23~"},   {Key::F12, 0, false, "\033[24~"}};
  auto check = [](const Case &test) {
    if (ct::input::sequence(test.key, test.mods, test.app) != test.expected) {
      std::fprintf(stderr, "key=%d modifiers=%u application=%d\n",
                   static_cast<int>(test.key), test.mods, test.app);
      throw std::runtime_error("input sequence mismatch");
    }
  };
  for (const auto &test : baseline) {
    check(test);
    Case app = test;
    app.app = true;
    std::string expected = test.expected;
    if (test.key <= Key::End)
      expected[1] = 'O';
    app.expected = expected.c_str();
    check(app);
  }
  for (const auto &test : cases)
    check(test);
  const char *modified[] = {"\033[1;2A", "\033[1;3A", "\033[1;4A", "\033[1;5A",
                            "\033[1;6A", "\033[1;7A", "\033[1;8A"};
  for (unsigned m = 1; m <= 7; ++m)
    for (bool app : {false, true})
      check({Key::Up, m, app, modified[m - 1]});

  using ct::input::Keypad;
  auto keypad = [](Keypad key, unsigned mods, bool num, bool app,
                   const std::string &expected, bool cursor = false,
                   bool separator = false) {
    if (ct::input::keypad_sequence(key, mods, num, app, cursor, separator) != expected)
      throw std::runtime_error("keypad sequence mismatch");
  };
  const Keypad digits[] = {Keypad::Zero, Keypad::One, Keypad::Two,
                           Keypad::Three, Keypad::Four, Keypad::Five,
                           Keypad::Six, Keypad::Seven, Keypad::Eight,
                           Keypad::Nine};
  const char *numeric[] = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"};
  const char *nav[] = {"\033[2~", "\033[F", "\033[B", "\033[6~", "\033[D",
                       "\033[E", "\033[C", "\033[H", "\033[A", "\033[5~"};
  const char *cursor_nav[] = {"\033[2~", "\033OF", "\033OB", "\033[6~", "\033OD",
    "\033OE", "\033OC", "\033OH", "\033OA", "\033[5~"};
  const char *app[] = {"\033Op", "\033Oq", "\033Or", "\033Os", "\033Ot",
                       "\033Ou", "\033Ov", "\033Ow", "\033Ox", "\033Oy"};
  for (int i = 0; i < 10; ++i) {
    keypad(digits[i], 0, true, false, numeric[i]);
    keypad(digits[i], 0, false, false, nav[i]);
    keypad(digits[i], 0, false, true, nav[i]);
    keypad(digits[i], 0, true, true, app[i]);
    keypad(digits[i], 0, false, false, cursor_nav[i], true);
  }
  const char *nav_mods[] = {"\033[1;2B", "\033[1;3B", "\033[1;4B",
                            "\033[1;5B", "\033[1;6B", "\033[1;7B",
                            "\033[1;8B"};
  const char *app_mods[] = {"\033O2r", "\033O3r", "\033O4r", "\033O5r",
                            "\033O6r", "\033O7r", "\033O8r"};
  for (unsigned mods = 1; mods <= 7; ++mods) {
    keypad(Keypad::Two, mods, false, false, nav_mods[mods - 1]);
    keypad(Keypad::Two, mods, false, true, nav_mods[mods - 1]);
    keypad(Keypad::Two, mods, true, true, app_mods[mods - 1]);
  }
  keypad(Keypad::Decimal, 0, false, false, "\033[3~");
  keypad(Keypad::Decimal, 0, true, false, ".");
  keypad(Keypad::Decimal, 0, true, true, "\033On");
  keypad(Keypad::Decimal, 0, true, false, ",", false, true);
  keypad(Keypad::Decimal, Alt, true, false, "\033,", false, true);
  keypad(Keypad::Decimal, Control, true, false, "\033[27;5;65452~", false, true);
  keypad(Keypad::Decimal, Control | Alt, true, false,
         "\033[27;7;65452~", false, true);
  const char *separator_app[] = {"\033O2l", "\033O3l", "\033O4l",
    "\033O5l", "\033O6l", "\033O7l", "\033O8l"};
  for (unsigned mods = 1; mods <= 7; ++mods)
    keypad(Keypad::Decimal, mods, true, true, separator_app[mods - 1], false, true);
  keypad(Keypad::Decimal, 0, true, true, "\033Ol", false, true);
  keypad(Keypad::Decimal, 0, false, false, "\033[3~", false, true);
  keypad(Keypad::Decimal, 0, false, true, "\033[3~", false, true);
  keypad(Keypad::Add, 0, true, false, "+", false, true);
  keypad(Keypad::Add, 0, true, true, "\033Ok", false, true);
  keypad(Keypad::Enter, 0, true, false, "\r");
  keypad(Keypad::Enter, 0, true, true, "\033OM");
  keypad(Keypad::Add, 0, true, true, "\033Ok");
  keypad(Keypad::Subtract, 0, true, true, "\033Om");
  keypad(Keypad::Multiply, 0, true, true, "\033Oj");
  keypad(Keypad::Divide, 0, true, true, "\033Oo");
  keypad(Keypad::Equal, 0, true, true, "=");
  keypad(Keypad::Two, Control, true, false, std::string(1, '\0'));
  keypad(Keypad::Two, Control | Alt, true, false, std::string("\033\0", 2));
  keypad(Keypad::Three, Control, true, false, "\033");
  keypad(Keypad::Four, Control, true, false, "\034");
  keypad(Keypad::Five, Control, true, false, "\035");
  keypad(Keypad::Six, Control, true, false, "\036");
  keypad(Keypad::Seven, Control, true, false, "\037");
  keypad(Keypad::Eight, Control, true, false, "\177");
  keypad(Keypad::Decimal, Control, true, false, "\033[27;5;65454~");
  keypad(Keypad::Divide, Control, true, false, "\037");
  keypad(Keypad::Enter, Control, true, false, "\r");
  keypad(Keypad::Nine, Control, true, false, "\033[27;5;65465~");
  keypad(Keypad::Equal, Control, true, false, "\033[27;5;65469~");
  keypad(Keypad::Two, Alt, true, true, "\033O3r");
  keypad(Keypad::Enter, Control | Alt, true, false, "\033\r");
  keypad(Keypad::Add, Shift | Alt | Control, false, true, "\033O8k");
  keypad(Keypad::Subtract, Alt | Control, false, true, "\033O7m");
  keypad(Keypad::Decimal, Control, false, true, "\033[3;5~");
  keypad(Keypad::Add, 0, false, false, "+");
  keypad(Keypad::Subtract, 0, false, false, "-");
  keypad(Keypad::Multiply, Alt, true, false, "\033*");
  keypad(Keypad::Divide, 0, false, false, "/");
}
