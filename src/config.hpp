#pragma once
#include "appearance.hpp"
#include <fstream>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace ct {
inline Theme read_theme(const std::string &path) {
  std::ifstream file(path);
  if (!file) throw std::runtime_error("cannot read theme: " + path);
  Theme theme = default_theme();
  std::string line;
  auto trim = [](std::string s) {
    size_t a = s.find_first_not_of(" \t\r"), b = s.find_last_not_of(" \t\r");
    return a == std::string::npos ? std::string() : s.substr(a, b - a + 1);
  };
  while (std::getline(file, line)) {
    line = trim(line);
    if (line.empty() || line[0] == '#') continue;
    size_t equal = line.find('=');
    if (equal == std::string::npos) throw std::runtime_error("invalid theme line: " + line);
    std::string key = trim(line.substr(0, equal)), value = trim(line.substr(equal + 1));
    int index = key == "foreground" ? 256 : key == "background" ? 257 :
                key == "cursor-color" ? 258 : key == "cursor-text" ? 259 :
                key == "selection-foreground" ? 260 : key == "selection-background" ? 261 : -1;
    if (key == "palette") {
      size_t split = value.find('=');
      if (split == std::string::npos) throw std::runtime_error("invalid theme palette");
      std::string number = trim(value.substr(0, split));
      if (number.empty() || number.size() > 3 || number.find_first_not_of("0123456789") != std::string::npos)
        throw std::runtime_error("invalid theme palette index");
      index = std::stoi(number);
      if (index > 255) throw std::runtime_error("invalid theme palette index");
      value = trim(value.substr(split + 1));
    }
    if (index < 0) throw std::runtime_error("unknown theme key: " + key);
    if (!value.empty() && value[0] == '#') value.erase(0, 1);
    if (value.size() != 6 || value.find_first_not_of("0123456789abcdefABCDEF") != std::string::npos)
      throw std::runtime_error("invalid theme color: " + value);
    theme.colors[index] = std::stoul(value, nullptr, 16);
    if (index >= 258) theme.customized |= 1u << (index - 258);
  }
  if (!file.eof()) throw std::runtime_error("failed reading theme: " + path);
  return theme;
}
}

namespace ct {
struct Settings {
  std::string font_family = "monospace", font_face, font_fallback, theme = "midnight";
  float font_size = 14, line_height = 1.3f, opacity = 1, scroll_multiplier = 3;
  int padding_x = 12, padding_y = 10;
  int cursor_style = 2; // DECSCUSR: steady block; applications may override.
  bool cursor_blink = false;
  float cursor_animation = 0.08f;
};
inline std::string trim_setting(const std::string &s) {
  auto a = s.find_first_not_of(" \t\r"), b = s.find_last_not_of(" \t\r");
  return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}
inline float setting_number(const std::string &value, float low, float high) {
  size_t used = 0;
  float n;
  try { n = std::stof(value, &used); } catch (...) { throw std::runtime_error("invalid number: " + value); }
  if (used != value.size() || !(n >= low && n <= high))
    throw std::runtime_error("number outside allowed range: " + value);
  return n;
}
inline void set_setting(Settings &s, const std::string &key, const std::string &value) {
  if (key == "font-family") { if (value.empty()) throw std::runtime_error("empty font family"); s.font_family = value; s.font_face.clear(); }
  else if (key == "font-file") { s.font_family = "file:" + value; s.font_face.clear(); }
  else if (key == "font-fallback") s.font_fallback = value;
  else if (key == "font-face") { s.font_face = value; s.font_family = "bitmap"; }
  else if (key == "theme") s.theme = value;
  else if (key == "font-size") s.font_size = setting_number(value, 6, 64);
  else if (key == "line-height") s.line_height = setting_number(value, 0.5f, 3);
  else if (key == "background-opacity") s.opacity = setting_number(value, 0, 1);
  else if (key == "cursor-animation") s.cursor_animation = setting_number(value, 0, 0.5f);
  else if (key == "scroll-multiplier") s.scroll_multiplier = setting_number(value, 0.1f, 20);
  else if (key == "padding-x" || key == "padding-y") {
    float n = setting_number(value, 0, 100);
    if (n != int(n)) throw std::runtime_error("padding must be an integer");
    (key == "padding-x" ? s.padding_x : s.padding_y) = int(n);
  } else if (key == "cursor-style") {
    if (value == "block") s.cursor_style = 2;
    else if (value == "underline") s.cursor_style = 4;
    else if (value == "bar") s.cursor_style = 6;
    else throw std::runtime_error("cursor-style must be block, underline or bar");
  } else if (key == "cursor-blink") {
    if (value != "true" && value != "false") throw std::runtime_error("cursor-blink must be true or false");
    s.cursor_blink = value == "true";
  } else throw std::runtime_error("unknown setting: " + key);
}
inline Settings read_settings(const std::string &path, bool required) {
  Settings settings;
  std::ifstream file(path);
  if (!file) {
    if (required || std::filesystem::exists(path)) throw std::runtime_error("cannot read config: " + path);
    return settings;
  }
  std::string line;
  int number = 0;
  while (std::getline(file, line)) {
    ++number; line = trim_setting(line);
    if (line.empty() || line[0] == '#') continue;
    try {
      auto equal = line.find('=');
      if (equal == std::string::npos) throw std::runtime_error("expected key = value");
      auto key = trim_setting(line.substr(0, equal)), value = trim_setting(line.substr(equal + 1));
      bool fallback_file = key == "font-fallback" && value.rfind("file:", 0) == 0;
      if (fallback_file || key == "font-face" || key == "font-file" || (key == "theme" && value != "midnight" && value != "light" && value != "classic")) {
        std::filesystem::path target(fallback_file ? value.substr(5) : value);
        if (target.is_relative()) target = std::filesystem::path(path).parent_path() / target;
        value = (fallback_file ? "file:" : "") + target.string();
      }
      set_setting(settings, key, value);
    } catch (const std::exception &e) {
      throw std::runtime_error(path + ":" + std::to_string(number) + ": " + e.what());
    }
  }
  if (!file.eof()) throw std::runtime_error("failed reading config: " + path);
  return settings;
}
inline Theme settings_theme(const Settings &s) {
  if (s.theme == "classic") return default_theme();
  if (s.theme != "midnight" && s.theme != "light") return read_theme(s.theme);
  Theme theme = default_theme();
  bool light = s.theme == "light";
  const uint32_t dark[] = {0x1b2030,0xf07882,0x9dcc8b,0xeac58b,0x91b9f4,0xc6a0ed,0x85cccf,0xd5dbea,
                          0x68738c,0xff929b,0xb2dfa1,0xffdaa0,0xa9ccff,0xdbb7ff,0x9fe3e5,0xf0f3fa};
  const uint32_t day[] = {0x30364a,0xb83b4d,0x357541,0x966510,0x285bb2,0x8050ac,0x16757b,0xd4d9e5,
                         0x667088,0xcb4054,0x40824a,0xa77614,0x356cc4,0x9360bd,0x25878c,0xf8f9fc};
  for (int i = 0; i < 16; ++i) theme.colors[i] = light ? day[i] : dark[i];
  theme.colors[256] = light ? 0x30364a : 0xd5dbea;
  theme.colors[257] = light ? 0xf5f6fa : 0x161b26;
  theme.colors[258] = light ? 0x285bb2 : 0x91b9f4;
  theme.colors[259] = theme.colors[257];
  theme.colors[260] = light ? 0x20283b : 0xf0f3fa;
  theme.colors[261] = light ? 0xcddcf5 : 0x344865;
  theme.customized = 15;
  return theme;
}
}
