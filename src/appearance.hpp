#pragma once
#include <cstdint>

namespace ct {
struct Theme {
  uint32_t colors[262]; // Palette, defaults, cursor and selection.
  uint32_t customized; // Optional cursor/selection overrides; otherwise invert.
};
inline Theme default_theme() {
  Theme theme{};
  const uint32_t base[] = {0, 0x800000, 0x008000, 0x808000,
    0x000080, 0x800080, 0x008080, 0xc0c0c0, 0x808080, 0xff0000,
    0x00ff00, 0xffff00, 0x0000ff, 0xff00ff, 0x00ffff, 0xffffff};
  for (int i = 0; i < 256; ++i) {
    if (i < 16) theme.colors[i] = base[i];
    else if (i >= 232) theme.colors[i] = (8 + 10 * (i - 232)) * 0x010101u;
    else {
      int n = i - 16, r = n / 36, g = n / 6 % 6, b = n % 6;
      theme.colors[i] = ((r ? 55 + 40*r : 0) << 16) |
        ((g ? 55 + 40*g : 0) << 8) | (b ? 55 + 40*b : 0);
    }
  }
  theme.colors[256] = theme.colors[258] = theme.colors[261] = 0xffffff;
  return theme;
}
}
