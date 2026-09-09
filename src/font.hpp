#pragma once
#include "face.hpp"
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_SYNTHESIS_H
#include <fontconfig/fontconfig.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <vector>

namespace ct {
// Font discovery and glyph coverage preparation are host work. Terminal text,
// layout and pixel composition remain on the GPU. Rebuild at the actual pixel
// size, rather than magnifying a previously rasterized atlas.
struct FontAtlas {
  int width = 0, height = 0;
  std::array<std::vector<unsigned char>, 4> faces;
};
inline FontAtlas rasterize_font(const std::string &family, float pixels, float line_height, const std::string &fallback = {}) {
  FT_Library library = nullptr;
  if (FT_Init_FreeType(&library)) throw std::runtime_error("cannot initialize FreeType");
  struct LibraryGuard { FT_Library p; ~LibraryGuard() { FT_Done_FreeType(p); } } guard{library};
  std::ifstream widths_file(std::string(CUDATERM_DATA_DIR) + "/widths.bin", std::ios::binary);
  std::vector<unsigned char> widths(0x110000);
  if (!widths_file.read((char *)widths.data(), widths.size()))
    throw std::runtime_error("cannot read font width data");
  FontAtlas atlas;
  for (int style = 0; style < 4; ++style) {
    std::vector<unsigned char> data(24);
    std::vector<uint32_t> pages(0x1100, 0xffffffffu), slots;
    uint32_t count = 0;
    for (int font_index = 0; font_index < 2; ++font_index) {
      const std::string &font_family = font_index ? fallback : family;
      if (font_family.empty()) continue;
      bool direct = font_family.rfind("file:", 0) == 0;
      std::string direct_path = direct ? font_family.substr(5) : "";
      std::unique_ptr<FcPattern, decltype(&FcPatternDestroy)> pattern(FcPatternCreate(), FcPatternDestroy);
      if (!pattern) throw std::bad_alloc();
      FcPatternAddString(pattern.get(), FC_FAMILY, (const FcChar8 *)font_family.c_str());
      FcPatternAddInteger(pattern.get(), FC_WEIGHT, style & 1 ? FC_WEIGHT_BOLD : FC_WEIGHT_REGULAR);
      FcPatternAddInteger(pattern.get(), FC_SLANT, style & 2 ? FC_SLANT_ITALIC : FC_SLANT_ROMAN);
      FcConfigSubstitute(nullptr, pattern.get(), FcMatchPattern);
      FcDefaultSubstitute(pattern.get());
      FcResult result;
      std::unique_ptr<FcPattern, decltype(&FcPatternDestroy)> match(direct ? nullptr : FcFontMatch(nullptr, pattern.get(), &result), FcPatternDestroy);
      FcChar8 *path = nullptr;
      int index = 0;
      if (direct) path = (FcChar8 *)direct_path.c_str();
      else {
        if (!match || FcPatternGetString(match.get(), FC_FILE, 0, &path) != FcResultMatch)
          throw std::runtime_error("cannot resolve font family: " + font_family);
        FcPatternGetInteger(match.get(), FC_INDEX, 0, &index);
      }
      FT_Face face = nullptr;
      if (FT_New_Face(library, (const char *)path, index, &face))
        throw std::runtime_error("cannot open resolved font: " + font_family);
      struct FaceGuard { FT_Face p; ~FaceGuard() { FT_Done_Face(p); } } face_guard{face};
      if (FT_Select_Charmap(face, FT_ENCODING_UNICODE) ||
          FT_Set_Char_Size(face, 0, std::lround(pixels * 64), 72, 72))
        throw std::runtime_error("font does not support the requested Unicode pixel size");
      if (!style && !font_index) {
        if (FT_Load_Char(face, 'M', FT_LOAD_DEFAULT)) throw std::runtime_error("font has no M glyph");
        atlas.width = std::max(1, int((face->glyph->advance.x + 63) / 64));
        atlas.height = std::max(1, int(std::ceil(pixels * line_height - 0.001f)));
        if (atlas.width > 64 || atlas.height > 128)
          throw std::runtime_error("requested font exceeds 64 x 128 cell dimensions");
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
    atlas.faces[style] = std::move(data);
  }
  return atlas;
}
}
