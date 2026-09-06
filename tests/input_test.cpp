#include "input.hpp"
#include "config.hpp"

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
}
