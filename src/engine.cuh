#pragma once

#include <cstddef>
#include <array>
#include <cstdint>
#include <string>
#include <vector>
#include "appearance.hpp"

namespace ct {

struct Cell {
  uint32_t cp, fg, bg, flags;
  uint32_t combining[3] = {};
  // Bit 0 records an explicit space; higher bits hold the immutable mark head.
  uint32_t reserved = 0;
};

struct Snapshot {
  int cols, rows, row, col, history_rows, view_offset;
  bool cursor_visible, application_cursor, bracketed_paste, mouse_tracking;
  bool synchronized_updates;
  int cell_width, cell_height;
  bool alternate_screen;
  bool application_keypad, numlock_override;
  int cursor_style;
};
struct MemoryUsage {
  size_t device_bytes, image_bytes, transfer_bytes;
  int history_capacity;
  size_t mark_bytes, mark_nodes;
};
struct FeedResult {
  size_t consumed;
  bool frame_complete;
};

enum class SearchDirection { Backward, Forward };
struct SearchMatch {
  bool found, invalidated;
  int start_row, start_col, end_row, end_col, view_offset;
};

enum class SelectionMode { Cell, Word, Line, Rectangle, Link };

class Engine {
public:
  Engine(int cols, int rows);
  ~Engine();
  Engine(const Engine &) = delete;
  Engine &operator=(const Engine &) = delete;

  void feed(const unsigned char *bytes, size_t length);
  std::string feed_and_replies(const unsigned char *bytes, size_t length);
  // Stop at a GPU-parsed synchronized-update end, before the next frame mutates
  // state. The caller retains the unconsumed transport bytes and takes replies.
  FeedResult feed_frame(const unsigned char *bytes, size_t length);
  void resize(int cols, int rows);
  Snapshot snapshot();
  MemoryUsage memory_usage() const;
  std::vector<Cell> cells();
  std::string take_replies();
  void select(int start_row, int start_col, int end_row, int end_col,
              SelectionMode mode = SelectionMode::Cell, bool history = false);
  void clear_selection();
  SearchMatch search(const std::string &, SearchDirection, bool restart = false);
  void clear_search();
  void set_search_prompt(const std::string &);
  std::string selected_text();
  void render(uint32_t *device_pixels, int width, int height);
  void scroll_view(int delta);
  void follow_output();
  // Buttons: 0/1/2 left/middle/right, 3 none, 64/65/66/67 wheel up/down/left/right.
  // Zero-based cells; modifiers 4/8/16 Shift/Alt/Control; actions 0/1/2
  // press/release/motion. Returns whether application tracking owns the event.
  // Encoded reports are retrieved with take_replies().
  bool mouse(int button, int row, int col, int modifiers, int action,
             int pixel_x = -1, int pixel_y = -1);
  void focus(bool focused);
  bool synchronized_updates() const;
  void set_theme(const Theme &theme);
  void set_cell_size(int width, int height);
  void load_face(const std::string &path);
  void load_faces(const std::array<std::vector<unsigned char>, 4> &faces);
  void set_presentation(int padding_x, int padding_y, int cursor_style);
  void set_cursor_phase(bool visible, bool focused);
  void set_cursor_position(float col, float row);
  void set_background_opacity(float opacity);
  bool take_title(std::string &title);
  // Pump host input while image decompression runs independently. The callback
  // may use input/selection methods, but must not feed more PTY output. `busy`
  // is false once decoding is complete, allowing deferred resize/allocation.
  void set_decode_pump(void (*pump)(void *, bool), void *context);

private:
  FeedResult enqueue_feed(const unsigned char *bytes, size_t length, bool stop_at_frame = false);
  struct Impl;
  Impl *p;
};

} // namespace ct
