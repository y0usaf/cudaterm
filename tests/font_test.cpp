#include "font.hpp"
#include <stdexcept>

static uint32_t word(const std::vector<unsigned char> &data, size_t offset) {
  uint32_t result; std::memcpy(&result, data.data() + offset, 4); return result;
}
static std::vector<unsigned char> glyph(const std::vector<unsigned char> &data, uint32_t cp) {
  auto h = ct::face_header(data.data(), data.size());
  size_t stride = h.width * 2 * h.height;
  size_t pages = (24 + h.count * stride + 3) & ~size_t(3);
  uint32_t page = word(data, pages + (cp >> 8) * 4);
  if (page == 0xffffffffu) return {};
  uint32_t slot = word(data, pages + 0x1100 * 4 + (page * 256 + (cp & 255)) * 4);
  if (slot == 0xffffffffu) return {};
  return {data.begin() + 24 + slot * stride, data.begin() + 24 + (slot + 1) * stride};
}
int main(int argc, char **argv) {
  if (argc != 3) throw std::runtime_error("expected primary and fallback font paths");
  auto primary = ct::rasterize_font(std::string("file:") + argv[1], 21, 1.142857f);
  if (primary.height != 24 || primary.width < 1 || primary.width > 64)
    throw std::runtime_error("font dimensions or serialized line height changed");
  auto regular = glyph(primary.faces[0], 'A');
  if (regular.empty() || regular == glyph(primary.faces[1], 'A') || regular == glyph(primary.faces[2], 'A'))
    throw std::runtime_error("standalone font styles are missing or identical");
  if (!glyph(primary.faces[0], 0xf07c).empty()) throw std::runtime_error("primary fixture already has Nerd icon");
  auto fallback = ct::rasterize_font(std::string("file:") + argv[1], 21, 1.142857f,
                                   std::string("file:") + argv[2]);
  for (int style = 0; style < 4; ++style) {
    auto icon = glyph(fallback.faces[style], 0xf07c);
    if (icon.empty() || std::none_of(icon.begin(), icon.end(), [](unsigned char c) { return c != 0; }))
      throw std::runtime_error("fallback icon missing or clipped away");
    if (glyph(fallback.faces[style], 'A') != glyph(primary.faces[style], 'A'))
      throw std::runtime_error("fallback replaced primary glyph");
  }
  bool rejected = false;
  try { ct::rasterize_font("file:/nonexistent/cudaterm-font.ttf", 14, 1.3f); }
  catch (const std::runtime_error &) { rejected = true; }
  if (!rejected) throw std::runtime_error("missing standalone font accepted");
}
