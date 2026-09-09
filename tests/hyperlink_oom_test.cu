#include "engine.cuh"
#include "hyperlinks.cuh"
#include <cuda_runtime.h>
#include <stdexcept>
#include <string>

static int denied = 0;
extern "C" cudaError_t __real_cudaMalloc(void **, size_t);
extern "C" cudaError_t __wrap_cudaMalloc(void **pointer, size_t bytes) {
  if (bytes == sizeof(ct::Hyperlinks)) {
    ++denied;
    *pointer = nullptr;
    return cudaErrorMemoryAllocation;
  }
  return __real_cudaMalloc(pointer, bytes);
}

int main() {
  ct::Engine engine(20, 2);
  const std::string text = "\033]8;;https://example.org\007label\033]8;;\007 rest";
  for (unsigned char byte : text) engine.feed(&byte, 1);
  engine.select(0, 0, 0, 9);
  if (denied != 1 || engine.selected_text() != "label rest" ||
      !engine.hyperlink_at(0, 0).empty())
    throw std::runtime_error("link allocation failure must preserve terminal text");
  const std::string next = "\r\n" + text;
  engine.feed(reinterpret_cast<const unsigned char *>(next.data()), next.size());
  if (denied != 1 || !engine.hyperlink_at(1, 0).empty())
    throw std::runtime_error("disabled links must not retry allocation for each command");
}
