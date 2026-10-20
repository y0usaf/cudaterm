__device__ int osc_number(const char *&p, const char *end) {
  if (p == end || *p < '0' || *p > '9') return -1;
  int n = 0;
  while (p < end && *p >= '0' && *p <= '9') {
    n = dmin(1000000, n * 10 + *p++ - '0');
  }
  return n;
}
__device__ bool osc_color(const char *p, const char *end, uint32_t &color) {
  bool rgb = end - p >= 4 && p[0] == 'r' && p[1] == 'g' && p[2] == 'b' && p[3] == ':';
  int digits = 0;
  if (rgb) p += 4;
  else {
    if (p == end || *p++ != '#' || (end - p) % 3) return false;
    digits = (end - p) / 3;
    if (digits < 1 || digits > 4) return false;
  }
  color = 0;
  for (int channel = 0; channel < 3; ++channel) {
    unsigned value = 0;
    int count = 0;
    while (p < end && (rgb ? *p != '/' : count < digits)) {
      int x = *p++;
      int h = x >= '0' && x <= '9' ? x - '0' :
              x >= 'a' && x <= 'f' ? x - 'a' + 10 :
              x >= 'A' && x <= 'F' ? x - 'A' + 10 : -1;
      if (h < 0 || ++count > 4) return false;
      value = value * 16 + h;
    }
    if (!count) return false;
    unsigned maximum = (1u << (4 * count)) - 1;
    color = (color << 8) | (value * 255 / maximum);
    if (rgb && channel < 2 && (p == end || *p++ != '/')) return false;
  }
  return p == end;
}
__device__ int decimal_digits(int value) {
  int n = 1;
  while (value /= 10) ++n;
  return n;
}
__device__ void osc_reply(DeviceState &s, int command, int index, uint32_t color, bool bell) {
  int n = 21 + decimal_digits(command) + (command == 4 ? decimal_digits(index) + 1 : 0) + (bell ? 1 : 2);
  if (s.reply_len + n > REPLY_CAP) return;
  reply_text(s, "\033]");
  reply_decimal(s, command);
  reply_text(s, ";");
  if (command == 4) { reply_decimal(s, index); reply_text(s, ";"); }
  reply_text(s, "rgb:");
  for (int shift = 16; shift >= 0; shift -= 8) {
    unsigned v = ((color >> shift) & 255) * 257;
    for (int bit = 12; bit >= 0; bit -= 4) reply_byte(s, "0123456789abcdef"[(v >> bit) & 15]);
    if (shift) reply_text(s, "/");
  }
  reply_text(s, bell ? "\a" : "\033\\");
}
__device__ bool title_utf8(const char *p, const char *end) {
  while (p < end) {
    unsigned c = (unsigned char)*p++;
    if (c < 32 || c == 127) return false;
    if (c < 128) continue;
    int n = c >= 0xc2 && c <= 0xdf ? 1 : c <= 0xef && c >= 0xe0 ? 2 :
            c >= 0xf0 && c <= 0xf4 ? 3 : -1;
    if (n < 0 || end - p < n) return false;
    unsigned cp = c & ((1u << (6 - n)) - 1);
    for (int i = 0; i < n; ++i) {
      unsigned next = (unsigned char)*p++;
      if ((next & 0xc0) != 0x80) return false;
      cp = (cp << 6) | (next & 63);
    }
    if (cp < (n == 1 ? 0x80u : n == 2 ? 0x800u : 0x10000u) ||
        cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) return false;
  }
  return true;
}
__device__ void finish_osc(DeviceState &s, bool bell) {
  const char *p = s.osc_text, *end = p + s.osc_len;
  int command = osc_number(p, end);
  if (command < 0 || (p < end && *p++ != ';')) return;
  if (command == 8) {
    const char *uri = p;
    while (uri < end && *uri != ';') ++uri;
    if (uri == end) return;
    ++uri;
    if (!title_utf8(uri, end)) return;
    if (uri == end) {
      const char *params_end = uri - 1;
      for (const char *param = p; param < params_end;) {
        const char *stop = param;
        while (stop < params_end && *stop != ':') ++stop;
        const char *equal = param;
        while (equal < stop && *equal != '=') ++equal;
        if (equal - param == 2 && param[0] == 'i' && param[1] == 'd' &&
            equal + 1 < stop)
          return;
        param = stop < params_end ? stop + 1 : params_end;
      }
      s.hyperlink_id = 0;
      return;
    }
    if (s.hyperlinks_disabled) { s.hyperlink_id = 0; return; }
    if (!s.hyperlinks) {
      s.graphics->request = {};
      s.graphics->request.ready = 1;
      s.graphics->request.barrier = 3;
      return;
    }
    auto &links = *s.hyperlinks;
    for (unsigned i = 0; i < HYPERLINK_SLOTS; ++i) {
      const auto &entry = links.entries[i];
      if (!entry.id) continue;
      int n = 0;
      while (uri + n < end && entry.uri[n] == uri[n]) ++n;
      if (uri + n == end && !entry.uri[n]) { s.hyperlink_id = entry.id; return; }
    }
    if (links.next_id == HYPERLINK_MAX_ID) { s.hyperlink_id = 0; return; }
    uint32_t id = ++links.next_id;
    auto &entry = links.entries[(id - 1) % HYPERLINK_SLOTS];
    entry.id = id;
    int n = 0;
    while (uri < end) entry.uri[n++] = *uri++;
    entry.uri[n] = 0;
    s.hyperlink_id = id;
  } else if (command == 0 || command == 2) {
    if (!title_utf8(p, end)) return;
    int n = 0;
    while (p < end) s.replies->title[n++] = *p++;
    s.replies->title[n] = 0;
    s.replies->title_changed = 1;
  } else if (command == 104) {
    if (p == end) {
      for (int i = 0; i < 256; ++i) s.theme.colors[i] = s.base_theme.colors[i];
    } else while (p < end) {
      int index = osc_number(p, end);
      if (index < 0 || index > 255 || (p < end && *p++ != ';')) return;
      s.theme.colors[index] = s.base_theme.colors[index];
    }
  } else if (command >= 110 && command <= 112 && p == end) {
    s.theme.colors[256 + command - 110] = s.base_theme.colors[256 + command - 110];
    if (command == 112) s.theme.customized = (s.theme.customized & ~1u) | (s.base_theme.customized & 1);
  } else if (command == 4 || (command >= 10 && command <= 12)) {
    int next = command;
    while (p < end) {
      int index = command == 4 ? osc_number(p, end) : 256 + next - 10;
      if (command == 4 && (p == end || *p++ != ';')) return;
      if (index < 0 || index >= 259 || (command == 4 && index > 255)) return;
      const char *stop = p;
      while (stop < end && *stop != ';') ++stop;
      uint32_t color;
      if (stop - p == 1 && *p == '?')
        osc_reply(s, command == 4 ? 4 : next, index, s.theme.colors[index], bell);
      else if (osc_color(p, stop, color)) {
        s.theme.colors[index] = color;
        if (index == 258) s.theme.customized |= 1;
      }
      p = stop < end ? stop + 1 : end;
      if (command != 4 && ++next > 12) return;
    }
  }
}
__device__ float acc_linear(uint32_t color, int shift) {
  float v = (color >> shift & 255) / 255.0f;
  return v <= 0.04045f ? v / 12.92f : __powf((v + 0.055f) / 1.055f, 2.4f);
}
__device__ float acc_luminance(float r, float g, float b) { return 0.2126f * r + 0.7152f * g + 0.0722f * b; }
__device__ float acc_luminance(uint32_t color) {
  return acc_luminance(acc_linear(color, 16), acc_linear(color, 8), acc_linear(color, 0));
}
__device__ float acc_ratio(float y, float z) { return (fmaxf(y, z) + 0.05f) / (fminf(y, z) + 0.05f); }
__device__ void acc_oklab(uint32_t color, float &L, float &a, float &b) {
  float r = acc_linear(color, 16), g = acc_linear(color, 8), u = acc_linear(color, 0);
  float l = cbrtf(0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * u);
  float m = cbrtf(0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * u);
  float s = cbrtf(0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * u);
  L = 0.2104542553f * l + 0.7936177850f * m - 0.0040720468f * s;
  a = 1.9779984951f * l - 2.4285922050f * m + 0.4505937099f * s;
  b = 0.0259040371f * l + 0.7827717662f * m - 0.8086757660f * s;
}
__device__ float3 acc_rgb(float L, float a, float b) {
  float l = L + 0.3963377774f * a + 0.2158037573f * b;
  float m = L - 0.1055613458f * a - 0.0638541728f * b;
  float s = L - 0.0894841775f * a - 1.2914855480f * b;
  l *= l * l; m *= m * m; s *= s * s;
  return {__saturatef(4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s),
          __saturatef(-1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s),
          __saturatef(-0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s)};
}
__device__ float acc_luminance(float3 c) { return acc_luminance(c.x, c.y, c.z); }
__device__ uint32_t acc_encode(float v, float round) {
  return (v <= 0.0031308f ? 12.92f * v : 1.055f * __powf(v, 1 / 2.4f) - 0.055f) * 255 + round;
}
__device__ __noinline__ uint32_t acc_fit(float target, uint32_t fg, uint32_t bg) {
  float y = acc_luminance(bg), L, a, b;
  if (acc_ratio(acc_luminance(fg), y) >= target) return fg;
  acc_oklab(fg, L, a, b);
  float end = acc_luminance(fg) > y ? 1 : 0, reach = acc_ratio(acc_luminance(acc_rgb(end, a, b)), y);
  if (reach < target && acc_ratio(acc_luminance(acc_rgb(1 - end, a, b)), y) > reach) end = 1 - end;
  for (int i = 0; i < 16; ++i) {
    float mid = (L + end) / 2;
    if (acc_ratio(acc_luminance(acc_rgb(mid, a, b)), y) < target) L = mid;
    else end = mid;
  }
  float3 c = acc_rgb(end, a, b);
  float round = end > L ? 0.999f : 0;
  return acc_encode(c.x, round) << 16 | acc_encode(c.y, round) << 8 | acc_encode(c.z, round);
}
__device__ bool acc_graphic(uint32_t cp) {
  return (cp >= 0x2500 && cp <= 0x259f) || (cp >= 0x1fb00 && cp <= 0x1fbff) || (cp >= 0xe0b0 && cp <= 0xe0d7);
}
__device__ uint32_t acc_correct(const DeviceState &s, uint32_t fg, uint32_t bg) {
  const uint64_t span = (1ull << 48) / ACC_SLOTS;
  uint64_t key = ((uint64_t(fg) << 24 | bg) * 0x9e3779b97f4a7c15ull) & ((1ull << 48) - 1);
  uint64_t tag = 1ull << 63 | key % span << 24, entry = s.acc[key / span];
  if ((entry & ~0xffffffull) == tag) return entry & 0xffffff;
  uint32_t out = acc_fit(s.theme.contrast_floor, fg, bg);
  s.acc[key / span] = tag | out;
  return out;
}
