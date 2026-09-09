#pragma once
#include <cstdint>

namespace ct {
// IDs fit the unused upper Cell.flags bits. A slot retains its full ID so
// eviction can never redirect an older cell to a newer link's destination.
constexpr unsigned HYPERLINK_SHIFT = 9;
constexpr unsigned HYPERLINK_SLOTS = 512;
constexpr unsigned HYPERLINK_MAX_ID = UINT32_MAX >> HYPERLINK_SHIFT;
struct HyperlinkEntry {
  uint32_t id;
  char uri[512];
};
struct Hyperlinks {
  uint32_t next_id;
  HyperlinkEntry entries[HYPERLINK_SLOTS];
  char query[512];
};
}
