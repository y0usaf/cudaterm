#pragma once
constexpr int IMAGE_SLOTS = 128;
constexpr size_t IMAGE_LIMIT = 32u << 20, IMAGE_BUDGET = 64u << 20;
struct GraphicsParams {
  uint32_t value[128];
  unsigned char seen[128];
};
struct GraphicsRequest {
  int ready, consumed, slot, committed, keep_upload, reset;
  int barrier, alternate, history_rows, history_growth;
  size_t input_bytes, output_bytes;
  uint32_t release[IMAGE_SLOTS / 32];
  int pool_wait, pool_gc;
};
struct Image {
  unsigned char *pixels;
  uint32_t id, placement;
  int width, height, channels, screen, visible;
  int px, py, sx, sy, width_crop, height_crop;
};
struct GraphicsState {
  GraphicsRequest request;
  GraphicsParams command, upload;
  Image images[IMAGE_SLOTS];
  int visible[IMAGE_SLOTS], visible_count;
  unsigned char chunk[4096];
  unsigned char *input;
  size_t input_capacity;
  size_t used;
  int chunk_size, active, invalid, phase, key, digits, header_size;
  uint32_t value, next_id;
};
