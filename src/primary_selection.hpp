#pragma once

#include <GLFW/glfw3.h>

#if defined(__linux__)
#ifndef GLFW_EXPOSE_NATIVE_WAYLAND
#define GLFW_EXPOSE_NATIVE_WAYLAND
#endif
#ifndef GLFW_EXPOSE_NATIVE_X11
#define GLFW_EXPOSE_NATIVE_X11
#endif
#include <GLFW/glfw3native.h>
#endif

namespace ct::primary_selection {

// GLFW's public clipboard API names only the regular clipboard. Keep the
// platform split here so callers can copy a terminal selection to the native
// primary selection without knowing which GLFW backend is active.
enum class Backend { Unsupported, X11, Wayland };

inline Backend backend() noexcept {
#if defined(__linux__)
  switch (glfwGetPlatform()) {
  case GLFW_PLATFORM_X11:
    return Backend::X11;
  case GLFW_PLATFORM_WAYLAND:
    return Backend::Wayland;
  default:
    return Backend::Unsupported;
  }
#else
  return Backend::Unsupported;
#endif
}

inline bool set(const char *text) noexcept {
#if defined(__linux__)
  switch (backend()) {
  case Backend::X11:
    glfwSetX11SelectionString(text);
    return true;
  case Backend::Wayland:
    if (!glfwWaylandPrimarySelectionSupported())
      return false;
    glfwSetWaylandPrimarySelectionString(text);
    return true;
  default:
    return false;
  }
#else
  (void)text;
  return false;
#endif
}

// The returned pointer is owned by GLFW and is valid until the next primary
// selection get/set call or library termination. Copy it before another call.
inline const char *get() noexcept {
#if defined(__linux__)
  switch (backend()) {
  case Backend::X11:
    return glfwGetX11SelectionString();
  case Backend::Wayland:
    if (!glfwWaylandPrimarySelectionSupported())
      return nullptr;
    return glfwGetWaylandPrimarySelectionString();
  default:
    return nullptr;
  }
#else
  return nullptr;
#endif
}

inline bool supported() noexcept {
#if defined(__linux__)
  switch (backend()) {
  case Backend::X11:
    return true;
  case Backend::Wayland:
    return glfwWaylandPrimarySelectionSupported() != 0;
  default:
    return false;
  }
#else
  return false;
#endif
}

} // namespace ct::primary_selection
