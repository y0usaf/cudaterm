#pragma once
#include <algorithm>

namespace ct {
struct CursorMotion {
  float x = 0, y = 0, from_x = 0, from_y = 0, target_x = 0, target_y = 0;
  double started = 0;
  bool initialized = false;
  bool update(float next_x, float next_y, double now, double duration, bool snap) {
    if (!initialized || snap || duration <= 0) {
      initialized = true;
      x = from_x = target_x = next_x; y = from_y = target_y = next_y;
      started = now; return false;
    }
    double t = std::clamp((now - started) / duration, 0.0, 1.0);
    float eased = float(1 - (1 - t) * (1 - t) * (1 - t));
    x = from_x + (target_x - from_x) * eased;
    y = from_y + (target_y - from_y) * eased;
    if (target_x != next_x || target_y != next_y) {
      from_x = x; from_y = y; target_x = next_x; target_y = next_y; started = now;
      return true;
    }
    return t < 1 && (from_x != target_x || from_y != target_y);
  }
};
}
