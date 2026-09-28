#pragma once
#include "engine.cuh"
#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb.h>
#include <dlfcn.h>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <future>
#include <map>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <vector>

namespace ct {
inline std::vector<std::vector<uint32_t>> read_emoji_sequences(const std::string &path) {
  std::ifstream file(path);
  if (!file) throw std::runtime_error("cannot read emoji sequences: " + path);
  std::vector<std::vector<uint32_t>> sequences;
  std::string line;
  while (std::getline(file, line)) {
    line = line.substr(0, line.find('#'));
    auto semicolon = line.find(';');
    if (semicolon == std::string::npos) continue;
    std::string field = line.substr(0, semicolon);
    auto range = field.find("..");
    if (range != std::string::npos) {
      uint32_t first = std::stoul(field.substr(0, range), nullptr, 16);
      uint32_t last = std::stoul(field.substr(range + 2), nullptr, 16);
      for (uint32_t cp = first; cp <= last; ++cp) sequences.push_back({cp});
      continue;
    }
    std::istringstream codepoints(field);
    std::vector<uint32_t> sequence;
    for (std::string hex; codepoints >> hex;) sequence.push_back(std::stoul(hex, nullptr, 16));
    if (!sequence.empty()) sequences.push_back(sequence);
  }
  return sequences;
}
template <class F> F harfbuzz_symbol(const char *name) {
  static void *library = dlopen(CUDATERM_HARFBUZZ, RTLD_NOW | RTLD_LOCAL);
  if (!library) throw std::runtime_error(std::string("cannot load HarfBuzz: ") + dlerror());
  void *symbol = dlsym(library, name);
  if (!symbol) throw std::runtime_error(std::string("HarfBuzz lacks ") + name);
  return reinterpret_cast<F>(symbol);
}
struct EmojiFace {
  FT_Library library = nullptr;
  FT_Face face = nullptr;
  explicit EmojiFace(const std::string &path) {
    if (FT_Init_FreeType(&library)) throw std::runtime_error("cannot initialize FreeType");
    if (FT_New_Face(library, path.c_str(), 0, &face)) {
      FT_Done_FreeType(library);
      throw std::runtime_error("cannot open emoji font: " + path);
    }
    if (!FT_HAS_COLOR(face)) {
      FT_Done_Face(face); FT_Done_FreeType(library);
      throw std::runtime_error("emoji font has no color glyphs: " + path);
    }
  }
  ~EmojiFace() { FT_Done_Face(face); FT_Done_FreeType(library); }
  EmojiFace(const EmojiFace &) = delete;
  EmojiFace &operator=(const EmojiFace &) = delete;
};
inline void draw_emoji(const FT_Bitmap &bitmap, int width, int height, uint32_t *out) {
  float scale = std::min(float(width) / bitmap.width, float(height) / bitmap.rows);
  float left = (width - bitmap.width * scale) / 2, top = (height - bitmap.rows * scale) / 2;
  for (int y = 0; y < height; ++y)
    for (int x = 0; x < width; ++x) {
      float x0 = std::max(0.0f, (x - left) / scale), x1 = std::min(float(bitmap.width), (x + 1 - left) / scale);
      float y0 = std::max(0.0f, (y - top) / scale), y1 = std::min(float(bitmap.rows), (y + 1 - top) / scale);
      if (x0 >= x1 || y0 >= y1) continue;
      float sum[4] = {};
      for (int sy = int(y0); sy < std::ceil(y1); ++sy) {
        float wy = std::min(y1, sy + 1.0f) - std::max(y0, float(sy));
        auto row = bitmap.buffer + (bitmap.pitch >= 0 ? sy : bitmap.rows - 1 - sy) * std::abs(bitmap.pitch);
        for (int sx = int(x0); sx < std::ceil(x1); ++sx) {
          float w = wy * (std::min(x1, sx + 1.0f) - std::max(x0, float(sx)));
          for (int c = 0; c < 4; ++c) sum[c] += w * row[sx * 4 + c];
        }
      }
      uint32_t a = std::min(255L, std::lround(sum[3] * scale * scale)), pixel = a << 24;
      for (int c = 0; c < 3; ++c)
        pixel |= uint32_t(std::min(long(a), std::lround(sum[c] * scale * scale))) << (8 * c);
      out[y * width + x] = pixel;
    }
}
inline EmojiAtlas rasterize_emoji(const std::string &path, int cell_width, int cell_height) {
  EmojiFace font(path);
  auto sequences = read_emoji_sequences(CUDATERM_EMOJI_SEQUENCES);
  auto joined = read_emoji_sequences(CUDATERM_EMOJI_ZWJ_SEQUENCES);
  sequences.insert(sequences.end(), joined.begin(), joined.end());
  auto blob_create = harfbuzz_symbol<decltype(&hb_blob_create_from_file_or_fail)>("hb_blob_create_from_file_or_fail");
  auto blob_destroy = harfbuzz_symbol<decltype(&hb_blob_destroy)>("hb_blob_destroy");
  auto face_create = harfbuzz_symbol<decltype(&hb_face_create)>("hb_face_create");
  auto face_destroy = harfbuzz_symbol<decltype(&hb_face_destroy)>("hb_face_destroy");
  auto font_create = harfbuzz_symbol<decltype(&hb_font_create)>("hb_font_create");
  auto font_destroy = harfbuzz_symbol<decltype(&hb_font_destroy)>("hb_font_destroy");
  auto buffer_create = harfbuzz_symbol<decltype(&hb_buffer_create)>("hb_buffer_create");
  auto buffer_destroy = harfbuzz_symbol<decltype(&hb_buffer_destroy)>("hb_buffer_destroy");
  auto buffer_clear = harfbuzz_symbol<decltype(&hb_buffer_clear_contents)>("hb_buffer_clear_contents");
  auto buffer_add = harfbuzz_symbol<decltype(&hb_buffer_add_utf32)>("hb_buffer_add_utf32");
  auto buffer_guess = harfbuzz_symbol<decltype(&hb_buffer_guess_segment_properties)>("hb_buffer_guess_segment_properties");
  auto shape = harfbuzz_symbol<decltype(&hb_shape)>("hb_shape");
  auto glyph_infos = harfbuzz_symbol<decltype(&hb_buffer_get_glyph_infos)>("hb_buffer_get_glyph_infos");
  auto glyph_positions = harfbuzz_symbol<decltype(&hb_buffer_get_glyph_positions)>("hb_buffer_get_glyph_positions");
  hb_blob_t *blob = blob_create(path.c_str());
  if (!blob) throw std::runtime_error("cannot read emoji font: " + path);
  hb_face_t *face = face_create(blob, 0);
  hb_font_t *shaper = font_create(face);
  hb_buffer_t *buffer = buffer_create();
  EmojiAtlas atlas;
  atlas.width = 2 * cell_width; atlas.height = cell_height;
  std::map<FT_UInt, uint32_t> slots;
  for (const auto &sequence : sequences) {
    std::vector<uint32_t> key;
    for (uint32_t cp : sequence) if (cp != 0xfe0f) key.push_back(cp);
    if (key.empty() || key.size() > 16) continue;
    FT_UInt glyph = 0;
    if (key.size() == 1) glyph = FT_Get_Char_Index(font.face, key[0]);
    else {
      buffer_clear(buffer);
      buffer_add(buffer, sequence.data(), sequence.size(), 0, sequence.size());
      buffer_guess(buffer);
      shape(shaper, buffer, nullptr, 0);
      unsigned count = 0, visible = 0;
      auto infos = glyph_infos(buffer, &count);
      auto positions = glyph_positions(buffer, &count);
      for (unsigned i = 0; i < count; ++i)
        if (positions[i].x_advance) { ++visible; glyph = infos[i].codepoint; }
      if (visible != 1) glyph = 0;
    }
    if (!glyph) continue;
    uint32_t slot = slots.emplace(glyph, slots.size()).first->second;
    atlas.sequences.push_back(key.size());
    atlas.sequences.push_back(slot | (sequence.size() == 2 && sequence[1] == 0xfe0f ? 0x80000000u : 0));
    atlas.sequences.insert(atlas.sequences.end(), key.begin(), key.end());
  }
  buffer_destroy(buffer); font_destroy(shaper); face_destroy(face); blob_destroy(blob);
  if (slots.empty()) throw std::runtime_error("emoji font has no emoji glyphs: " + path);
  std::vector<FT_UInt> glyphs(slots.size());
  for (const auto &entry : slots) glyphs[entry.second] = entry.first;
  size_t stride = size_t(atlas.width) * atlas.height;
  atlas.pixels.assign(glyphs.size() * stride, 0);
  unsigned threads = std::clamp(std::thread::hardware_concurrency(), 1u, 16u);
  std::vector<std::future<void>> work;
  for (unsigned t = 0; t < threads; ++t)
    work.push_back(std::async(std::launch::async, [&, t] {
      EmojiFace local(path);
      FT_Face f = local.face;
      if (FT_HAS_FIXED_SIZES(f) && !FT_IS_SCALABLE(f)) {
        int best = 0;
        for (int i = 1; i < f->num_fixed_sizes; ++i) {
          int h = f->available_sizes[i].height, b = f->available_sizes[best].height;
          if (b < cell_height ? h > b : h >= cell_height && h < b) best = i;
        }
        if (FT_Select_Size(f, best)) throw std::runtime_error("cannot select emoji strike: " + path);
      } else if (FT_Set_Pixel_Sizes(f, 0, cell_height))
        throw std::runtime_error("cannot size emoji font: " + path);
      for (size_t i = t; i < glyphs.size(); i += threads) {
        if (FT_Load_Glyph(f, glyphs[i], FT_LOAD_COLOR)) continue;
        if (f->glyph->format != FT_GLYPH_FORMAT_BITMAP && FT_Render_Glyph(f->glyph, FT_RENDER_MODE_NORMAL)) continue;
        const auto &bitmap = f->glyph->bitmap;
        if (bitmap.pixel_mode != FT_PIXEL_MODE_BGRA || !bitmap.width || !bitmap.rows) continue;
        draw_emoji(bitmap, atlas.width, atlas.height, atlas.pixels.data() + i * stride);
      }
    }));
  for (auto &task : work) task.get();
  return atlas;
}
}
