#include "engine.cuh"
#include "runtime.hpp"
#include <cuda_runtime.h>
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <cuda_gl_interop.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

static void check(cudaError_t e) {
  if (e != cudaSuccess) throw std::runtime_error(cudaGetErrorString(e));
}
static void sample(const char *stage) {
  std::ifstream maps("/proc/self/smaps");
  std::string line, name = "anonymous";
  std::map<std::string, size_t> rss;
  size_t pss = 0, private_kb = 0;
  while (std::getline(maps, line)) {
    if (line.find('-') < line.find(' ')) {
      std::istringstream in(line);
      std::string address, permissions, offset, dev, inode;
      in >> address >> permissions >> offset >> dev >> inode;
      std::getline(in >> std::ws, name);
      if (name.empty()) name = "anonymous";
    } else {
      std::istringstream in(line);
      std::string key;
      size_t kb;
      if (in >> key >> kb) {
        if (key == "Rss:") rss[name] += kb;
        if (key == "Pss:") pss += kb;
        if (key == "Private_Clean:" || key == "Private_Dirty:") private_kb += kb;
      }
    }
  }
  size_t total = 0;
  for (auto &entry : rss) total += entry.second;
  long gpu_mib = -1;
  if (FILE *pipe = popen("nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits", "r")) {
    char row[256];
    while (fgets(row, sizeof(row), pipe)) {
      long pid, mib;
      if (sscanf(row, "%ld, %ld", &pid, &mib) == 2 && pid == getpid()) gpu_mib = mib;
    }
    if (pclose(pipe)) gpu_mib = -1;
  }
  std::cout << "{\"stage\":\"" << stage << "\",\"rss_kib\":" << total
            << ",\"pss_kib\":" << pss << ",\"private_kib\":" << private_kb
            << ",\"nvidia_compute_mib\":" << gpu_mib
            << ",\"mappings_kib\":{";
  bool first = true;
  for (auto &entry : rss) if (entry.second >= 1024) {
    if (!first) std::cout << ',';
    first = false;
    std::cout << '"' << entry.first << "\":" << entry.second;
  }
  std::cout << "}}\n";
}
int main(int argc, char **argv) {
  try {
    sample("process");
    ct::configure_runtime();
    check(cudaSetDevice(0));
    for (int i = 1; i < argc; ++i)
      if (std::string(argv[i]) == "--small-stack")
        check(cudaDeviceSetLimit(cudaLimitStackSize, 128));
    sample("cuda_context");
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    bool use_egl = false;
    for (int i = 1; i < argc; ++i) use_egl |= std::string(argv[i]) == "--egl";
    if (use_egl) {
      auto query = (PFNEGLQUERYDEVICESEXTPROC)eglGetProcAddress("eglQueryDevicesEXT");
      auto platform = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
      auto attribute = (PFNEGLQUERYDEVICEATTRIBEXTPROC)eglGetProcAddress("eglQueryDeviceAttribEXT");
      EGLDeviceEXT devices[16];
      EGLint count = 0;
      if (!query || !platform || !attribute || !query(16, devices, &count))
        throw std::runtime_error("EGL device enumeration failed");
      for (int i = 0; i < count; ++i) {
        EGLAttrib ordinal = -1;
        if (attribute(devices[i], EGL_CUDA_DEVICE_NV, &ordinal) && ordinal == 0)
          display = platform(EGL_PLATFORM_DEVICE_EXT, devices[i], nullptr);
      }
      if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr) ||
          !eglBindAPI(EGL_OPENGL_API)) throw std::runtime_error("NVIDIA EGL initialization failed");
      EGLint attributes[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE,
                             EGL_OPENGL_BIT, EGL_NONE};
      EGLConfig config;
      if (!eglChooseConfig(display, attributes, &config, 1, &count) || !count)
        throw std::runtime_error("EGL config failed");
      context = eglCreateContext(display, config, EGL_NO_CONTEXT, nullptr);
      if (context == EGL_NO_CONTEXT || !eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context))
        throw std::runtime_error("EGL context failed");
      sample("egl_context");
      GLuint buffer;
      glGenBuffers(1, &buffer);
      glBindBuffer(GL_PIXEL_UNPACK_BUFFER, buffer);
      glBufferData(GL_PIXEL_UNPACK_BUFFER, 318 * 8 * 89 * 16 * 4, nullptr, GL_STREAM_DRAW);
      cudaGraphicsResource *resource = nullptr;
      check(cudaGraphicsGLRegisterBuffer(&resource, buffer, cudaGraphicsRegisterFlagsWriteDiscard));
      check(cudaGraphicsMapResources(1, &resource));
      check(cudaGraphicsUnmapResources(1, &resource));
      sample("egl_interop");
      check(cudaGraphicsUnregisterResource(resource));
      glDeleteBuffers(1, &buffer);
    }
    {
      ct::Engine engine(318, 89);
      check(cudaDeviceSynchronize());
      sample("engine");
      std::string text(65536, 'x');
      engine.feed((const unsigned char *)text.data(), text.size());
      sample("text_64k");
      uint32_t *pixels = nullptr;
      check(cudaMalloc(&pixels, 318 * 8 * 89 * 16 * 4));
      engine.render(pixels, 318 * 8, 89 * 16);
      check(cudaDeviceSynchronize());
      sample("raster");
      check(cudaFree(pixels));
    }
    sample("engine_destroyed");
    if (display != EGL_NO_DISPLAY) {
      eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
      eglDestroyContext(display, context);
      eglTerminate(display);
    }
    check(cudaDeviceReset());
    sample("cuda_destroyed");
  } catch (const std::exception &e) {
    std::cerr << e.what() << '\n';
    return 1;
  }
}
