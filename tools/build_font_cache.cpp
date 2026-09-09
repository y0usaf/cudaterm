#include "font.hpp"
#include <cstdio>

int main(int argc, char **argv) {
  try {
    if (argc != 6 || argv[5][0] != '/')
      throw std::runtime_error("expected FONT FALLBACK PIXELS LINE_HEIGHT ABSOLUTE_OUTPUT_DIRECTORY");
    auto number = [](const char *text, float low, float high) {
      size_t end;
      float value = std::stof(text, &end);
      if (text[end] || !(value >= low && value <= high))
        throw std::runtime_error("invalid font dimensions");
      return value;
    };
    float pixels = number(argv[3], 6, 64), line_height = number(argv[4], 0.5f, 3);
    std::filesystem::path output(argv[5]);
    if (!std::filesystem::is_directory(output) || !std::filesystem::is_empty(output))
      throw std::runtime_error("font cache output directory must exist and be empty");
    if (setenv("XDG_CACHE_HOME", argv[5], 1) || unsetenv("CUDATERM_PREPARED_FONTS"))
      throw std::runtime_error("cannot configure font cache output");
    ct::rasterize_font(std::string("file:") + argv[1], pixels, line_height,
                       std::string("file:") + argv[2]);
    // Runtime cache writes are best-effort; a build must fail if no atlas was saved.
    auto directory = output / "cudaterm/fonts";
    if (!std::filesystem::is_directory(directory) ||
        std::distance(std::filesystem::directory_iterator(directory), std::filesystem::directory_iterator()) != 1)
      throw std::runtime_error("cannot write prepared font cache");
    return 0;
  } catch (const std::exception &error) {
    std::fprintf(stderr, "cudaterm font cache: %s\n", error.what());
    return 1;
  }
}
