#pragma once
#include "appearance.hpp"
#include <fstream>
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
