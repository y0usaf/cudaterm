#pragma once
#include <string>

namespace ct {
inline std::string explicit_uri(const std::string &text) {
  if (text.size() > 8192 || text.find_first_of("\r\n\t ") != std::string::npos) return {};
  for (unsigned char c : text) if (c < 32 || c == 127) return {};
  for (const auto &prefix : {"https://", "http://", "file://", "mailto:"})
    if (text.rfind(prefix, 0) == 0 && text.size() > std::char_traits<char>::length(prefix)) return text;
  return {};
}
// Only launch explicit URI schemes. Never interpret terminal text as a shell
// command or as xdg-open command-line options.
inline std::string detected_uri(std::string text) {
  while (!text.empty() && (text.front() == '(' || text.front() == '[' || text.front() == '{')) text.erase(0, 1);
  while (!text.empty() && (text.back() == '.' || text.back() == ',' || text.back() == ';' || text.back() == '!')) text.pop_back();
  for (auto pair : {std::string("()"), std::string("[]"), std::string("{}")}) {
    int balance = 0;
    for (char c : text) balance += (c == pair[0]) - (c == pair[1]);
    while (balance < 0 && !text.empty() && text.back() == pair[1]) { text.pop_back(); ++balance; }
  }
  return explicit_uri(text);
}
}
