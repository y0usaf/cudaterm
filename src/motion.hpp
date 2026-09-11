#pragma once
#include <algorithm>
#include <cmath>

namespace ct {
// A cursor move within this window of a key or pointer event is yours and
// animates; a position the program picks on its own lands immediately. Keeps
// program repaints (prompt returning, TUI redraws) from dragging the block
// across the window.
inline constexpr double kUserInputWindow = 0.25;
// Chases the visual cursor toward its cell. Positions are in cells; a cell is
// roughly 8-16 px, so any remainder below 1/32 cell is under half a pixel.
struct CursorMotion {
  // One repaint can move the cursor further than any gesture does.
  static constexpr float kSnapCells = 8;
  // Output and repaints drive the cursor far faster than a hand can. The block
  // then tracks the target exactly, the way an unanimated cursor does, and the
  // hold keeps it glued across the pauses between writes.
  static constexpr double kRapidMove = 0.03;
  static constexpr double kGlueHold = 0.15;
  static constexpr float kSettleCells = 1.0f / 32;
  float x = 0, y = 0, target_x = 0, target_y = 0;
  double last = 0, last_move = 0, glue_until = 0;
  bool initialized = false;
  // Returns true while the cursor is still moving, so the caller keeps
  // scheduling frames. `duration` is the time to settle one cell.
  bool update(float next_x, float next_y, double now, double duration, bool snap) {
    if (!initialized) {
      initialized = true;
      x = target_x = next_x; y = target_y = next_y;
      last = last_move = now; return false;
    }
    if (next_x != target_x || next_y != target_y) {
      if (now - last_move < kRapidMove) glue_until = now + kGlueHold;
      last_move = now; target_x = next_x; target_y = next_y;
    }
    double dt = std::clamp(now - last, 0.0, 0.05);
    last = now;
    float dx = target_x - x, dy = target_y - y;
    if (snap || duration <= 0 || now < glue_until ||
        std::max(std::fabs(dx), std::fabs(dy)) > kSnapCells) {
      x = target_x; y = target_y; return false;
    }
    // Exponential approach, so the speed follows the distance left rather than
    // restarting a fixed segment at every move. Frame-rate independent.
    float rate = float(1 - std::exp(-4.0 * dt / duration));
    x += dx * rate; y += dy * rate;
    if (std::max(std::fabs(target_x - x), std::fabs(target_y - y)) <= kSettleCells) {
      x = target_x; y = target_y; return false;
    }
    return true;
  }
};
}
