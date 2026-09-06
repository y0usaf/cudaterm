#include "engine.cuh"
#include <cstdio>
#include <random>
#include <stdexcept>
#include <string>

static void feed(ct::Engine &e, const std::string &s) {
  e.feed((const unsigned char *)s.data(), s.size());
}
static void compare(ct::Engine &a, ct::Engine &b) {
  auto x = a.cells(), y = b.cells();
  if (x.size() != y.size())
    throw std::runtime_error("size");
  for (size_t i = 0; i < x.size(); ++i)
    if (x[i].cp != y[i].cp || x[i].fg != y[i].fg || x[i].bg != y[i].bg ||
        x[i].flags != y[i].flags || x[i].combining[0] != y[i].combining[0] ||
        x[i].combining[1] != y[i].combining[1] ||
        x[i].combining[2] != y[i].combining[2])
      throw std::runtime_error("cell " + std::to_string(i));
  auto s = a.snapshot(), t = b.snapshot();
  if (s.row != t.row || s.col != t.col)
    throw std::runtime_error("cursor");
  if (a.take_replies() != b.take_replies())
    throw std::runtime_error("replies");
}
int classifier_boundaries() {
  try {
    auto equivalent = [](const std::string &setup, const std::string &payload) {
      ct::Engine bulk(80, 24), bytes(80, 24);
      feed(bulk, setup);
      feed(bytes, setup);
      feed(bulk, payload);
      for (unsigned char c : payload)
        bytes.feed(&c, 1);
      compare(bulk, bytes);
      feed(bulk, "Z\x1b[6n");
      feed(bytes, "Z\x1b[6n");
      compare(bulk, bytes);
    };
    for (int n : {257, 513}) {
      for (int offset : {0, 31, 32, 255, 256, n - 1}) {
        std::string payload(n, 'A');
        payload[offset] = '\t';
        equivalent("", payload);
      }
    }
    // A pending parser fragment and disabled bulk modes must override every
    // byte's classification, including otherwise entirely printable input.
    for (const char *setup : {"\x1b[", "\x1b[4h", "\x1b[?7l", "\x1b[2;5r"})
      equivalent(setup, std::string(513, 'A'));
    for (int n : {4095, 4096, 4097}) {
      for (int line : {14, 15}) {
        const std::string pattern = std::string(line, 'B') + "\r\n";
        std::string payload;
        while ((int)payload.size() < n)
          payload += pattern;
        payload.resize(n);
        equivalent("\x1b[32;44m" + std::string(80, 'P'), payload);
        payload[n - 7] = '\t';
        equivalent("\x1b[3;8H", payload);
      }
    }
    return 0;
  } catch (const std::exception &e) {
    std::fprintf(stderr, "classifier boundary: %s\n", e.what());
    return 1;
  }
}
int seeded_tests() {
  int cols = 0, rows = 0, seed = 0;
  try {
    for (auto geometry : {std::pair<int, int>{1, 1}, {7, 4}, {80, 24}}) {
      cols = geometry.first;
      rows = geometry.second;
      for (seed = 0; seed < 8; ++seed) {
        ct::Engine batch(cols, rows), stream(cols, rows);
        std::string initial = "background\x1b[H\x1b[32;44m";
        if (seed & 1)
          initial += std::string(cols, 'P'); // deferred wrap at chunk boundary
        if (seed == 2)
          initial += "\x1b[2;3H";
        if (seed == 3 && rows > 3)
          initial += "\x1b[2;3r"; // fallback for partial margins
        feed(batch, initial);
        feed(stream, initial);
        std::mt19937 rng(seed);
        std::string payload;
        for (int line = 0; line < 30; ++line) {
          int len = rng() % (cols * 3 + 1);
          for (int c = 0; c < len; ++c)
            payload += (char)('A' + rng() % 26);
          payload += "\r\n";
        }
        while (payload.size() < 512)
          payload += "a\r\n";
        if (seed == 4)
          payload += "\r";
        else if (seed == 5)
          payload += "tail without newline";
        else if (seed == 6)
          payload += "\x1b[31mred\x1b[6n";
        else if (seed == 7)
          payload = std::string(1024, 'X');
        feed(batch, payload);
        for (unsigned char c : payload)
          stream.feed(&c, 1);
        compare(batch, stream);
        // Continuation reveals hidden delayed-wrap and UTF-8/parser state.
        feed(batch, "\nZ\x1b[6n");
        feed(stream, "\nZ\x1b[6n");
        compare(batch, stream);
        batch.resize(cols + 1, rows + 1);
        stream.resize(cols + 1, rows + 1);
        compare(batch, stream);
      }
    }
    return 0;
  } catch (const std::exception &e) {
    std::fprintf(stderr, "plain %dx%d seed %d: %s\n", cols, rows, seed,
                 e.what());
    return 1;
  }
}

