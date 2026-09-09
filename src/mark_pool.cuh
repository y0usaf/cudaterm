#pragma once

#include "engine.cuh"

namespace mark_pool {

struct Node { uint32_t cp, parent; };
struct Arena {
  Node *nodes;
  uint32_t *used;
  uint32_t capacity;
  uint32_t *status;
};
struct RootSpan { ct::Cell *cells; uint32_t count; };

enum : uint32_t { OK = 0, FULL = 1, MALFORMED = 2 };

__device__ inline uint32_t head(const ct::Cell &c) { return c.reserved >> 1; }
__device__ inline void set_head(ct::Cell &c, uint32_t h) {
  c.reserved = (c.reserved & 1u) | (h << 1);
}

__device__ inline uint32_t inline_count(const ct::Cell &c) {
  uint32_t n = 0;
  for (int i = 0; i < 3 && c.combining[i]; ++i) ++n;
  return n;
}
__device__ inline bool append_node(const Arena &a, uint32_t parent, uint32_t cp,
                                   uint32_t &ref) {
  uint32_t i = *a.used;
  if (i >= a.capacity) { *a.status = FULL; return false; }
  a.nodes[i] = {cp, parent};
  *a.used = i + 1;
  ref = i + 1;
  return true;
}

// The cell is written only after every required suffix node exists. A failed
// append therefore leaves the caller's input cell byte-for-byte unchanged.
__device__ inline bool append_mark(ct::Cell &c, uint32_t cp, const Arena &a) {
  for (int i = 0; i < 3; ++i)
    if (!c.combining[i]) { c.combining[i] = cp; return true; }
  ct::Cell original = c;
  uint32_t old = head(original), ref = old;
  uint32_t n = *a.used;
  if (n > a.capacity || (old && old > n)) {
    *a.status = MALFORMED; return false;
  }
  uint32_t next;
  // One leader owns this serial append. No speculative counter increment is
  // performed, so FULL leaves both the root and arena counter unchanged.
  if (n == a.capacity) { *a.status = FULL; return false; }
  if (!append_node(a, ref, cp, next)) { c = original; return false; }
  set_head(c, next);
  return true;
}

__device__ inline bool mark_at(const ct::Cell &c, const Arena &a, uint32_t ordinal,
                               uint32_t &cp) {
  if (ordinal < 3) { cp = c.combining[ordinal]; return cp != 0; }
  uint32_t ref = head(c), n = *a.used;
  if (n > a.capacity) { *a.status = MALFORMED; return false; }
  uint32_t length = 0, scan = ref;
  for (uint32_t steps = 0; scan; ++steps) {
    if (scan > n || (scan && a.nodes[scan - 1].parent >= scan) || steps > n) {
      *a.status = MALFORMED; return false;
    }
    ++length; scan = a.nodes[scan - 1].parent;
  }
  uint32_t target = ordinal - 3;
  if (target >= length) return false;
  for (uint32_t i = 0; i < length - 1 - target; ++i) {
    if (!ref || ref > n) { *a.status = MALFORMED; return false; }
    ref = a.nodes[ref - 1].parent;
  }
  if (!ref || ref > n) { *a.status = MALFORMED; return false; }
  cp = a.nodes[ref - 1].cp;
  return true;
}
// Rendering and byte-counting may visit overflow marks newest-first.
__device__ inline bool overlay_mark(const ct::Cell &c, const Arena &a,
                                    int &inline_pos, uint32_t &ref, uint32_t &cp) {
  if (inline_pos < 3 && c.combining[inline_pos]) { cp = c.combining[inline_pos++]; return true; }
  inline_pos = 3;
  if (!ref) return false;
  if (ref > *a.used || a.nodes[ref - 1].parent >= ref) { *a.status = MALFORMED; return false; }
  Node node = a.nodes[ref - 1]; cp = node.cp; ref = node.parent;
  return true;
}
__device__ inline uint32_t mark_count(const ct::Cell &c, const Arena &a) {
  uint32_t count = inline_count(c), ref = head(c), n = *a.used;
  if (n > a.capacity) { *a.status = MALFORMED; return 0; }
  for (uint32_t steps = 0; ref; ++steps) {
    if (ref > n || a.nodes[ref - 1].parent >= ref || steps > n) { *a.status = MALFORMED; return 0; }
    ++count; ref = a.nodes[ref - 1].parent;
  }
  return count;
}

} // namespace mark_pool
