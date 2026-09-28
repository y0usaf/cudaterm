#pragma once
#include <algorithm>
#include <array>
#include <cmath>

namespace ct {
inline constexpr double kUserInputWindow = 0.25;
struct CursorMotion {
  static constexpr float kSnapCells = 8;
  static constexpr double kRapidMove = 0.03;
  static constexpr double kGlueHold = 0.15;
  static constexpr float kSettleCells = 1.0f / 32;
  float x = 0, y = 0, target_x = 0, target_y = 0;
  double last = 0, last_move = 0, glue_until = 0;
  bool initialized = false;
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
    float rate = float(1 - std::exp(-4.0 * dt / duration));
    x += dx * rate; y += dy * rate;
    if (std::max(std::fabs(target_x - x), std::fabs(target_y - y)) <= kSettleCells) {
      x = target_x; y = target_y; return false;
    }
    return true;
  }
};
struct Spring {
  float position = 0, velocity = 0;
  bool update(float dt, float length) {
    if (position == 0) return false;
    if (length <= dt) {
      position = velocity = 0;
      return false;
    }
    float omega = 4 / length, a = position, b = position * omega + velocity, c = std::exp(-omega * dt);
    position = (a + b * dt) * c;
    velocity = c * (b - a * omega - b * dt * omega);
    if (std::fabs(position) < 0.25f && std::fabs(velocity) < 4) {
      position = velocity = 0;
      return false;
    }
    return true;
  }
};
struct CursorTrail {
  std::array<float, 8> corners{}, target{};
  std::array<Spring, 8> springs{};
  std::array<float, 4> length{};
  double last = 0, last_move = 0, glue_until = 0;
  bool initialized = false, active = false;
  bool update(const std::array<float, 8> &next, float cell_w, double now, double duration, float trail, bool snap) {
    double dt = std::clamp(now - last, 0.0, 0.05);
    last = now;
    if (!initialized || next != target) {
      if (initialized && now - last_move < CursorMotion::kRapidMove) glue_until = now + CursorMotion::kGlueHold;
      last_move = now;
      bool land = !initialized || snap || duration <= 0 || now < glue_until;
      initialized = true;
      float dx = (next[0] + next[4] - target[0] - target[4]) / 2, dy = (next[1] + next[5] - target[1] - target[5]) / 2;
      bool typing = dy == 0 && std::fabs(dx) <= 2.001f * cell_w;
      std::array<float, 4> alignment{};
      for (int i = 0; i < 4; ++i) {
        float cx = next[2 * i] - (next[0] + next[4]) / 2, cy = next[2 * i + 1] - (next[1] + next[5]) / 2;
        float tx = next[2 * i] - corners[2 * i], ty = next[2 * i + 1] - corners[2 * i + 1];
        float cn = std::hypot(cx, cy), tn = std::hypot(tx, ty);
        alignment[i] = cn > 0 && tn > 0 ? (cx * tx + cy * ty) / (cn * tn) : 0;
      }
      float leading = float(duration) * std::clamp(1 - trail, 0.0f, 1.0f);
      for (int i = 0; i < 4; ++i) {
        int rank = 0;
        for (int j = 0; j < 4; ++j)
          rank += alignment[j] < alignment[i] || (alignment[j] == alignment[i] && j < i);
        length[i] = typing ? float(duration) : rank >= 2 ? leading : rank == 1 ? (leading + float(duration)) / 2 : float(duration);
      }
      for (int i = 0; i < 8; ++i) {
        springs[i].position = land ? 0 : next[i] - corners[i];
        if (land) springs[i].velocity = 0;
      }
      target = next;
    }
    bool moving = false;
    for (int i = 0; i < 8; ++i) {
      moving |= springs[i].update(float(dt), length[i / 2]);
      corners[i] = target[i] - springs[i].position;
    }
    active = moving;
    return moving;
  }
};
struct ScrollMotion {
  Spring offset;
  float velocity = 0, carried = 0;
  double last = 0, last_touch = -1;
  void moved(int before, int after, int rows, float cell_h) {
    offset.position = std::clamp(offset.position + (before - after) * cell_h, -rows * cell_h, rows * cell_h);
  }
  void touch(double y, double now) {
    double dt = std::clamp(now - last_touch, 0.004, 0.1);
    velocity = last_touch < 0 || now - last_touch > 0.1 ? float(y / dt) : 0.7f * velocity + 0.3f * float(y / dt);
    last_touch = now;
  }
  void stop() { velocity = 0; carried = 0; last_touch = -1; }
  int coast(double now) {
    double dt = std::clamp(now - last, 0.0, 0.05);
    if (last_touch < 0 || now - last_touch < 0.06 || velocity == 0) return 0;
    carried += velocity * float(dt);
    velocity *= float(std::exp(-dt / 0.3));
    if (std::fabs(velocity) < 3) {
      velocity = 0;
      last_touch = -1;
    }
    int rows = int(carried);
    carried -= rows;
    return rows;
  }
  bool update(double now, double duration) {
    double dt = std::clamp(now - last, 0.0, 0.05);
    last = now;
    bool coasting = last_touch >= 0 && velocity != 0;
    return offset.update(float(dt), float(duration)) || coasting;
  }
};
}
