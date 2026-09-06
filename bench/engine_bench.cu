#include "engine.cuh"
#include <cuda_runtime.h>

#include <chrono>
#include <cstddef>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
struct Options {
  int cols = 80, rows = 24, repeats = 5, warmup = 1;
  std::size_t bytes = 4096;
  std::string workload = "text";
  bool render = false, dense = false, replies = false;
};
[[noreturn]] void bad(const std::string &s) {
  throw std::runtime_error(
      s + "\nusage: engine-bench [--cols N] [--rows N] [--repeats N] [--warmup "
          "N] [--bytes N] [--render [--dense] | --replies] [--workload "
          "text|ansi|unicode|graphics|tabs|emoji|marks|query|insert]");
}
template <typename T> T number(const char *option, const std::string &value) {
  try {
    std::size_t end = 0;
    unsigned long long n = std::stoull(value, &end);
    if (end != value.size() ||
        n > static_cast<unsigned long long>(std::numeric_limits<T>::max()))
      bad(std::string("invalid value for ") + option);
    return static_cast<T>(n);
  } catch (const std::exception &) {
    bad(std::string("invalid value for ") + option);
  }
}
Options parse(int argc, char **argv) {
  Options o;
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    if (a == "--render")
      o.render = true;
    else if (a == "--replies")
      o.replies = true;
    else if (a == "--dense")
      o.dense = true;
    else if (a == "--workload") {
      if (++i == argc)
        bad("missing value for --workload");
      o.workload = argv[i];
    } else if (a == "--cols" || a == "--rows" || a == "--repeats" ||
               a == "--warmup" || a == "--bytes") {
      if (++i == argc)
        bad("missing value for " + a);
      if (a == "--cols")
        o.cols = number<int>(a.c_str(), argv[i]);
      else if (a == "--rows")
        o.rows = number<int>(a.c_str(), argv[i]);
      else if (a == "--repeats")
        o.repeats = number<int>(a.c_str(), argv[i]);
      else if (a == "--warmup")
        o.warmup = number<int>(a.c_str(), argv[i]);
      else
        o.bytes = number<std::size_t>(a.c_str(), argv[i]);
    } else
      bad("unknown option: " + a);
  }
  if (o.cols < 1 || o.rows < 1 || o.repeats < 1 || o.warmup < 0 || o.bytes < 1)
    bad("cols, rows, repeats and bytes must be positive; warmup must be "
        "nonnegative");
  if (o.bytes > (1u << 20))
    bad("bytes must not exceed the engine input limit (1048576)");
  if (o.workload != "text" && o.workload != "ansi" && o.workload != "unicode" &&
      o.workload != "graphics" && o.workload != "tabs" &&
      o.workload != "emoji" && o.workload != "marks" &&
      o.workload != "query" && o.workload != "insert")
    bad("workload must be text, ansi, unicode, graphics, tabs, emoji, marks, query or insert");
  if (o.replies && o.render)
    bad("--replies and --render are mutually exclusive");
  if (o.dense && !o.render)
    bad("--dense requires --render");
  return o;
}
std::vector<unsigned char> make_payload(const Options &o) {
  std::string pattern =
      o.workload == "query"      ? "\x1b[6n"
      : o.workload == "insert"    ? "0123456789abcdefghijklmnopqrstuvwxyz\r\n"
      : o.workload == "emoji"      ? "😀"
      : o.workload == "marks"    ? "ée𝆅"
      : o.workload == "tabs"     ? "column\tvalue\r\n"
      : o.workload == "graphics" ? "\x1b[32mlqqqqqqk\x1b[0m\r\n"
      : o.workload == "text"     ? "0123456789abcdefghijklmnopqrstuvwxyz\r\n"
      : o.workload == "ansi"
          ? "\x1b[31mred\x1b[0m \x1b[38;2;10;200;70mgreen\x1b[0m\r\n"
          : "Latin é Ελληνικά 日本語 😀\r\n";
  if (o.dense) {
    size_t pos;
    while ((pos = pattern.find("\r\n")) != std::string::npos)
      pattern.erase(pos, 2);
  }
  const std::size_t framing = o.workload == "graphics"
                                  ? 6
                                  : o.workload == "insert" ? 8 : 0;
  const std::size_t count =
      o.bytes >= framing ? (o.bytes - framing) / pattern.size() : 0;
  if (!count)
    bad("bytes is smaller than one complete workload pattern");
  std::vector<unsigned char> result(count * pattern.size());
  for (std::size_t i = 0; i < result.size(); ++i)
    result[i] = static_cast<unsigned char>(pattern[i % pattern.size()]);
  if (o.workload == "graphics") {
    result.insert(result.begin(), {27, '(', '0'});
    result.insert(result.end(), {27, '(', 'B'});
  } else if (o.workload == "insert") {
    result.insert(result.begin(), {27, '[', '4', 'h'});
    result.insert(result.end(), {27, '[', '4', 'l'});
  }
  return result;
}
void ck(cudaError_t status) {
  if (status != cudaSuccess)
    throw std::runtime_error(cudaGetErrorString(status));
}
struct FrameTimer {
  uint32_t *pixels = nullptr;
  cudaEvent_t begin = nullptr, end = nullptr;
  ~FrameTimer() {
    cudaFree(pixels);
    if (begin)
      cudaEventDestroy(begin);
    if (end)
      cudaEventDestroy(end);
  }
  void init(int width, int height) {
    ck(cudaMalloc(&pixels, size_t(width) * height * sizeof(uint32_t)));
    ck(cudaEventCreate(&begin));
    ck(cudaEventCreate(&end));
  }
  double sample(ct::Engine &engine, int width, int height) {
    ck(cudaEventRecord(begin));
    engine.render(pixels, width, height);
    ck(cudaEventRecord(end));
    ck(cudaEventSynchronize(end));
    float ms = 0;
    ck(cudaEventElapsedTime(&ms, begin, end));
    return double(ms) * 1000000;
  }
};
} // namespace
int main(int argc, char **argv) {
  try {
    const Options o = parse(argc, argv);
    const auto bytes = make_payload(o);
    ct::Engine engine(o.cols, o.rows);
    FrameTimer timer;
    if (o.render) {
      engine.feed(bytes.data(), bytes.size());
      timer.init(o.cols * 8, o.rows * 16);
    }
    for (int i = 0; i < o.warmup; ++i) {
      if (o.render)
        timer.sample(engine, o.cols * 8, o.rows * 16);
      else if (o.replies)
        engine.feed_and_replies(bytes.data(), bytes.size());
      else
        engine.feed(bytes.data(), bytes.size());
    }
    std::cout << "{\"benchmark\":\""
              << (o.render ? "engine-render-cuda-event"
                           : o.replies ? "engine-feed-replies" : "engine-feed")
              << "\",\"dense\":" << (o.dense ? "true" : "false")
              << ",\"workload\":\"" << o.workload << "\",\"cols\":" << o.cols
              << ",\"rows\":" << o.rows << ",\"requested_bytes\":" << o.bytes
              << ",\"bytes\":" << bytes.size() << ",\"warmup\":" << o.warmup
              << ",\"repeats\":" << o.repeats << ",\"samples\":[";
    for (int i = 0; i < o.repeats; ++i) {
      const auto start = std::chrono::steady_clock::now();
      if (o.replies)
        engine.feed_and_replies(bytes.data(), bytes.size());
      else if (!o.render)
        engine.feed(bytes.data(), bytes.size());
      const auto host_elapsed =
          std::chrono::duration_cast<std::chrono::nanoseconds>(
              std::chrono::steady_clock::now() - start)
              .count();
      double elapsed = o.render ? timer.sample(engine, o.cols * 8, o.rows * 16)
                                : double(host_elapsed);
      if (i)
        std::cout << ',';
      std::cout << "{\"duration_ns\":";
      if (o.render)
        std::cout << elapsed;
      else
        std::cout << host_elapsed;
      std::cout << (o.render ? ",\"ns_per_pixel\":" : ",\"ns_per_byte\":")
                << elapsed / (o.render ? size_t(o.cols) * 8 * o.rows * 16
                                       : bytes.size())
                << '}';
    }
    std::cout << "]}\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "engine-bench: " << e.what() << '\n';
    return 2;
  }
}
