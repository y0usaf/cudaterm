#include "engine.cuh"
#include <chrono>
#include <cstdio>
#include <stdexcept>
#include <string>

static void feed(ct::Engine &e, const std::string &text) {
  e.feed(reinterpret_cast<const unsigned char *>(text.data()), text.size());
}
int main(int argc, char **argv) {
  try {
    if (argc != 3) throw std::runtime_error("expected columns and hard|soft");
    int cols = std::stoi(argv[1]);
    if (cols != 80 && cols != 318) throw std::runtime_error("columns must be 80 or 318");
    std::string kind = argv[2], query;
    if (kind != "hard" && kind != "soft") throw std::runtime_error("expected hard or soft");
    ct::Engine engine(cols, 24);
    if (kind == "hard") {
      std::string text;
      for (int i = 0; i < 5000; ++i)
        text += "line-" + std::to_string(i) + (i == 1500 || i == 4900 ? "-needle\r\n" : "-filler\r\n");
      feed(engine, text); query = "needle";
    } else {
      for (int i = 0; i < 5; ++i) feed(engine, std::string(262144, 'X'));
      query.assign(256, 'X');
    }
    size_t baseline = engine.memory_usage().device_bytes;
    for (int i = 0; i < 5; ++i)
      if (!engine.search(query, ct::SearchDirection::Backward, true).found)
        throw std::runtime_error("warmup query not found");
    std::printf("{\"columns\":%d,\"rows\":24,\"case\":\"%s\",\"query_codepoints\":%zu,\"warmup\":5,\"samples_ns\":[", cols, kind.c_str(), query.size());
    for (int i = 0; i < 40; ++i) {
      auto begin = std::chrono::steady_clock::now();
      auto match = engine.search(query, ct::SearchDirection::Backward, true);
      auto end = std::chrono::steady_clock::now();
      if (!match.found) throw std::runtime_error("query not found");
      std::printf("%s%lld", i ? "," : "", (long long)std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count());
    }
    size_t active = engine.memory_usage().device_bytes;
    engine.clear_search();
    size_t cleared = engine.memory_usage().device_bytes;
    std::printf("],\"device_bytes_before\":%zu,\"device_bytes_active\":%zu,\"device_bytes_cleared\":%zu}\n", baseline, active, cleared);
    if (cleared != baseline) throw std::runtime_error("search scratch retained after clear");
  } catch (const std::exception &e) { std::fprintf(stderr, "%s\n", e.what()); return 1; }
}
