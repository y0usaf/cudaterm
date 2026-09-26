#pragma once

#include "keyboard_protocol.cuh"

#include <cstdint>
#include <string>
#include <string_view>

namespace ct::keyboard {
enum class Key : uint8_t {
  Character,
  Escape,
  Enter,
  Tab,
  Backspace,
  Up,
  Down,
  Left,
  Right,
  Home,
  End,
  Begin,
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
  Functional,
  Unknown,
};

enum class Action : uint8_t { Press, Repeat, Release };

enum Modifier : uint32_t {
  Shift = 1u << 0,
  Alt = 1u << 1,
  Control = 1u << 2,
  Super = 1u << 3,
  CapsLock = 1u << 4,
  NumLock = 1u << 5,
};

struct KeyEvent {
  Key key = Key::Unknown;
  uint32_t codepoint = 0;
  uint32_t unshifted_codepoint = 0;
  uint32_t alternate_codepoint = 0;
  std::string_view text;
  uint32_t modifiers = 0;
  Action action = Action::Press;
  bool application_cursor = false;
};

inline uint32_t first_codepoint(std::string_view text) {
  if (text.empty())
    return 0;
  const auto byte = [&](size_t i) -> unsigned char {
    return static_cast<unsigned char>(text[i]);
  };
  const unsigned char lead = byte(0);
  uint32_t cp = 0;
  size_t width = 0;
  if (lead < 0x80) {
    return lead;
  } else if (lead >= 0xc2 && lead <= 0xdf) {
    cp = lead & 0x1f;
    width = 2;
  } else if (lead >= 0xe0 && lead <= 0xef) {
    cp = lead & 0x0f;
    width = 3;
  } else if (lead >= 0xf0 && lead <= 0xf4) {
    cp = lead & 0x07;
    width = 4;
  } else {
    return 0;
  }
  if (text.size() < width)
    return 0;
  for (size_t i = 1; i < width; ++i) {
    const unsigned char c = byte(i);
    if ((c & 0xc0) != 0x80)
      return 0;
    cp = (cp << 6) | (c & 0x3f);
  }
  if ((width == 2 && cp < 0x80) || (width == 3 && cp < 0x800) ||
      (width == 4 && cp < 0x10000) || cp > 0x10ffff ||
      (cp >= 0xd800 && cp <= 0xdfff))
    return 0;
  return cp;
}

namespace detail {

inline bool next_codepoint(std::string_view text, size_t &offset,
                           uint32_t &cp) {
  if (offset >= text.size())
    return false;
  const size_t start = offset;
  const unsigned char lead = static_cast<unsigned char>(text[offset++]);
  size_t width = 1;
  if (lead >= 0xc2 && lead <= 0xdf)
    width = 2;
  else if (lead >= 0xe0 && lead <= 0xef)
    width = 3;
  else if (lead >= 0xf0 && lead <= 0xf4)
    width = 4;
  else if (lead >= 0x80 || lead > 0x7f) {
    offset = start;
    return false;
  }
  if (start + width > text.size()) {
    offset = start;
    return false;
  }
  cp = lead & (width == 1 ? 0x7fu : width == 2 ? 0x1fu :
               width == 3 ? 0x0fu : 0x07u);
  for (size_t i = 1; i < width; ++i) {
    const unsigned char c = static_cast<unsigned char>(text[start + i]);
    if ((c & 0xc0) != 0x80) {
      offset = start;
      return false;
    }
    cp = (cp << 6) | (c & 0x3f);
  }
  if ((width == 2 && cp < 0x80) || (width == 3 && cp < 0x800) ||
      (width == 4 && cp < 0x10000) || cp > 0x10ffff ||
      (cp >= 0xd800 && cp <= 0xdfff)) {
    offset = start;
    return false;
  }
  offset = start + width;
  return true;
}

inline bool printable_text(std::string_view text) {
  size_t offset = 0;
  uint32_t cp = 0;
  bool any = false;
  while (offset < text.size()) {
    if (!next_codepoint(text, offset, cp))
      return false;
    if (cp < 0x20 || cp == 0x7f)
      return false;
    any = true;
  }
  return any;
}

inline bool has_printable_text(std::string_view text) {
  return printable_text(text);
}

inline void append_decimal(std::string &out, uint32_t value) {
  out += std::to_string(value);
}

inline uint32_t kitty_modifiers(uint32_t modifiers) {
  uint32_t raw = 0;
  if (modifiers & Shift)
    raw |= 1;
  if (modifiers & Alt)
    raw |= 2;
  if (modifiers & Control)
    raw |= 4;
  if (modifiers & Super)
    raw |= 8;
  if (modifiers & CapsLock)
    raw |= 64;
  if (modifiers & NumLock)
    raw |= 128;
  return raw + 1;
}

inline bool binding_modifier(uint32_t modifiers) {
  return modifiers & (Alt | Control | Super);
}

inline bool physical_modifier(uint32_t modifiers) {
  return modifiers & (Shift | Alt | Control | Super);
}

inline std::string legacy_control(Key key) {
  switch (key) {
  case Key::Enter: return "\r";
  case Key::Tab: return "\t";
  case Key::Backspace: return "\177";
  default: return {};
  }
}

inline bool control_key(Key key) {
  return key == Key::Escape || key == Key::Enter || key == Key::Tab ||
         key == Key::Backspace;
}

struct Functional {
  uint32_t code = 0;
  const char *number = nullptr;
  char final = 0;
  bool cursor = false;
};

inline Functional functional(Key key) {
  switch (key) {
  case Key::Escape: return {27, nullptr, 'u', false};
  case Key::Enter: return {13, nullptr, 'u', false};
  case Key::Tab: return {9, nullptr, 'u', false};
  case Key::Backspace: return {127, nullptr, 'u', false};
  case Key::Up: return {1, nullptr, 'A', true};
  case Key::Down: return {1, nullptr, 'B', true};
  case Key::Right: return {1, nullptr, 'C', true};
  case Key::Left: return {1, nullptr, 'D', true};
  case Key::Home: return {1, nullptr, 'H', true};
  case Key::End: return {1, nullptr, 'F', true};
  case Key::Begin: return {1, nullptr, 'E', true};
  case Key::Insert: return {0, "2", '~', false};
  case Key::Delete: return {0, "3", '~', false};
  case Key::PageUp: return {0, "5", '~', false};
  case Key::PageDown: return {0, "6", '~', false};
  case Key::F1: return {0, nullptr, 'P', false};
  case Key::F2: return {0, nullptr, 'Q', false};
  case Key::F3: return {0, "13", '~', false};
  case Key::F4: return {0, nullptr, 'S', false};
  case Key::F5: return {0, "15", '~', false};
  case Key::F6: return {0, "17", '~', false};
  case Key::F7: return {0, "18", '~', false};
  case Key::F8: return {0, "19", '~', false};
  case Key::F9: return {0, "20", '~', false};
  case Key::F10: return {0, "21", '~', false};
  case Key::F11: return {0, "23", '~', false};
  case Key::F12: return {0, "24", '~', false};
  case Key::Functional: return {0, nullptr, 'u', false};
  case Key::Character:
  case Key::Unknown:
    return {};
  }
  return {};
}

inline uint32_t text_key(const KeyEvent &event, uint32_t active_text) {
  if (event.unshifted_codepoint)
    return event.unshifted_codepoint;
  if (event.codepoint)
    return event.codepoint;
  return active_text;
}

inline void append_text_codepoints(std::string &out, std::string_view text,
                                   bool &wrote) {
  size_t offset = 0;
  uint32_t cp = 0;
  while (offset < text.size()) {
    if (!next_codepoint(text, offset, cp))
      return;
    if (cp < 0x20 || cp == 0x7f)
      continue;
    if (!wrote)
      wrote = true;
    else
      out += ':';
    append_decimal(out, cp);
  }
}

inline std::string full_sequence(uint32_t code, char final, uint32_t modifiers,
                                Action action, bool report_events,
                                uint32_t alternate, uint32_t base_alternate,
                                bool report_alternates,
                                std::string_view associated_text,
                                bool report_text) {
  std::string out = "\033[";
  append_decimal(out, code);
  if (report_alternates && alternate && alternate != code)
    append_decimal(out.insert(out.size(), ":"), alternate);
  if (report_alternates && base_alternate && base_alternate != code &&
      base_alternate != alternate) {
    out += alternate ? ":" : "::";
    append_decimal(out, base_alternate);
  }

  const uint32_t mods = kitty_modifiers(modifiers);
  bool prior = false;
  if (report_events) {
    out += ';';
    append_decimal(out, mods);
    out += ':';
    append_decimal(out, action == Action::Press ? 1 :
                        action == Action::Repeat ? 2 : 3);
    prior = true;
  } else if (mods > 1) {
    out += ';';
    append_decimal(out, mods);
    prior = true;
  }

  if (report_text && (associated_text.size() != 0)) {
    bool wrote = false;
    if (!prior)
      out += ";;";
    else
      out += ';';
    const size_t before = out.size();
    append_text_codepoints(out, associated_text, wrote);
    if (!wrote)
      out.resize(before - (prior ? 1 : 2));
  }
  out += final;
  return out;
}

inline std::string special_sequence(const Functional &key, uint32_t modifiers,
                                    Action action, bool report_events,
                                    bool application_cursor,
                                    bool disambiguate) {
  const uint32_t mods = kitty_modifiers(modifiers);
  if (report_events) {
    std::string out = "\033[";
    if (key.number)
      out += key.number;
    else
      out += '1';
    out += ';';
    append_decimal(out, mods);
    out += ':';
    append_decimal(out, action == Action::Press ? 1 :
                        action == Action::Repeat ? 2 : 3);
    out += key.final;
    return out;
  }
  if (modifiers & (Shift | Alt | Control | Super)) {
    std::string out = "\033[";
    if (key.number)
      out += key.number;
    else
      out += '1';
    out += ';';
    append_decimal(out, mods);
    out += key.final;
    return out;
  }
  if (key.number)
    return std::string("\033[") + key.number + key.final;
  if (!disambiguate && key.cursor && application_cursor)
    return std::string("\033O") + key.final;
  return std::string("\033[") + key.final;
}

}

inline std::string encode(const KeyEvent &event, uint32_t flags) {
  flags &= ALL_FLAGS;
  if (!flags)
    return {};
  const bool report_events = flags & REPORT_EVENTS;
  const bool report_all = flags & REPORT_ALL;
  const bool report_alternates = flags & REPORT_ALTERNATES;
  const bool report_text = report_all && (flags & REPORT_TEXT);

  if (event.action == Action::Release && !report_events)
    return {};
  if (event.action == Action::Release && !report_all &&
      (event.key == Key::Enter || event.key == Key::Tab ||
       event.key == Key::Backspace))
    return {};

  const uint32_t active_text = first_codepoint(event.text);
  if (event.key == Key::Character || event.key == Key::Unknown) {
    const uint32_t code = detail::text_key(event, active_text);
    const bool modified = detail::binding_modifier(event.modifiers);
    if (!code) {
      if (event.action != Action::Release && detail::has_printable_text(event.text) &&
          !modified && !report_all)
        return std::string(event.text);
      return {};
    }
    if (!report_all && !report_alternates && !modified &&
        event.action != Action::Release) {
      if (detail::has_printable_text(event.text))
        return std::string(event.text);
      if (event.key == Key::Unknown)
        return {};
    }
    uint32_t alternate = 0;
    if (report_alternates) {
      if (event.codepoint && event.codepoint != code)
        alternate = event.codepoint;
      if (active_text && active_text != code && (event.modifiers & Shift))
        alternate = active_text;
    }
    return detail::full_sequence(code, 'u', event.modifiers, event.action,
                                 report_events, alternate,
                                 event.alternate_codepoint,
                                 report_alternates, event.text, report_text);
  }

  const detail::Functional functional = detail::functional(event.key);
  if (!functional.final)
    return {};
  if (detail::control_key(event.key)) {
    if (event.key != Key::Escape && !report_all &&
        !detail::physical_modifier(event.modifiers))
      return detail::legacy_control(event.key);
    return detail::full_sequence(functional.code, 'u', event.modifiers,
                                 event.action, report_events, 0, 0, false,
                                 event.text, report_text);
  }
  if (event.key == Key::Functional) {
    if (!event.codepoint)
      return {};
    return detail::full_sequence(event.codepoint, 'u', event.modifiers,
                                 event.action, report_events, 0, 0, false,
                                 event.text, report_text);
  }
  return detail::special_sequence(functional, event.modifiers, event.action,
                                  report_events, event.application_cursor,
                                  flags & DISAMBIGUATE);
}

inline std::string encode_disambiguated(
    uint32_t codepoint, uint32_t modifiers, Key key = Key::Character,
    bool application_cursor = false, Action action = Action::Press,
    uint32_t unshifted_codepoint = 0) {
  KeyEvent event;
  event.key = key;
  event.codepoint = codepoint;
  event.unshifted_codepoint = unshifted_codepoint;
  event.modifiers = modifiers;
  event.action = action;
  event.application_cursor = application_cursor;
  return encode(event, DISAMBIGUATE);
}

}
