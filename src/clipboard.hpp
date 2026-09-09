#pragma once
#include <string>
#include <cstddef>

namespace ct {
// Desktop clipboard writes are host effects. Observe the consumed PTY stream,
// preserving string boundaries so graphics/DCS payloads cannot become requests.
// Reads (OSC 52 ... ?) are deliberately unsupported.
class ClipboardWrites {
  enum State { Ground, Escape, Osc, OscEscape, Other, OtherEscape } state = Ground;
  std::string payload;
  bool overflow = false;
  static constexpr size_t limit = 4 * ((1024 * 1024 + 2) / 3) + 16;
  static int digit(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    return c == '+' ? 62 : c == '/' ? 63 : -1;
  }
  static bool utf8(const std::string &text) {
    for (size_t i = 0; i < text.size();) {
      unsigned c = static_cast<unsigned char>(text[i++]);
      if (!c) return false;
      if (c < 128) continue;
      int n = c >= 0xc2 && c <= 0xdf ? 1 : c >= 0xe0 && c <= 0xef ? 2 :
              c >= 0xf0 && c <= 0xf4 ? 3 : -1;
      if (n < 0 || text.size() - i < size_t(n)) return false;
      unsigned cp = c & ((1u << (6 - n)) - 1);
      for (int j = 0; j < n; ++j) {
        unsigned next = static_cast<unsigned char>(text[i++]);
        if ((next & 0xc0) != 0x80) return false;
        cp = (cp << 6) | (next & 63);
      }
      if (cp < (n == 1 ? 0x80u : n == 2 ? 0x800u : 0x10000u) ||
          cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) return false;
    }
    return true;
  }
  template<class Write> void finish(Write &write) {
    if (overflow || payload.compare(0, 3, "52;") != 0) return;
    auto start = payload.find(';', 3);
    if (start == std::string::npos) return;
    auto target = payload.substr(3, start - 3);
    if (!target.empty() && target != "c") return;
    ++start;
    size_t count = payload.size() - start;
    if (count % 4) return;
    std::string text;
    for (size_t i = start; i < payload.size(); i += 4) {
      int a = digit(payload[i]), b = digit(payload[i + 1]);
      bool pad2 = payload[i + 2] == '=', pad3 = payload[i + 3] == '=';
      int c = pad2 ? 0 : digit(payload[i + 2]);
      int d = pad3 ? 0 : digit(payload[i + 3]);
      if (a < 0 || b < 0 || c < 0 || d < 0 || (pad2 && !pad3) ||
          ((pad2 || pad3) && i + 4 != payload.size()) ||
          (pad2 && (b & 15)) || (pad3 && !pad2 && (c & 3))) return;
      text += char((a << 2) | (b >> 4));
      if (!pad2) text += char((b << 4) | (c >> 2));
      if (!pad3) text += char((c << 6) | d);
    }
    if (text.size() <= 1024 * 1024 && utf8(text)) write(text);
  }
public:
  template<class Write> void feed(const unsigned char *bytes, size_t length, Write write) {
    for (size_t i = 0; i < length; ++i) {
      unsigned char c = bytes[i];
      if (c == 0x18 || c == 0x1a) { state = Ground; payload.clear(); continue; }
      switch (state) {
      case Ground: if (c == 27) state = Escape; break;
      case Escape:
        if (c == ']') { state = Osc; payload.clear(); overflow = false; }
        else if (c == 'P' || c == '_' || c == '^' || c == 'X') state = Other;
        else if (c != 27) state = Ground;
        break;
      case Osc:
        if (c == 7) { finish(write); state = Ground; payload.clear(); }
        else if (c == 27) state = OscEscape;
        else if (payload.size() < limit) payload += char(c);
        else overflow = true;
        break;
      case OscEscape:
        if (c == '\\') { finish(write); state = Ground; payload.clear(); }
        else { overflow = true; state = c == 27 ? OscEscape : Osc; }
        break;
      case Other: if (c == 27) state = OtherEscape; break;
      case OtherEscape: state = c == '\\' ? Ground : c == 27 ? OtherEscape : Other; break;
      }
    }
  }
};
} // namespace ct
