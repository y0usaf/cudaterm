#pragma once

#include <GLFW/glfw3.h>
#ifndef GLFW_EXPOSE_NATIVE_WAYLAND
#define GLFW_EXPOSE_NATIVE_WAYLAND
#endif
#include <GLFW/glfw3native.h>
#include <algorithm>
#include <wayland-client.h>

namespace ct {

struct FrameClock {
  wl_surface *surface = nullptr;
  wl_callback *callback = nullptr;
  double interval = 0, last = -1e9;

  explicit FrameClock(GLFWwindow *window) {
    if (glfwGetPlatform() == GLFW_PLATFORM_WAYLAND) {
      surface = glfwGetWaylandWindow(window);
      return;
    }
    GLFWmonitor *monitor = glfwGetPrimaryMonitor();
    const GLFWvidmode *mode = monitor ? glfwGetVideoMode(monitor) : nullptr;
    interval = 1.0 / (mode && mode->refreshRate > 0 ? mode->refreshRate : 60);
  }
  FrameClock(const FrameClock &) = delete;
  FrameClock &operator=(const FrameClock &) = delete;
  ~FrameClock() {
    if (callback)
      wl_callback_destroy(callback);
  }
  bool waiting() const { return callback != nullptr; }
  double ready_at(double max_fps) const {
    return last + std::max(interval, max_fps > 0 ? 1 / max_fps : 0.0);
  }
  void request(double now);
};

inline void frame_done(void *data, wl_callback *callback, uint32_t) {
  wl_callback_destroy(callback);
  static_cast<FrameClock *>(data)->callback = nullptr;
}
inline const wl_callback_listener frame_listener = {frame_done};

inline void FrameClock::request(double now) {
  last = now;
  if (!surface)
    return;
  callback = wl_surface_frame(surface);
  wl_callback_add_listener(callback, &frame_listener, this);
}

}
