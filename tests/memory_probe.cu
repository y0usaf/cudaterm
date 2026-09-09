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
static void sample(const char *stage, const ct::Engine *engine = nullptr, size_t external_device_bytes = 0) {
  ct::MemoryUsage owned{};
  if (engine) owned = engine->memory_usage();
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
  std::cout << "{\"engine_accounted\":";
  if (engine)
    std::cout << "{\"device_bytes\":" << owned.device_bytes
              << ",\"image_bytes\":" << owned.image_bytes
              << ",\"transfer_bytes\":" << owned.transfer_bytes
              << ",\"history_capacity\":" << owned.history_capacity << "}";
  else std::cout << "null";
  std::cout << ",\"external_device_bytes\":" << external_device_bytes;
  std::cout << ",\"stage\":\"" << stage << "\",\"rss_kib\":" << total
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
      glFinish();
      sample("egl_interop_released");
    }
    {
      ct::Engine engine(318, 89);
      check(cudaDeviceSynchronize());
      sample("engine", &engine);
      bool history = false;
      for (int i = 1; i < argc; ++i) history |= std::string(argv[i]) == "--history";
      if (history) {
        std::string payload;
        for (int i = 0; i < 10000; ++i)
          payload += "history é 日本語 \x1b[31mcolor\x1b[0m\r\n";
        // The host workload buffer remains constant across all cycle snapshots.
        sample("before_history", &engine);
        for (int cycle = 0; cycle < 3; ++cycle) {
          engine.feed(reinterpret_cast<const unsigned char *>(payload.data()), payload.size());
          check(cudaDeviceSynchronize());
          auto filled = engine.memory_usage();
          if (filled.history_capacity != 4096) throw std::runtime_error("history did not reach capacity");
          sample(("history_" + std::to_string(cycle)).c_str(), &engine);
          const unsigned char reset[] = "\x1b[3J\x1b" "c";
          engine.feed(reset, sizeof(reset) - 1);
          check(cudaDeviceSynchronize());
          auto cleared = engine.memory_usage();
          if (cleared.history_capacity != 128 || cleared.image_bytes || cleared.transfer_bytes)
            throw std::runtime_error("reset retained engine allocations");
          sample(("reset_" + std::to_string(cycle)).c_str(), &engine);
        }
      }
      std::string text(65536, 'x');
      engine.feed((const unsigned char *)text.data(), text.size());
      sample("text_64k", &engine);
      uint32_t *pixels = nullptr;
      check(cudaMalloc(&pixels, 318 * 8 * 89 * 16 * 4));
      engine.render(pixels, 318 * 8, 89 * 16);
      check(cudaDeviceSynchronize());
      sample("raster", &engine, 318 * 8 * 89 * 16 * 4);
      check(cudaFree(pixels));
      sample("raster_released", &engine);
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
