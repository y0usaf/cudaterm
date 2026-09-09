#pragma once

#include <string>
#include <stdexcept>
#include <vector>

namespace ct::input {
// File drops insert shell arguments without evaluating filenames as shell code.
inline std::string dropped_paths(int count, const char *const *paths) {
  std::string text;
  for (int i = 0; i < count; ++i) {
    if (i) text += ' ';
    text += '\'';
    for (const char *p = paths[i]; *p; ++p) {
      if (static_cast<unsigned char>(*p) < 0x20 || *p == 0x7f)
        throw std::invalid_argument("dropped filename contains a terminal control character");
      if (*p == '\'') text += "'\\''";
      else text += *p;
    }
    text += '\'';
  }
  return text;
}
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
  F12,
  Begin
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
  case Key::Begin:
    final = 'E';
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

enum class Keypad {
  Zero, One, Two, Three, Four, Five, Six, Seven, Eight, Nine,
  Decimal, Enter, Add, Subtract, Multiply, Divide, Equal
};

inline std::string keypad_sequence(Keypad key, unsigned modifiers,
                                   bool num_lock, bool application_keypad,
                                   bool application_cursor,
                                   bool decimal_separator = false) {
  const unsigned index = static_cast<unsigned>(key);
  modifiers &= Shift | Alt | Control;
  if (!num_lock && key <= Keypad::Decimal) {
    const Key navigation[] = {Key::Insert, Key::End, Key::Down, Key::PageDown,
      Key::Left, Key::Begin, Key::Right, Key::Home, Key::Up, Key::PageUp,
      Key::Delete};
    return sequence(navigation[index], modifiers, application_cursor);
  }
  if (application_keypad && key != Keypad::Equal)
    return "\033O" + (modifiers ? std::to_string(1 + modifiers) : "") +
           (key == Keypad::Decimal && decimal_separator
              ? 'l' : "pqrstuvwxynMkmjo"[index]);

  char byte = "0123456789.\r+-*/="[index];
  if (key == Keypad::Decimal && decimal_separator)
    byte = ',';
  if (modifiers & Control) {
    if (key >= Keypad::Two && key <= Keypad::Eight)
      byte = "\000\033\034\035\036\037\177"[index - 2];
    else if (key == Keypad::Divide)
      byte = '\037';
    else if (key != Keypad::Enter) {
      // Legacy modified-key form uses the keypad keysym when no C0 byte exists.
      const unsigned keysym[] = {65456,65457,65458,65459,65460,65461,65462,65463,
        65464,65465, decimal_separator ? 65452u : 65454u, 65421, 65451,65453,
        65450,65455,65469};
      return "\033[27;" + std::to_string(1 + modifiers) + ";" +
             std::to_string(keysym[index]) + "~";
    }
  }
  std::string result(1, byte);
  if (modifiers & Alt) result.insert(result.begin(), '\033');
  return result;
}

} // namespace ct::input
