#pragma once
constexpr int IMAGE_SLOTS = 128;
constexpr int GRAPHIC_PLACEMENT_SLOTS = 256;
constexpr size_t IMAGE_LIMIT = 32u << 20, IMAGE_BUDGET = 64u << 20;
// Destination geometry is metadata only, but it still drives cursor movement
// and per-pixel sampling. Keep hostile c=/r= commands bounded before they can
// turn into large device loops or overflowing signed coordinates.
constexpr int GRAPHIC_DEST_LIMIT = 1 << 20;
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
  uint32_t id;
  int width, height, channels, screen;
};
struct GraphicPlacement {
  int occupied, image_slot;
  uint32_t placement;
  int screen, visible;
  int px, py;
  // sx/sy and width_crop/height_crop describe the currently visible part
  // of the destination rectangle.  The scroll path trims this rectangle in
  // destination pixels, so source sampling can remain correct for scaled
  // placements as well as the existing one-pixel-per-source-pixel case.
  int sx, sy, width_crop, height_crop;
  int source_x, source_y, source_width, source_height;
  int dest_width, dest_height;
};
struct GraphicsState {
  GraphicsRequest request;
  GraphicsParams command, upload;
  Image images[IMAGE_SLOTS];
  GraphicPlacement placements[GRAPHIC_PLACEMENT_SLOTS];
  int visible[GRAPHIC_PLACEMENT_SLOTS], visible_count;
  unsigned char chunk[4096];
  unsigned char *input;
  size_t input_capacity;
  size_t used;
  int chunk_size, active, invalid, phase, key, digits, header_size;
  uint32_t value, next_id;
};