namespace wide_cases {
using ct::Cell;
using ct::Engine;
void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}
bool same_cell(const Cell &a, const Cell &b) {
  if (a.cp != b.cp || a.fg != b.fg || a.bg != b.bg || a.flags != b.flags ||
      a.reserved != b.reserved)
    return false;
  for (int i = 0; i < 3; ++i)
    if (a.combining[i] != b.combining[i])
      return false;
  return true;
}
void check(bool ok, const char *msg) {
  if (!ok)
    throw std::runtime_error(msg);
}
void compare(const char *name, int cols, int rows, const std::string &setup,
             const std::string &payload) {
  Engine bulk(cols, rows), plain(cols, rows);
  feed(bulk, setup);
  feed(plain, setup);
  bulk.feed(reinterpret_cast<const unsigned char *>(payload.data()),
            payload.size());
  for (unsigned char c : payload)
    plain.feed(&c, 1);
  const auto a = bulk.cells(), b = plain.cells();
  check(a.size() == b.size(), name);
  for (size_t i = 0; i < a.size(); ++i)
    check(same_cell(a[i], b[i]), name);
  const auto sa = bulk.snapshot(), sb = plain.snapshot();
  check(sa.row == sb.row && sa.col == sb.col &&
            sa.cursor_visible == sb.cursor_visible &&
            sa.application_cursor == sb.application_cursor &&
            sa.bracketed_paste == sb.bracketed_paste,
        name);
}
std::string ascii(size_t n) {
  std::string s;
  s.reserve(n);
  for (size_t i = 0; i < n; ++i)
    s += static_cast<char>('a' + (i % 26));
  return s;
}
void wide_combining_initial() {
  compare("bulk after wide and combining", 20, 4,
          "\x1b[1;2H\xE4\xB8\xAD\x1b[1;4He\xCC\x81\x1b[1;1H", ascii(300));
}
void cursor_on_wide_base() {
  compare("bulk with cursor on wide base", 80, 8,
          "\x1b[1;11H\xE4\xB8\xAD\x1b[1;11H", ascii(280));
}
void cursor_on_wide_tail() {
  compare("bulk with cursor on wide tail", 80, 8,
          "\x1b[1;11H\xE4\xB8\xAD\x1b[1;12H", ascii(280));
}
void partial_overwrite_without_scroll() {
  compare("partial overwrite without scroll", 80, 8, "\x1b[4;41H中\x1b[1;1H",
          ascii(281));
}
void scroll_after_wide_content() {
  compare("bulk while scrolling", 10, 3,
          "\x1b[1;1H\xE4\xB8\xAD\x1b[2;1He\xCC\x81", ascii(320));
}
int run() {
  struct Test {
    const char *name;
    void (*run)();
  } tests[] = {
      {"wide_combining_initial", wide_combining_initial},
      {"cursor_on_wide_base", cursor_on_wide_base},
      {"cursor_on_wide_tail", cursor_on_wide_tail},
      {"partial_overwrite_without_scroll", partial_overwrite_without_scroll},
      {"scroll_after_wide_content", scroll_after_wide_content},
  };
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

} // namespace wide_cases
int main() {
  return classifier_boundaries() || seeded_tests() || wide_cases::run();
}
