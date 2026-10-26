#pragma once
#include "graphics_types.cuh"

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace ct {
namespace {

constexpr size_t GRAPHIC_SOURCE_LIMIT = IMAGE_LIMIT + (1u << 16);

bool source_path_safe(const std::string &path) {
  if (path.empty() || path.size() > 4095 || path[0] != '/' ||
      path.find('\0') != std::string::npos)
    return false;
  for (const char *sensitive : {"/proc/", "/sys/", "/dev/fd/", "/dev/pts/"})
    if (path.compare(0, std::strlen(sensitive), sensitive) == 0) return false;
  return path.compare(0, 5, "/dev/") != 0 || path.compare(0, 9, "/dev/shm/") == 0;
}

bool source_temporary(const std::string &path) {
  if (path.find("tty-graphics-protocol") == std::string::npos) return false;
  if (path.compare(0, 5, "/tmp/") == 0 || path.compare(0, 9, "/dev/shm/") == 0)
    return true;
  const char *tmp = std::getenv("TMPDIR");
  if (!tmp || !*tmp) return false;
  std::string dir = tmp;
  if (dir.back() != '/') dir.push_back('/');
  return path.compare(0, dir.size(), dir) == 0;
}

bool base64_text(const std::vector<unsigned char> &in, std::string &out) {
  out.clear();
  if (in.empty() || in.size() % 4) return false;
  auto digit = [](unsigned char c) -> int {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    return c == '+' ? 62 : c == '/' ? 63 : -1;
  };
  out.reserve(in.size() / 4 * 3);
  for (size_t i = 0; i < in.size(); i += 4) {
    int a = digit(in[i]), b = digit(in[i + 1]);
    bool pad_c = in[i + 2] == '=', pad_d = in[i + 3] == '=';
    int c = pad_c ? 0 : digit(in[i + 2]), d = pad_d ? 0 : digit(in[i + 3]);
    if (a < 0 || b < 0 || c < 0 || d < 0 || (pad_c && !pad_d) ||
        ((pad_c || pad_d) && i + 4 != in.size()))
      return false;
    out.push_back(char((a << 2) | (b >> 4)));
    if (!pad_c) out.push_back(char((b << 4) | (c >> 2)));
    if (!pad_d) out.push_back(char((c << 6) | d));
  }
  return !out.empty();
}

bool read_fd(int fd, size_t size, std::vector<unsigned char> &out) {
  out.resize(size);
  size_t done = 0;
  while (done < size) {
    ssize_t n = ::read(fd, out.data() + done, size - done);
    if (n <= 0) return false;
    done += size_t(n);
  }
  return true;
}

bool graphics_read_source(unsigned medium, const std::string &name,
                          std::vector<unsigned char> &out) {
  out.clear();
  if (medium == 's') {
    int fd = ::shm_open(name.c_str(), O_RDONLY | O_CLOEXEC, 0);
    if (fd < 0) return false;
    ::shm_unlink(name.c_str());
    struct stat st {};
    bool ok = ::fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0 &&
              size_t(st.st_size) <= GRAPHIC_SOURCE_LIMIT && read_fd(fd, size_t(st.st_size), out);
    ::close(fd);
    if (!ok) out.clear();
    return ok;
  }
  if (!source_path_safe(name) || (medium == 't' && !source_temporary(name))) return false;
  int fd = ::open(name.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  if (fd < 0) return false;
  struct stat st {};
  bool ok = ::fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0 &&
            size_t(st.st_size) <= GRAPHIC_SOURCE_LIMIT && read_fd(fd, size_t(st.st_size), out);
  ::close(fd);
  if (medium == 't') ::unlink(name.c_str());
  if (!ok) out.clear();
  return ok;
}

}  // namespace
}  // namespace ct
