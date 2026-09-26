#pragma once
#include <cstdlib>
#include <stdexcept>
#include <unistd.h>

namespace ct {
inline void configure_runtime() {
  if (setenv("CUDA_DEVICE_MAX_CONNECTIONS", "1", 0) ||
      setenv("CUDA_SCALE_LAUNCH_QUEUES", "0.25x", 0))
    throw std::runtime_error("cannot configure CUDA queues");
  const char *vendor = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
  if (access(vendor, R_OK) == 0 &&
      setenv("__EGL_VENDOR_LIBRARY_FILENAMES", vendor, 0))
    throw std::runtime_error("cannot configure EGL vendor");
}
}
