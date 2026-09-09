#pragma once
#include "face.hpp"
#include <array>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>
#include <xxhash.h>

namespace ct {
struct FontAtlas {
  int width = 0, height = 0;
  std::array<std::vector<unsigned char>, 4> faces;
};
inline void cache_field(std::string &key, const std::string &value) {
  key += std::to_string(value.size()) + ":" + value;
}
inline bool cache_file_identity(std::string &key, const std::string &path) {
  struct stat st;
  if (stat(path.c_str(), &st)) return false;
  cache_field(key, path);
  std::error_code error;
  auto resolved = std::filesystem::canonical(path, error).string();
  if (!error && resolved.rfind("/nix/store/", 0) == 0) {
    // Store paths are immutable identities, including across cache substitution
    // on another machine. Mutable files still use precise filesystem metadata.
    cache_field(key, resolved);
    return true;
  }
  for (auto value : {uint64_t(st.st_dev), uint64_t(st.st_ino), uint64_t(st.st_size),
                     uint64_t(st.st_mtim.tv_sec), uint64_t(st.st_mtim.tv_nsec),
                     uint64_t(st.st_ctim.tv_sec), uint64_t(st.st_ctim.tv_nsec)})
    cache_field(key, std::to_string(value));
  return true;
}
inline uint64_t font_cache_hash(const void *data, size_t size, uint64_t hash = 0) {
  return XXH3_64bits_withSeed(data, size, hash);
}
inline std::string font_cache_path(const std::string &key) {
  const char *root = std::getenv("XDG_CACHE_HOME");
  std::string directory;
  if (root && *root == '/') directory = root;
  else {
    root = std::getenv("HOME");
    if (!root || *root != '/') return {};
    directory = std::string(root) + "/.cache";
  }
  return directory + "/cudaterm/fonts/" + std::to_string(font_cache_hash(key.data(), key.size())) + ".bin";
}
inline std::string prepared_font_cache_path(const std::string &key) {
  const char *directory = std::getenv("CUDATERM_PREPARED_FONTS");
  if (!directory || *directory != '/') return {};
  return std::string(directory) + "/" + std::to_string(font_cache_hash(key.data(), key.size())) + ".bin";
}
// Cache files are disposable: reject partial/corrupt entries and regenerate.
// The full key is checked as well as its filename hash; writes publish atomically.
inline bool read_font_cache(const std::string &path, const std::string &key, FontAtlas &atlas) {
  if (path.empty()) return false;
  std::ifstream file(path, std::ios::binary);
  std::string stored(key.size(), '\0');
  if (!file.read(stored.data(), stored.size()) || stored != key) return false;
  FontAtlas result;
  uint64_t hash = font_cache_hash(key.data(), key.size());
  for (auto &face : result.faces) {
    uint32_t size;
    if (!file.read(reinterpret_cast<char *>(&size), sizeof size) || size < 24 || size > 21 * 1024 * 1024) return false;
    face.resize(size);
    if (!file.read(reinterpret_cast<char *>(face.data()), size)) return false;
    hash = font_cache_hash(face.data(), face.size(), hash);
    try {
      auto h = face_header(face.data(), face.size());
      size_t tables = (24 + size_t(h.count) * h.width * 2 * h.height + 3) & ~size_t(3);
      if (tables + 0x1100 * 4 + size_t(h.pages) * 256 * 4 != size) return false;
      if (result.width && (result.width != int(h.width) || result.height != int(h.height))) return false;
      result.width = h.width; result.height = h.height;
      for (size_t offset = tables; offset < size; offset += 4) {
        uint32_t entry;
        std::memcpy(&entry, face.data() + offset, 4);
        if (entry != 0xffffffffu && entry >= (offset < tables + 0x1100 * 4 ? h.pages : h.count)) return false;
      }
    } catch (const std::runtime_error &) { return false; }
  }
  uint64_t stored_hash;
  if (!file.read(reinterpret_cast<char *>(&stored_hash), sizeof stored_hash) || stored_hash != hash || file.peek() != EOF) return false;
  atlas = std::move(result);
  return true;
}
inline void write_font_cache(const std::string &path, const std::string &key, const FontAtlas &atlas) {
  if (path.empty()) return;
  std::error_code error;
  std::filesystem::create_directories(std::filesystem::path(path).parent_path(), error);
  if (error) return;
  std::string temporary = path + ".XXXXXX";
  int fd = mkstemp(temporary.data());
  if (fd < 0) return;
  FILE *file = fdopen(fd, "wb");
  if (!file) { close(fd); unlink(temporary.c_str()); return; }
  bool ok = fwrite(key.data(), 1, key.size(), file) == key.size();
  uint64_t hash = font_cache_hash(key.data(), key.size());
  for (const auto &face : atlas.faces) {
    uint32_t size = face.size();
    hash = font_cache_hash(face.data(), face.size(), hash);
    if (fwrite(&size, sizeof size, 1, file) != 1 || fwrite(face.data(), 1, size, file) != size) ok = false;
  }
  if (fwrite(&hash, sizeof hash, 1, file) != 1) ok = false;
  if (fclose(file)) ok = false;
  if (ok) rename(temporary.c_str(), path.c_str());
  unlink(temporary.c_str());
}
}
