#pragma once

#include <string>
#include <vector>

namespace ct::input {
// PTY writes may consume only a prefix. Keep that prefix as an offset rather
// than moving a large paste after every write, and release it when drained.
class PendingBytes {
  std::vector<unsigned char> bytes;
  size_t offset = 0;
public:
  bool empty() const { return offset == bytes.size(); }
  size_t size() const { return bytes.size() - offset; }
  size_t capacity() const { return bytes.capacity(); }
  const unsigned char *data() const { return bytes.data() + offset; }
  void append(const unsigned char *p, size_t n) {
    if (offset && n > bytes.capacity() - bytes.size()) {
      bytes.erase(bytes.begin(), bytes.begin() + offset);
      offset = 0;
    }
    bytes.insert(bytes.end(), p, p + n);
  }
  void consume(size_t n) {
    offset += n;
    if (empty()) {
      std::vector<unsigned char>().swap(bytes);
      offset = 0;
    }
  }
};

enum class Key {
  Up,
  Down,
  Right,
  Left,
  Home,
  End,
  Insert,
  Delete,
  PageUp,
  PageDown,
  F1,
  F2,
  F3,
  F4,
  F5,
  F6,
  F7,
  F8,
  F9,
  F10,
  F11,
  F12
};
enum Modifier { Shift = 1, Alt = 2, Control = 4 };

inline std::string sequence(Key key, unsigned modifiers,
                            bool application_cursor) {
  char final = 0;
  const char *number = nullptr;
  bool cursor_key = false;
  switch (key) {
  case Key::Up:
    final = 'A';
    cursor_key = true;
    break;
  case Key::Down:
    final = 'B';
    cursor_key = true;
    break;
  case Key::Right:
    final = 'C';
    cursor_key = true;
    break;
  case Key::Left:
    final = 'D';
    cursor_key = true;
    break;
  case Key::Home:
    final = 'H';
    cursor_key = true;
    break;
  case Key::End:
    final = 'F';
    cursor_key = true;
    break;
  case Key::Insert:
    number = "2";
    break;
  case Key::Delete:
    number = "3";
    break;
  case Key::PageUp:
    number = "5";
    break;
  case Key::PageDown:
    number = "6";
    break;
  case Key::F1:
    final = 'P';
    break;
  case Key::F2:
    final = 'Q';
    break;
  case Key::F3:
    final = 'R';
    break;
  case Key::F4:
    final = 'S';
    break;
  case Key::F5:
    number = "15";
    break;
  case Key::F6:
    number = "17";
    break;
  case Key::F7:
    number = "18";
    break;
  case Key::F8:
    number = "19";
    break;
  case Key::F9:
    number = "20";
    break;
  case Key::F10:
    number = "21";
    break;
  case Key::F11:
    number = "23";
    break;
  case Key::F12:
    number = "24";
    break;
  }
  if (!modifiers) {
    if (number)
      return "\033[" + std::string(number) + "~";
    return (cursor_key && !application_cursor)
               ? "\033[" + std::string(1, final)
               : "\033O" + std::string(1, final);
  }
  const unsigned parameter = 1 + ((modifiers & Shift) ? 1 : 0) +
                             ((modifiers & Alt) ? 2 : 0) +
                             ((modifiers & Control) ? 4 : 0);
  return "\033[" + (number ? std::string(number) : "1") + ";" +
         std::to_string(parameter) + (number ? "~" : std::string(1, final));
}
} // namespace ct::input
