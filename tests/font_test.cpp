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
  char temporary[] = "/tmp/cudaterm-font-test-XXXXXX";
  if (!mkdtemp(temporary)) throw std::runtime_error("cannot create cache fixture");
  struct Cleanup { const char *path; ~Cleanup() { std::filesystem::remove_all(path); } } cleanup{temporary};
  setenv("XDG_CACHE_HOME", temporary, 1);
  auto primary = ct::rasterize_font(std::string("file:") + argv[1], 21, 1.142857f);
  if (primary.height != 24 || primary.width < 1 || primary.width > 64)
    throw std::runtime_error("font dimensions or serialized line height changed");
  auto regular = glyph(primary.faces[0], 'A');
  if (regular.empty() || regular == glyph(primary.faces[1], 'A') || regular == glyph(primary.faces[2], 'A'))
    throw std::runtime_error("standalone font styles are missing or identical");
  // Every italic source row must retain its coverage, including ink outside
  // the advance width. Compare against FreeType before cell clipping.
  FT_Library library;
  FT_Face face;
  if (FT_Init_FreeType(&library) || FT_New_Face(library, argv[1], 0, &face) ||
      FT_Set_Char_Size(face, 0, 21 * 64, 72, 72))
    throw std::runtime_error("cannot open italic regression fixture");
  bool overhang = false;
  for (int style : {2, 3}) for (unsigned cp = 33; cp < 127; ++cp) {
    FT_Load_Char(face, cp, FT_LOAD_DEFAULT);
    if (style & 1) FT_GlyphSlot_Embolden(face->glyph);
    FT_GlyphSlot_Oblique(face->glyph);
    FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL);
    const auto &bitmap = face->glyph->bitmap;
    overhang |= face->glyph->bitmap_left < 0 ||
      face->glyph->bitmap_left + int(bitmap.width) > primary.width;
    int ascent = (face->size->metrics.ascender + 63) / 64;
    int descent = (-face->size->metrics.descender + 63) / 64;
    int baseline = (primary.height - ascent - descent) / 2 + ascent;
    auto rendered = glyph(primary.faces[style], cp);
    for (unsigned y = 0; y < bitmap.rows; ++y) {
      int dy = baseline - face->glyph->bitmap_top + int(y);
      if (dy < 0 || dy >= primary.height) continue;
      auto row = bitmap.buffer + y * bitmap.pitch;
      unsigned expected = 0, actual = 0;
      unsigned width = std::min(bitmap.width, unsigned(primary.width));
      for (unsigned x = 0; x < width; ++x) {
        unsigned first = x * bitmap.width / width;
        unsigned last = (x + 1) * bitmap.width / width;
        unsigned coverage = 0;
        for (unsigned sx = first; sx < last; ++sx) coverage += row[sx];
        expected += coverage / (last - first);
      }
      for (int x = 0; x < primary.width; ++x)
        actual += rendered[dy * primary.width * 2 + x];
      if (actual != expected) throw std::runtime_error("italic ink clipped at cell boundary");
    }
  }
  FT_Done_Face(face);
  FT_Done_FreeType(library);
  if (!overhang) throw std::runtime_error("italic fixture has no overhanging glyphs");
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
  auto render = [&] { return ct::rasterize_font(std::string("file:") + argv[1], 21, 1.142857f,
                                              std::string("file:") + argv[2]); };
  auto cached = render();
  if (cached.faces != fallback.faces || cached.width != fallback.width || cached.height != fallback.height)
    throw std::runtime_error("cached font differs from fresh rendering");
  auto directory = std::filesystem::path(temporary) / "cudaterm/fonts";
  if (std::distance(std::filesystem::directory_iterator(directory), std::filesystem::directory_iterator()) != 2)
    throw std::runtime_error("primary/fallback cache keys did not separate");
  auto fresh_cache = std::filesystem::path(temporary) / "fresh-user-cache";
  setenv("CUDATERM_PREPARED_FONTS", directory.c_str(), 1);
  setenv("XDG_CACHE_HOME", fresh_cache.c_str(), 1);
  if (render().faces != fallback.faces || std::filesystem::exists(fresh_cache))
    throw std::runtime_error("prepared font cache was not reused without a user cache");
  unsetenv("CUDATERM_PREPARED_FONTS");
  setenv("XDG_CACHE_HOME", temporary, 1);
  // A hit must not rewrite the cache; a malformed entry must regenerate it.
  for (const auto &entry : std::filesystem::directory_iterator(directory)) {
    auto before = std::filesystem::last_write_time(entry.path());
    render();
    if (std::filesystem::last_write_time(entry.path()) != before)
      throw std::runtime_error("cache hit rewrote the font atlas");
    std::ofstream(entry.path(), std::ios::binary | std::ios::trunc) << "broken";
  }
  if (render().faces != fallback.faces) throw std::runtime_error("corrupt cache did not recover");
  auto resized = ct::rasterize_font(std::string("file:") + argv[1], 18, 1.142857f,
                                  std::string("file:") + argv[2]);
  if (resized.height == fallback.height) throw std::runtime_error("size change reused old cache");
  std::string identity_before, identity_after;
  auto mutable_font = std::filesystem::path(temporary) / "font.ttf";
  std::filesystem::copy_file(argv[1], mutable_font);
  ct::cache_file_identity(identity_before, mutable_font);
  std::filesystem::last_write_time(mutable_font, std::filesystem::last_write_time(mutable_font) + std::chrono::seconds(1));
  ct::cache_file_identity(identity_after, mutable_font);
  if (identity_before == identity_after) throw std::runtime_error("font replacement did not change cache identity");
  // Corruption in glyph pixels must be rejected as well as malformed headers.
  auto integrity = (std::filesystem::path(temporary) / "integrity.bin").string();
  ct::write_font_cache(integrity, "integrity", fallback);
  ct::FontAtlas restored;
  if (!ct::read_font_cache(integrity, "integrity", restored) || restored.faces != fallback.faces)
    throw std::runtime_error("font cache integrity fixture failed");
  if (ct::read_font_cache(integrity, "wrong-key", restored))
    throw std::runtime_error("font cache accepted the wrong key");
  {
    std::fstream file(integrity, std::ios::in | std::ios::out | std::ios::binary);
    constexpr int pixel = 9 + 4 + 24;
    file.seekg(pixel); char value; file.get(value);
    file.seekp(pixel); file.put(value ^ 1);
  }
  if (ct::read_font_cache(integrity, "integrity", restored))
    throw std::runtime_error("font cache accepted corrupted glyph pixels");
  // Cache I/O failure must not prevent opening a terminal.
  auto blocked = std::filesystem::path(temporary) / "blocked";
  std::ofstream(blocked) << "not a directory";
  setenv("XDG_CACHE_HOME", blocked.c_str(), 1);
  if (render().faces != fallback.faces) throw std::runtime_error("unavailable cache changed rendering");
  bool rejected = false;
  try { ct::rasterize_font("file:/nonexistent/cudaterm-font.ttf", 14, 1.3f); }
  catch (const std::runtime_error &) { rejected = true; }
  if (!rejected) throw std::runtime_error("missing standalone font accepted");
}
