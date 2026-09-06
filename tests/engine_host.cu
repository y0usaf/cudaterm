#include "engine.cuh"
#include <cuda_runtime.h>
#include <cstdio>
#include <stdexcept>
#include <vector>
#include <string>
#include <cstring>
#include <chrono>
#include <thread>

static void read_bytes(void *out, size_t n) {
  if (std::fread(out, 1, n, stdin) != n) throw std::runtime_error("truncated harness request");
}
static void respond(const void *data, uint32_t size) {
  if (std::fwrite(&size, 4, 1, stdout) != 1 ||
      (size && std::fwrite(data, 1, size, stdout) != size) || std::fflush(stdout))
    throw std::runtime_error("harness response failed");
}
static void check(cudaError_t e) {
  if (e != cudaSuccess) throw std::runtime_error(cudaGetErrorString(e));
}
// A test transport, not a terminal parser: F feeds opaque PTY bytes, R returns
// CUDA-rasterized pixels, S exposes state, W resizes, M injects pointer events.
int main() {
  try {
    ct::Engine engine(80, 24);
    struct Probe {
      ct::Engine *engine;
      int calls = 0, ended = 0;
      double maximum_ms = 0;
      std::string reports;
    } probe{&engine};
    for (int action; (action = std::getchar()) != EOF;) {
      uint32_t n; read_bytes(&n, 4);
      if (n > (1u << 20)) throw std::runtime_error("oversized harness request");
      std::vector<unsigned char> bytes(n); read_bytes(bytes.data(), n);
      if (action == 'H' && !n) {
        engine.set_decode_pump([](void *context, bool busy) {
          auto &p = *static_cast<Probe *>(context);
          if (!busy) { ++p.ended; return; }
          auto start = std::chrono::steady_clock::now();
          p.engine->snapshot();
          p.engine->mouse(0, 1, 1, 0, 0);
          p.reports += p.engine->take_replies();
          p.maximum_ms = std::max(p.maximum_ms, std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - start).count());
          ++p.calls;
          std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }, &probe);
        respond(nullptr, 0);
      } else if (action == 'D' && n == 8) {
        int dimensions[2]; std::memcpy(dimensions, bytes.data(), 8);
        engine.set_cell_size(dimensions[0], dimensions[1]);
        respond(nullptr, 0);
      } else if (action == 'P' && !n) {
        std::string report = "{\"calls\":" + std::to_string(probe.calls) +
          ",\"ended\":" + std::to_string(probe.ended) + ",\"maximum_ms\":" +
          std::to_string(probe.maximum_ms) + ",\"mouse_bytes\":" + std::to_string(probe.reports.size()) + "}";
        respond(report.data(), report.size());
      } else if (action == 'F') {
        auto reply = engine.feed_and_replies(bytes.data(), bytes.size());
        respond(reply.data(), reply.size());
      } else if (action == 'R') {
        auto s = engine.snapshot();
        size_t size = size_t(s.cols) * s.cell_width * s.rows * s.cell_height * 4;
        uint32_t *pixels; check(cudaMalloc(&pixels, size));
        engine.render(pixels, s.cols * s.cell_width, s.rows * s.cell_height);
        std::vector<unsigned char> out(size);
        check(cudaMemcpy(out.data(), pixels, size, cudaMemcpyDeviceToHost));
        check(cudaFree(pixels)); respond(out.data(), out.size());
      } else if (action == 'S') {
        auto s = engine.snapshot();
        std::string text = "{\"cols\":" + std::to_string(s.cols) +
          ",\"rows\":" + std::to_string(s.rows) + ",\"row\":" + std::to_string(s.row) +
          ",\"col\":" + std::to_string(s.col) + ",\"history\":" + std::to_string(s.history_rows) +
          ",\"sync\":" + std::to_string(s.synchronized_updates) + "}";
        respond(text.data(), text.size());
      } else if (action == 'A') {
        auto m = engine.memory_usage();
        std::string text = "{\"device_bytes\":" + std::to_string(m.device_bytes) +
          ",\"image_bytes\":" + std::to_string(m.image_bytes) +
          ",\"transfer_bytes\":" + std::to_string(m.transfer_bytes) +
          ",\"history_capacity\":" + std::to_string(m.history_capacity) + "}";
        respond(text.data(), text.size());
      } else if (action == 'W' && n == 8) {
        int dims[2]; std::memcpy(dims, bytes.data(), 8); engine.resize(dims[0], dims[1]);
        respond(nullptr, 0);
      } else if (action == 'M' && n == 28) {
        int event[7]; std::memcpy(event, bytes.data(), 28);
        engine.mouse(event[0], event[1], event[2], event[3], event[4], event[5], event[6]);
        auto reply = engine.take_replies(); respond(reply.data(), reply.size());
      } else throw std::runtime_error("unknown harness command");
    }
  } catch (const std::exception &e) { std::fprintf(stderr, "%s\n", e.what()); return 1; }
}
