// Bounded OSC handling on the GPU. Unknown commands and malformed/oversized
// strings are discarded; bytes never become printable terminal input.
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
__device__ int osc_decimal(char *out, int n, int value) {
  char digits[8]; int count = 0;
  do { digits[count++] = '0' + value % 10; value /= 10; } while (value);
  while (count) out[n++] = digits[--count];
  return n;
}
__device__ void osc_reply(DeviceState &s, int command, int index, uint32_t color, bool bell) {
  char out[48] = {27, ']'};
  int n = osc_decimal(out, 2, command);
  out[n++] = ';';
  if (command == 4) { n = osc_decimal(out, n, index); out[n++] = ';'; }
  out[n++] = 'r'; out[n++] = 'g'; out[n++] = 'b'; out[n++] = ':';
  const char *hex = "0123456789abcdef";
  for (int shift = 16; shift >= 0; shift -= 8) {
    unsigned v = ((color >> shift) & 255) * 257;
    for (int bit = 12; bit >= 0; bit -= 4) out[n++] = hex[(v >> bit) & 15];
    if (shift) out[n++] = '/';
  }
  if (bell) out[n++] = 7;
  else { out[n++] = 27; out[n++] = '\\'; }
  if (s.reply_len + n <= REPLY_CAP) reply(s, out, n);
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
  if (command == 0 || command == 2) {
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
