#pragma once
#include <cstdint>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>

namespace ct {
struct FaceHeader { uint32_t width, height, count, pages; };
inline FaceHeader face_header(const unsigned char *data, size_t size) {
  FaceHeader h;
  if (size < 24 || std::memcmp(data, "CTFACE01", 8))
    throw std::runtime_error("invalid font face header");
  std::memcpy(&h, data + 8, sizeof h);
  if (!h.width || h.width > 64 || !h.height || h.height > 128 ||
      !h.count || h.count > 0x110000 || !h.pages || h.pages > 0x1100 ||
      uint64_t(h.count) * h.width * 2 * h.height > 64 * 1024 * 1024)
    throw std::runtime_error("invalid font face dimensions");
  return h;
}
inline FaceHeader face_header(const std::string &path) {
  std::ifstream file(path, std::ios::binary);
  unsigned char data[24];
  if (!file.read(reinterpret_cast<char *>(data), sizeof data))
    throw std::runtime_error("cannot read font face: " + path);
  return face_header(data, sizeof data);
}
}
