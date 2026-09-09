#include "input.hpp"
#include "keyboard_protocol.hpp"
#include "config.hpp"
#include "motion.hpp"
#include "uri.hpp"
#include "clipboard.hpp"
#include "reload_signal.hpp"
#include <sys/eventfd.h>

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
    int fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (fd < 0) throw std::runtime_error("reload eventfd fixture");
    struct sigaction before{}, after{};
    sigaction(SIGUSR1, nullptr, &before);
    {
      ct::ReloadSignal reload(fd);
      raise(SIGUSR1);
      uint64_t count = 0;
      if (read(fd, &count, sizeof count) != sizeof count || count != 1 ||
          !ct::ReloadSignal::pending() || !ct::ReloadSignal::take() || ct::ReloadSignal::take())
        throw std::runtime_error("SIGUSR1 must wake idle event loop and consume reload once");
    }
    sigaction(SIGUSR1, nullptr, &after);
    close(fd);
    if (before.sa_handler != after.sa_handler)
      throw std::runtime_error("reload handler must restore signal ownership");
  }
  {
    const char *paths[] = {"/tmp/plain", "/tmp/a b", "/tmp/it's", "/tmp/$(touch nope)`x`;界"};
    if (ct::input::dropped_paths(4, paths) !=
        "'/tmp/plain' '/tmp/a b' '/tmp/it'\\''s' '/tmp/$(touch nope)`x`;界'" ||
        !ct::input::dropped_paths(0, nullptr).empty())
      throw std::runtime_error("file drops must preserve literal shell arguments");
    for (const char *path : {"/tmp/\033[201~", "/tmp/\rcommand", "/tmp/\nline", "/tmp/\177"}) {
      bool rejected = false;
      try { ct::input::dropped_paths(1, &path); }
      catch (const std::invalid_argument &) { rejected = true; }
      if (!rejected) throw std::runtime_error("file drops must reject terminal controls");
    }
  }
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
    if (ct::explicit_uri("https://example.org/a).") != "https://example.org/a)." ||
        !ct::explicit_uri("javascript:alert(1)").empty())
      throw std::runtime_error("explicit hyperlinks must preserve exact safe targets");
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

  {
    using K = ct::keyboard::Key;
    using A = ct::keyboard::Action;
    auto expect = [](const std::string &got, const char *want) {
      if (got != want)
        throw std::runtime_error("Kitty keyboard encoding mismatch");
    };
    if (ct::keyboard::first_codepoint("\xC3\xA9") != 0xE9 ||
        ct::keyboard::first_codepoint("\xC0\x80") != 0 ||
        ct::keyboard::first_codepoint("\xF4\x90\x80\x80") != 0)
      throw std::runtime_error("layout UTF-8 decoding mismatch");
    expect(ct::keyboard::encode_disambiguated(27, 0, K::Escape), "\033[27u");
    expect(ct::keyboard::encode_disambiguated(13, 0, K::Enter), "\r");
    expect(ct::keyboard::encode_disambiguated(9, ct::keyboard::Shift, K::Tab), "\033[9;2u");
    expect(ct::keyboard::encode_disambiguated(127, ct::keyboard::Alt, K::Backspace), "\033[127;3u");
    expect(ct::keyboard::encode_disambiguated(1, 0, K::Up, true), "\033[A");
    expect(ct::keyboard::encode_disambiguated(0, 0, K::F1), "\033[P");
    expect(ct::keyboard::encode_disambiguated(0, 0, K::F3), "\033[13~");
    expect(ct::keyboard::encode_disambiguated(57399, 0, K::Functional), "\033[57399u");

    ct::keyboard::KeyEvent text{K::Character, 'a', 'a', 0, "a", 0, A::Press, false};
    expect(ct::keyboard::encode(text, ct::keyboard::DISAMBIGUATE), "a");
    text.modifiers = ct::keyboard::Control;
    expect(ct::keyboard::encode(text, ct::keyboard::DISAMBIGUATE), "\033[97;5u");
    text.modifiers = ct::keyboard::Shift;
    text.text = "A";
    expect(ct::keyboard::encode(text, ct::keyboard::DISAMBIGUATE), "A");
    text.modifiers = ct::keyboard::Control | ct::keyboard::Shift;
    expect(ct::keyboard::encode(text, ct::keyboard::DISAMBIGUATE), "\033[97;6u");
    text.modifiers = ct::keyboard::Alt;
    text.text = "[";
    text.codepoint = text.unshifted_codepoint = '[';
    expect(ct::keyboard::encode(text, ct::keyboard::DISAMBIGUATE), "\033[91;3u");

    ct::keyboard::KeyEvent release{K::Escape, 0, 0, 0, {}, 0, A::Release, false};
    if (!ct::keyboard::encode(release, ct::keyboard::DISAMBIGUATE).empty())
      throw std::runtime_error("unrequested Kitty release was encoded");

    ct::keyboard::Negotiation state;
    ct::keyboard::set(state, false, ct::keyboard::DISAMBIGUATE, 1);
    for (int i = 0; i < ct::keyboard::KEYBOARD_STACK_DEPTH; ++i)
      ct::keyboard::push(state, false, 0);
    ct::keyboard::pop(state, false, ct::keyboard::KEYBOARD_STACK_DEPTH);
    if (ct::keyboard::current(state, false) != ct::keyboard::DISAMBIGUATE)
      throw std::runtime_error("full Kitty keyboard pop lost base mode");
    ct::keyboard::set(state, false, ct::keyboard::REPORT_EVENTS | ct::keyboard::REPORT_ALL, 1);
    if (ct::keyboard::current(state, false) != 0)
      throw std::runtime_error("unsupported Kitty keyboard flags advertised");
    ct::keyboard::set(state, true, ct::keyboard::DISAMBIGUATE, 1);
    if (ct::keyboard::current(state, false) != 0 ||
        ct::keyboard::current(state, true) != ct::keyboard::DISAMBIGUATE)
      throw std::runtime_error("primary/alternate Kitty stacks shared state");
    ct::keyboard::reset(state);
    if (ct::keyboard::current(state, false) || ct::keyboard::current(state, true))
      throw std::runtime_error("Kitty keyboard reset left state");
  }
}
