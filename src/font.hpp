#pragma once
#include "font_cache.hpp"
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_SYNTHESIS_H
#include <fontconfig/fontconfig.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <future>
#include <vector>

namespace ct {
// Font discovery and glyph coverage preparation are host work. Terminal text,
// layout and pixel composition remain on the GPU. Rebuild at the actual pixel
// size, rather than magnifying a previously rasterized atlas.
struct ResolvedFont { std::string path; int index = 0; bool direct = false; };
inline ResolvedFont resolve_font(const std::string &family, int style) {
  if (family.empty()) return {};
  if (family.rfind("file:", 0) == 0) return {family.substr(5), 0, true};
  std::unique_ptr<FcPattern, decltype(&FcPatternDestroy)> pattern(FcPatternCreate(), FcPatternDestroy);
  if (!pattern) throw std::bad_alloc();
  FcPatternAddString(pattern.get(), FC_FAMILY, (const FcChar8 *)family.c_str());
  FcPatternAddInteger(pattern.get(), FC_WEIGHT, style & 1 ? FC_WEIGHT_BOLD : FC_WEIGHT_REGULAR);
  FcPatternAddInteger(pattern.get(), FC_SLANT, style & 2 ? FC_SLANT_ITALIC : FC_SLANT_ROMAN);
  FcConfigSubstitute(nullptr, pattern.get(), FcMatchPattern);
  FcDefaultSubstitute(pattern.get());
  FcResult result;
  std::unique_ptr<FcPattern, decltype(&FcPatternDestroy)> match(FcFontMatch(nullptr, pattern.get(), &result), FcPatternDestroy);
  FcChar8 *path = nullptr;
  int index = 0;
  if (!match || FcPatternGetString(match.get(), FC_FILE, 0, &path) != FcResultMatch)
    throw std::runtime_error("cannot resolve font family: " + family);
  FcPatternGetInteger(match.get(), FC_INDEX, 0, &index);
  return {reinterpret_cast<const char *>(path), index, false};
}
inline FontAtlas rasterize_font(const std::string &family, float pixels, float line_height, const std::string &fallback = {}) {
  std::array<ResolvedFont, 8> fonts;
  std::string key = "CTFONT-CACHE-2";
  cache_field(key, std::string(reinterpret_cast<const char *>(&pixels), sizeof pixels));
  cache_field(key, std::string(reinterpret_cast<const char *>(&line_height), sizeof line_height));
  const char *properties = std::getenv("FREETYPE_PROPERTIES");
  cache_field(key, properties ? properties : "");
#ifdef CUDATERM_FONT_CACHE_ID
  // Nix fingerprints the renderer and its dependencies, so unrelated rebuilds
  // can reuse the atlas. Native builds conservatively use executable identity.
  cache_field(key, CUDATERM_FONT_CACHE_ID);
  bool cacheable = true;
#else
  bool cacheable = cache_file_identity(key, "/proc/self/exe");
#endif
  cacheable = cache_file_identity(key, std::string(CUDATERM_DATA_DIR) + "/widths.bin") && cacheable;
  for (int style = 0; style < 4; ++style) {
    for (int i = 0; i < 2; ++i) {
      auto &font = fonts[style * 2 + i];
      font = resolve_font(i ? fallback : family, style);
      cache_field(key, std::to_string(font.index));
      cache_field(key, font.direct ? "direct" : "matched");
      if (font.path.empty()) cache_field(key, "");
      else if (!cache_file_identity(key, font.path)) cacheable = false;
    }
  }
  std::string cache = cacheable ? font_cache_path(key) : "";
  FontAtlas cached;
  if (read_font_cache(cache, key, cached)) return cached;
  if (cacheable && read_font_cache(prepared_font_cache_path(key), key, cached)) return cached;
  std::ifstream widths_file(std::string(CUDATERM_DATA_DIR) + "/widths.bin", std::ios::binary);
  std::vector<unsigned char> widths(0x110000);
  if (!widths_file.read((char *)widths.data(), widths.size()))
    throw std::runtime_error("cannot read font width data");
  FontAtlas atlas;
  auto rasterize_style = [&](int style, bool metrics_only) {
    FT_Library library = nullptr;
    if (FT_Init_FreeType(&library)) throw std::runtime_error("cannot initialize FreeType");
    struct LibraryGuard { FT_Library p; ~LibraryGuard() { FT_Done_FreeType(p); } } guard{library};
    std::vector<unsigned char> data(24);
    std::vector<uint32_t> pages(0x1100, 0xffffffffu), slots;
    uint32_t count = 0;
    for (int font_index = 0; font_index < 2; ++font_index) {
      const std::string &font_family = font_index ? fallback : family;
      if (font_family.empty()) continue;
      const auto &resolved = fonts[style * 2 + font_index];
      bool direct = resolved.direct;
      FT_Face face = nullptr;
      if (FT_New_Face(library, resolved.path.c_str(), resolved.index, &face))
        throw std::runtime_error("cannot open resolved font: " + font_family);
      struct FaceGuard { FT_Face p; ~FaceGuard() { FT_Done_Face(p); } } face_guard{face};
      if (FT_Select_Charmap(face, FT_ENCODING_UNICODE) ||
          FT_Set_Char_Size(face, 0, std::lround(pixels * 64), 72, 72))
        throw std::runtime_error("font does not support the requested Unicode pixel size");
      if (metrics_only) {
        if (FT_Load_Char(face, 'M', FT_LOAD_DEFAULT)) throw std::runtime_error("font has no M glyph");
        atlas.width = std::max(1, int((face->glyph->advance.x + 63) / 64));
        atlas.height = std::max(1, int(std::ceil(pixels * line_height - 0.001f)));
        if (atlas.width > 64 || atlas.height > 128)
          throw std::runtime_error("requested font exceeds 64 x 128 cell dimensions");
        return std::vector<unsigned char>{};
      }
      int ascent = (face->size->metrics.ascender + 63) / 64;
      int descent = (-face->size->metrics.descender + 63) / 64;
      int baseline = (atlas.height - ascent - descent) / 2 + ascent;
      size_t stride = atlas.width * 2 * atlas.height;
      FT_UInt glyph;
      for (FT_ULong cp = FT_Get_First_Char(face, &glyph); glyph; cp = FT_Get_Next_Char(face, cp, &glyph)) {
        if (cp < 32 || cp >= widths.size() || !widths[cp] || widths[cp] > 2) continue;
        if (pages[cp >> 8] != 0xffffffffu && slots[pages[cp >> 8] * 256 + (cp & 255)] != 0xffffffffu) continue;
        if (FT_Load_Glyph(face, glyph, FT_LOAD_DEFAULT)) continue;
        if (direct && (style & 1)) FT_GlyphSlot_Embolden(face->glyph);
        if (direct && (style & 2)) FT_GlyphSlot_Oblique(face->glyph);
        if (FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL)) continue;
        const auto &bitmap = face->glyph->bitmap;
        if (bitmap.pixel_mode != FT_PIXEL_MODE_GRAY && bitmap.pixel_mode != FT_PIXEL_MODE_MONO) continue;
        // Four real style faces share a bounded 64 MiB glyph budget.
        if (data.size() + stride > 16 * 1024 * 1024)
          throw std::runtime_error("font atlas exceeds 16 MiB per style; choose a smaller font size");
        size_t offset = data.size();
        data.resize(offset + stride, 0);
        int span = atlas.width * widths[cp];
        int left = face->glyph->bitmap_left;
        for (unsigned y = 0; y < bitmap.rows; ++y) {
          int dy = baseline - face->glyph->bitmap_top + int(y);
          if (dy < 0 || dy >= atlas.height) continue;
          auto row = bitmap.buffer + (bitmap.pitch >= 0 ? y : bitmap.rows - 1 - y) * std::abs(bitmap.pitch);
          bool fit = font_index && bitmap.width > unsigned(span);
          unsigned draw_width = fit ? unsigned(span) : bitmap.width;
          for (unsigned x = 0; x < draw_width; ++x) {
            int dx = fit ? int(x) : left + int(x);
            if (dx < 0 || dx >= span) continue;
            unsigned first = fit ? x * bitmap.width / draw_width : x;
            unsigned last = fit ? (x + 1) * bitmap.width / draw_width : x + 1;
            unsigned coverage = 0;
            for (unsigned source_x = first; source_x < last; ++source_x)
              coverage += bitmap.pixel_mode == FT_PIXEL_MODE_MONO
                ? (row[source_x / 8] & (0x80 >> (source_x % 8)) ? 255 : 0) : row[source_x];
            data[offset + dy * atlas.width * 2 + dx] = coverage / (last - first);
          }
        }
        // Cell rules must meet across line spacing; font ascenders alone leave
        // gaps in full-screen application borders.
        unsigned arms = cp == 0x2500 ? 3 : cp == 0x2502 ? 12 : cp == 0x250c ? 10 :
          cp == 0x2510 ? 9 : cp == 0x2514 ? 6 : cp == 0x2518 ? 5 : cp == 0x251c ? 14 :
          cp == 0x2524 ? 13 : cp == 0x252c ? 11 : cp == 0x2534 ? 7 : cp == 0x253c ? 15 : 0;
        if (arms) {
          std::fill(data.begin() + offset, data.end(), 0);
          int cx = (atlas.width - 1) / 2, cy = (atlas.height - 1) / 2;
          int thickness = std::max(1, int(pixels / 14));
          for (int y = 0; y < atlas.height; ++y) for (int x = 0; x < atlas.width; ++x) {
            bool horizontal = y >= cy && y < cy + thickness &&
              (((arms & 1) && x <= cx) || ((arms & 2) && x >= cx));
            bool vertical = x >= cx && x < cx + thickness &&
              (((arms & 4) && y <= cy) || ((arms & 8) && y >= cy));
            if (horizontal || vertical) data[offset + y * atlas.width * 2 + x] = 255;
          }
        }
        if (pages[cp >> 8] == 0xffffffffu) {
          pages[cp >> 8] = slots.size() / 256;
          slots.resize(slots.size() + 256, 0xffffffffu);
        }
        slots[pages[cp >> 8] * 256 + (cp & 255)] = count++;
      }
    }
    if (!count) throw std::runtime_error("font has no usable glyphs: " + family);
    std::memcpy(data.data(), "CTFACE01", 8);
    uint32_t header[] = {uint32_t(atlas.width), uint32_t(atlas.height), count, uint32_t(slots.size() / 256)};
    std::memcpy(data.data() + 8, header, sizeof header);
    data.resize((data.size() + 3) & ~size_t(3));
    for (const auto *table : {&pages, &slots}) {
      size_t offset = data.size(); data.resize(offset + table->size() * 4);
      std::memcpy(data.data() + offset, table->data(), table->size() * 4);
    }
    return data;
  };
  // Read regular-face metrics before workers access the shared dimensions.
  // Each worker owns its FreeType library; deferred execution handles thread limits.
  rasterize_style(0, true);
  std::array<std::future<std::vector<unsigned char>>, 4> styles;
  for (int style = 0; style < 4; ++style)
    styles[style] = std::async(std::launch::async | std::launch::deferred, rasterize_style, style, false);
  for (int style = 0; style < 4; ++style)
    atlas.faces[style] = styles[style].get();
  write_font_cache(cache, key, atlas);
  return atlas;
}
}
