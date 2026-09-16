#pragma once

//! xdg-activation-v1: a BEL in an unfocused window asks the compositor to
//! raise it (foot's bell.urgent). Wayland only; other platforms ignore the
//! bell. The global binds lazily off GLFW's display on first request, and
//! token `done` events ride the default queue — glfwPollEvents dispatches
//! them.

#include <GLFW/glfw3.h>
#if defined(__linux__)
#ifndef GLFW_EXPOSE_NATIVE_WAYLAND
#define GLFW_EXPOSE_NATIVE_WAYLAND
#endif
#include <GLFW/glfw3native.h>
#include <cstring>
#include <wayland-client.h>
#include "xdg-activation-v1-client-protocol.h"
#endif

namespace ct::activation {

#if defined(__linux__)

inline xdg_activation_v1 *global = nullptr;
inline bool resolved = false;

inline void registry_global(void *, wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t) {
  if (std::strcmp(interface, xdg_activation_v1_interface.name) == 0)
    global = static_cast<xdg_activation_v1 *>(
        wl_registry_bind(registry, name, &xdg_activation_v1_interface, 1));
}
inline void registry_remove(void *, wl_registry *, uint32_t) {}
inline const wl_registry_listener registry_listener = {registry_global,
                                                     registry_remove};

inline void token_done(void *data, xdg_activation_token_v1 *token,
                       const char *id) {
  xdg_activation_v1_activate(global, id, static_cast<wl_surface *>(data));
  xdg_activation_token_v1_destroy(token);
}
inline const xdg_activation_token_v1_listener token_listener = {token_done};

#endif

// Ask the compositor to raise `window`. The token is serial-less, so the
// compositor decides between focusing it and marking it urgent.
inline void request(GLFWwindow *window) {
#if defined(__linux__)
  if (glfwGetPlatform() != GLFW_PLATFORM_WAYLAND)
    return;
  if (!resolved) {
    resolved = true;
    auto *display = glfwGetWaylandDisplay();
    auto *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, nullptr);
    wl_display_roundtrip(display);
    wl_registry_destroy(registry);
  }
  if (!global)
    return;
  auto *surface = glfwGetWaylandWindow(window);
  auto *token = xdg_activation_v1_get_activation_token(global);
  xdg_activation_token_v1_set_app_id(token, "cudaterm");
  xdg_activation_token_v1_set_surface(token, surface);
  xdg_activation_token_v1_add_listener(token, &token_listener, surface);
  xdg_activation_token_v1_commit(token);
  wl_display_flush(glfwGetWaylandDisplay());
#else
  (void)window;
#endif
}

} // namespace ct::activation
