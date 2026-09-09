#pragma once

#include <GLFW/glfw3.h>
#include <cstdint>

#if defined(__linux__)
#ifndef GLFW_EXPOSE_NATIVE_WAYLAND
#define GLFW_EXPOSE_NATIVE_WAYLAND
#endif
#include <GLFW/glfw3native.h>
#endif

namespace ct::ime {

enum class Event : int {
  Enter = 1,
  Leave = 2,
  Preedit = 3,
  Commit = 4,
  DeleteSurrounding = 5,
  Done = 6,
};

#if defined(__linux__)
using Callback = GLFWwaylandTextInputCallback;
#else
using Callback = void (*)(void *, int, const char *, std::int32_t, std::int32_t,
                           std::uint32_t, std::uint32_t);
#endif

inline bool supported() noexcept {
#if defined(__linux__)
  return glfwGetPlatform() == GLFW_PLATFORM_WAYLAND &&
         glfwWaylandTextInputSupported() != 0;
#else
  return false;
#endif
}

inline void set_callback(GLFWwindow *window, Callback callback, void *user) noexcept {
#if defined(__linux__)
  if (window && glfwGetPlatform() == GLFW_PLATFORM_WAYLAND)
    glfwSetWaylandTextInputCallback(window, callback, user);
#else
  (void)window;
  (void)callback;
  (void)user;
#endif
}

inline void enable(GLFWwindow *window, int x, int y, int width, int height) noexcept {
#if defined(__linux__)
  if (window && glfwGetPlatform() == GLFW_PLATFORM_WAYLAND)
    glfwWaylandTextInputEnable(window, x, y, width, height);
#else
  (void)window;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
#endif
}

inline void disable(GLFWwindow *window) noexcept {
#if defined(__linux__)
  if (window && glfwGetPlatform() == GLFW_PLATFORM_WAYLAND)
    glfwWaylandTextInputDisable(window);
#else
  (void)window;
#endif
}

inline void set_cursor_rectangle(GLFWwindow *window, int x, int y, int width,
                                 int height) noexcept {
#if defined(__linux__)
  if (window && glfwGetPlatform() == GLFW_PLATFORM_WAYLAND)
    glfwWaylandTextInputSetCursorRectangle(window, x, y, width, height);
#else
  (void)window;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
#endif
}

} // namespace ct::ime
