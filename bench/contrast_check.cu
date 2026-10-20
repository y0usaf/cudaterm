#include "engine.cuh"
#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <stdexcept>

namespace {
void ck(cudaError_t status) {
  if (status != cudaSuccess) throw std::runtime_error(cudaGetErrorString(status));
}
double luminance(const uchar4 &p) {
  double sum = 0;
  const double weight[] = {0.2126, 0.7152, 0.0722};
  const unsigned char channel[] = {p.x, p.y, p.z};
  for (int i = 0; i < 3; ++i) {
    double v = channel[i] / 255.0;
    sum += weight[i] * (v <= 0.04045 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4));
  }
  return sum;
}
double ratio(const uchar4 &a, const uchar4 &b) {
  double x = luminance(a) + 0.05, y = luminance(b) + 0.05;
  return x > y ? x / y : y / x;
}
void render(ct::Engine &engine, float floor, uchar4 (&image)[16][32]) {
  ct::Theme theme = ct::default_theme();
  theme.colors[256] = 0x1b1f27;
  theme.colors[257] = 0xf5f6fa;
  theme.contrast_floor = floor;
  engine.set_theme(theme);
  cudaArray_t pixels = nullptr;
  cudaSurfaceObject_t surface = 0;
  const cudaChannelFormatDesc format = cudaCreateChannelDesc<uchar4>();
  ck(cudaMallocArray(&pixels, &format, 32, 16, cudaArraySurfaceLoadStore));
  cudaResourceDesc target{};
  target.resType = cudaResourceTypeArray;
  target.res.array.array = pixels;
  ck(cudaCreateSurfaceObject(&surface, &target));
  engine.render(surface, 32, 16);
  ck(cudaMemcpy2DFromArray(image, sizeof(image[0]), pixels, 0, 0, sizeof(image[0]), 16,
                           cudaMemcpyDeviceToHost));
  cudaDestroySurfaceObject(surface);
  cudaFreeArray(pixels);
}
double rendered_ratio(ct::Engine &engine, float floor) {
  uchar4 image[16][32];
  render(engine, floor, image);
  const uchar4 paper = image[0][31];
  double ink = 0;
  for (int y = 0; y < 16; ++y)
    for (int x = 0; x < 8; ++x)
      ink = std::max(ink, ratio(image[y][x], paper));
  return ink;
}
}
int main() {
  try {
    ct::Engine engine(4, 1);
    engine.set_cell_size(8, 16);
    const char text[] = "\033[38;2;128;128;128mX";
    engine.feed(reinterpret_cast<const unsigned char *>(text), sizeof(text) - 1);
    double off = rendered_ratio(engine, 0), on = rendered_ratio(engine, 4.5f);
    ct::Engine block(4, 1);
    block.set_cell_size(8, 16);
    const char half[] = "\033[38;2;92;42;104;48;2;184;71;110m\xe2\x96\x80";
    block.feed(reinterpret_cast<const unsigned char *>(half), sizeof(half) - 1);
    uchar4 image[16][32];
    render(block, 4.5f, image);
    const uchar4 top = image[2][4];
    bool kept = top.x == 92 && top.y == 42 && top.z == 104;
    std::printf("{\"floor_0\":%.3f,\"floor_4_5\":%.3f,\"half_block_top\":\"%02x%02x%02x\",\"half_block_kept\":%s}\n",
                off, on, top.x, top.y, top.z, kept ? "true" : "false");
    return off < 4.5 && on >= 4.5 && kept ? 0 : 1;
  } catch (const std::exception &e) {
    std::fprintf(stderr, "contrast-check: %s\n", e.what());
    return 2;
  }
}
