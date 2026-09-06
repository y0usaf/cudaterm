#pragma once
__device__ uint32_t graphic_value(const GraphicsParams &p, char key, uint32_t fallback = 0) {
  return p.seen[(int)key] ? p.value[(int)key] : fallback;
}
__device__ int image_slot(const GraphicsState &g, uint32_t id) {
  for (int i = 0; i < IMAGE_SLOTS; ++i)
    if (g.images[i].pixels && g.images[i].id == id) return i;
  return -1;
}
__device__ void graphic_begin(GraphicsState &g) {
  g.command = {};
  g.chunk_size = g.invalid = g.phase = g.key = g.digits = g.header_size = 0;
  g.value = 0;
}
__device__ void graphic_parameter(GraphicsState &g) {
  if (g.phase != 2 || !g.digits || g.command.seen[g.key]) g.invalid = 1;
  if (!g.invalid) {
    g.command.seen[g.key] = 1;
    g.command.value[g.key] = g.value;
  }
  g.phase = g.key = g.digits = 0;
  g.value = 0;
}
__device__ void graphic_header(GraphicsState &g, unsigned char c) {
  if (++g.header_size > 1024) { g.invalid = 1; return; }
  if (c == ',') { graphic_parameter(g); return; }
  if (g.phase == 0) {
    bool known = false;
    const char *keys = "atfovsiphwxyXYmCqd";
    for (int i = 0; keys[i]; ++i) known |= keys[i] == c;
    if (!known) { g.invalid = 1; return; }
    g.key = c; g.phase = 1;
  } else if (g.phase == 1) {
    if (c != '=') g.invalid = 1;
    g.phase = 2;
  } else if (g.key == 'a' || g.key == 't' || g.key == 'o' || g.key == 'd') {
    if (g.digits) g.invalid = 1;
    g.value = c; ++g.digits;
  } else {
    if (c < '0' || c > '9' || g.value > (0xffffffffu - (c - '0')) / 10) {
      g.invalid = 1; return;
    }
    g.value = 10 * g.value + c - '0'; ++g.digits;
  }
}
__device__ void graphic_plan(DeviceState &s) {
  auto &g = *s.graphics;
  g.request = {};
  g.request.ready = 1;
  g.request.slot = -1;
  auto &p = g.command;
  unsigned action = graphic_value(p, 'a', 't');
  if (g.active) {
    // Continuations carry only m and optionally q.
    for (int i = 0; i < 128; ++i)
      if (p.seen[i] && i != 'm' && i != 'q') g.invalid = 1;
    if (p.seen['q']) { g.upload.seen['q'] = 1; g.upload.value['q'] = p.value['q']; }
    action = graphic_value(g.upload, 'a', 't');
  } else if (action == 't' || action == 'T' || action == 'q') {
    g.upload = p;
    g.used = 0;
    g.active = 1;
  }
  if (graphic_value(p, 'm') > 1 || graphic_value(p, 'q') > 2) g.invalid = 1;
  if (g.active) {
    const auto &u = g.upload;
    unsigned f = graphic_value(u, 'f', 32), compression = graphic_value(u, 'o');
    size_t width = graphic_value(u, 's'), height = graphic_value(u, 'v');
    if ((f != 24 && f != 32) || graphic_value(u, 't', 'd') != 'd' ||
        (compression && compression != 'z') || !width || !height ||
        width > 8192 || height > 8192 || width * height * (f / 8) > IMAGE_LIMIT ||
        g.chunk_size % 4) g.invalid = 1;
    g.request.input_bytes = g.used + size_t(g.chunk_size / 4) * 3;
    if (g.request.input_bytes > IMAGE_LIMIT + (1u << 16)) g.invalid = 1;
    if (!graphic_value(p, 'm') && !g.invalid) {
      uint32_t id = graphic_value(u, 'i');
      if (!id) {
        do { ++g.next_id; } while (!g.next_id || image_slot(g, g.next_id) >= 0);
        g.upload.seen['i'] = 1; g.upload.value['i'] = id = g.next_id;
        // Anonymous transfers do not request a response.
        g.upload.seen['q'] = 1; g.upload.value['q'] = 2;
      }
      int slot = image_slot(g, id);
      if (slot < 0)
        for (int i = 0; i < IMAGE_SLOTS; ++i)
          if (!g.images[i].pixels) { slot = i; break; }
      size_t bytes = width * height * (f / 8), total = bytes;
      for (int i = 0; i < IMAGE_SLOTS; ++i)
        if (i != slot && g.images[i].pixels)
          total += size_t(g.images[i].width) * g.images[i].height * g.images[i].channels;
      if (slot < 0 || total > IMAGE_BUDGET) g.invalid = 1;
      else { g.request.slot = slot; g.request.output_bytes = bytes; }
    }
  } else if (action == 'd') {
    unsigned which = graphic_value(p, 'd', 'a');
    if (which != 'a' && which != 'A' && which != 'i' && which != 'I') g.invalid = 1;
    for (int i = 0; i < IMAGE_SLOTS && !g.invalid; ++i) {
      auto &im = g.images[i];
      if (!im.pixels || im.screen != s.alt_active) continue;
      if ((which == 'i' || which == 'I') && im.id != graphic_value(p, 'i')) continue;
      if (which == 'A' || which == 'I') g.request.release[i / 32] |= 1u << (i % 32);
    }
  } else if (action != 'p') g.invalid = 1;
  // Placement can scroll hundreds of rows even for a tiny compressed command.
  // Tell the allocator that bound before executing it, without CPU parsing.
  if (!g.invalid && !s.alt_active) {
    if (g.active && action == 'T' && g.request.output_bytes && !graphic_value(g.upload, 'C'))
      g.request.history_growth = (graphic_value(g.upload, 'v') + 2 * s.cell_height - 2) / s.cell_height;
    else if (!g.active && action == 'p' && !graphic_value(p, 'C')) {
      int slot = image_slot(g, graphic_value(p, 'i'));
      if (slot >= 0) g.request.history_growth = (g.images[slot].height + 2 * s.cell_height - 2) / s.cell_height;
    }
  }
  if (g.invalid) {
    g.request.input_bytes = g.request.output_bytes = 0;
    for (auto &bits : g.request.release) bits = 0;
  }
}
__device__ void graphic_reply(DeviceState &s, const GraphicsParams &p, bool success) {
  unsigned q = graphic_value(p, 'q');
  uint32_t id = graphic_value(p, 'i');
  if (!id || q == 2 || (q == 1 && success)) return;
  char out[80] = {27, '_', 'G', 'i', '='};
  char digits[10]; int n = 5, count = 0;
  do { digits[count++] = '0' + id % 10; id /= 10; } while (id);
  while (count) out[n++] = digits[--count];
  unsigned placement = graphic_value(p, 'p');
  if (placement) {
    out[n++] = ','; out[n++] = 'p'; out[n++] = '=';
    do { digits[count++] = '0' + placement % 10; placement /= 10; } while (placement);
    while (count) out[n++] = digits[--count];
  }
  out[n++] = ';';
  const char *message = success ? "OK" : "EINVAL: invalid or unsupported graphics command";
  for (int i = 0; message[i]; ++i) out[n++] = message[i];
  out[n++] = 27; out[n++] = '\\';
  reply(s, out, n);
}
__device__ int base64_digit(unsigned char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  return c == '+' ? 62 : c == '/' ? 63 : -1;
}
__device__ bool graphic_decode(GraphicsState &g, unsigned char *input) {
  const int lane = threadIdx.x;
  bool valid = true;
  const size_t start = g.used;
  for (int i = lane * 4; i < g.chunk_size; i += blockDim.x * 4) {
    int a = base64_digit(g.chunk[i]), b = base64_digit(g.chunk[i+1]);
    int c = base64_digit(g.chunk[i+2]), d = base64_digit(g.chunk[i+3]);
    bool pad_c = g.chunk[i+2] == '=', pad_d = g.chunk[i+3] == '=';
    if (a < 0 || b < 0 || (c < 0 && !pad_c) || (d < 0 && !pad_d) ||
        (pad_c && !pad_d) || ((pad_c || pad_d) &&
        (i + 4 != g.chunk_size || graphic_value(g.command, 'm'))) ||
        (pad_c && (b & 15)) || (!pad_c && pad_d && (c & 3))) { valid = false; continue; }
    size_t at = start + (i / 4) * 3;
    input[at] = (a << 2) | (b >> 4);
    if (!pad_c) input[at+1] = (b << 4) | (c >> 2);
    if (!pad_d) input[at+2] = (c << 6) | d;
  }
  valid = __syncthreads_count(!valid) == 0;
  if (!lane && valid) {
    g.used += g.chunk_size / 4 * 3;
    if (g.chunk_size && g.chunk[g.chunk_size-1] == '=') --g.used;
    if (g.chunk_size && g.chunk[g.chunk_size-2] == '=') --g.used;
  }
  __syncthreads();
  return valid;
}
__device__ bool graphic_place(DeviceState &s, Image &image, const GraphicsParams &p) {
  unsigned sx = graphic_value(p, 'x'), sy = graphic_value(p, 'y');
  unsigned w = graphic_value(p, 'w', image.width), h = graphic_value(p, 'h', image.height);
  unsigned x = graphic_value(p, 'X'), y = graphic_value(p, 'Y');
  if (sx >= unsigned(image.width) || sy >= unsigned(image.height) ||
      !w || !h || x >= unsigned(s.cell_width) || y >= unsigned(s.cell_height) || graphic_value(p, 'C') > 1) return false;
  image.sx = sx; image.sy = sy;
  image.width_crop = dmin(w, unsigned(image.width) - sx);
  image.height_crop = dmin(h, unsigned(image.height) - sy);
  image.px = s.col * s.cell_width + x; image.py = s.row * s.cell_height + y;
  image.screen = s.alt_active; image.visible = 1;
  image.placement = graphic_value(p, 'p');
  return true;
}
__device__ void graphic_cursor(DeviceState &s, const Image &image, const GraphicsParams &p,
                                FillJob *jobs) {
  if (graphic_value(p, 'C')) return;
  auto &g = *s.graphics;
  g.visible_count = 0;
  for (int i = 0; i < IMAGE_SLOTS; ++i)
    if (g.images[i].visible) g.visible[g.visible_count++] = i;
  s.jobs = jobs;
  s.job_count = 0;
  int rows = (image.height_crop + graphic_value(p, 'Y') + s.cell_height - 1) / s.cell_height;
  for (int i = 1; i < rows; ++i) {
    newline(s);
    for (int j = 0; j < s.job_count; ++j) {
      auto &job = jobs[j];
      for (int k = 0; k < job.count; ++k)
        job.first[k] = job.source ? job.source[k] : job.value;
    }
    s.job_count = 0;
  }
  s.col = dmin(s.cols - 1, s.col + (image.width_crop + int(graphic_value(p, 'X')) + s.cell_width - 1) / s.cell_width);
  s.wrap_pending = 0; s.jobs = nullptr;
}
__global__ void graphics_decode(DeviceState *s, unsigned char *input,
                                 unsigned char *output, size_t capacity, bool allocation_failed) {
  __shared__ ct::inflate::Workspace workspace;
  auto &g = *s->graphics;
  int lane = threadIdx.x;
  if (g.request.reset || g.request.barrier || !g.active) return;
  if (!lane) {
    g.input = input; g.input_capacity = capacity;
    if (allocation_failed) g.invalid = 1;
  }
  __syncthreads();
  if (!g.invalid) {
    bool ok = graphic_decode(g, input);
    if (!lane && !ok) g.invalid = 1;
  }
  __syncthreads();
  if (g.invalid || graphic_value(g.command, 'm')) return;
  if (graphic_value(g.upload, 'o') == 'z') {
    bool ok = ct::inflate::decode(input, g.used, output, g.request.output_bytes, workspace);
    if (!lane && !ok) g.invalid = 1;
  } else {
    if (g.used != g.request.output_bytes) {
      if (!lane) g.invalid = 1;
    } else for (size_t i = lane; i < g.used; i += blockDim.x) output[i] = input[i];
  }
}
__global__ void graphics_execute(DeviceState *s, unsigned char *input,
                                  unsigned char *output, bool allocation_failed) {
  __shared__ FillJob jobs[MAX_ROWS + 4];
  if (threadIdx.x) return;
  auto &g = *s->graphics;
  auto &r = g.request;
  if (r.reset) {
    for (int i = 0; i < IMAGE_SLOTS; ++i)
      if (r.release[i / 32] & (1u << (i % 32))) g.images[i] = {};
    g.command = {}; g.active = 0; g.used = 0;
  }
  bool ok = !g.invalid && !allocation_failed;
  if (r.barrier && !r.reset) {
    // Storage ownership is unchanged; only the host's history hint changes.
  } else if (g.active) {
    bool more = graphic_value(g.command, 'm');
    if (!more || !ok) {
      unsigned action = graphic_value(g.upload, 'a', 't');
      if (ok && action != 'q') {
        Image im{};
        im.pixels = output; im.id = graphic_value(g.upload, 'i');
        im.width = graphic_value(g.upload, 's'); im.height = graphic_value(g.upload, 'v');
        im.channels = graphic_value(g.upload, 'f', 32) / 8; im.screen = s->alt_active;
        if (action == 'T') ok = graphic_place(*s, im, g.upload);
        if (ok) {
          g.images[r.slot] = im; r.committed = 1;
          if (action == 'T') graphic_cursor(*s, g.images[r.slot], g.upload, jobs);
        }
      }
      graphic_reply(*s, g.upload, ok);
      g.active = 0; g.used = 0;
    }
  } else if (!r.reset) {
    unsigned action = graphic_value(g.command, 'a', 't');
    if (action == 'p' && ok) {
      int slot = image_slot(g, graphic_value(g.command, 'i'));
      ok = slot >= 0 && graphic_place(*s, g.images[slot], g.command);
      if (ok) graphic_cursor(*s, g.images[slot], g.command, jobs);
    } else if (action == 'd' && ok) {
      unsigned which = graphic_value(g.command, 'd', 'a');
      for (int i = 0; i < IMAGE_SLOTS; ++i) {
        if (r.release[i / 32] & (1u << (i % 32))) g.images[i] = {};
        else if (g.images[i].screen == s->alt_active &&
                 ((which == 'a') || (which == 'i' &&
                  g.images[i].id == graphic_value(g.command, 'i')))) g.images[i].visible = 0;
      }
    }
    graphic_reply(*s, g.command, ok);
  }
  r.keep_upload = g.active;
  if (!g.active) { g.input = nullptr; g.input_capacity = 0; }
  r.history_rows = s->history_count;
  r.alternate = s->alt_active;
  g.visible_count = 0;
  for (int i = 0; i < IMAGE_SLOTS; ++i)
    if (g.images[i].visible) g.visible[g.visible_count++] = i;
  r.ready = 0;
}
__device__ uint32_t graphic_pixel(const DeviceState &s, int x, int y, uint32_t color, unsigned &opacity) {
  const auto &g = *s.graphics;
  for (int i = 0; i < g.visible_count; ++i) {
    const auto &im = g.images[g.visible[i]];
    if (!im.visible || im.screen != s.alt_active) continue;
    int dx = x - im.px, dy = y - im.py - s.view_offset * s.cell_height;
    if (dx < 0 || dy < 0 || dx >= im.width_crop || dy >= im.height_crop) continue;
    const unsigned char *pixel = im.pixels +
        (size_t(dy + im.sy) * im.width + dx + im.sx) * im.channels;
    unsigned a = im.channels == 4 ? pixel[3] : 255;
    opacity = a + (opacity * (255 - a) + 127) / 255;
    unsigned r = (pixel[0] * a + ((color >> 16) & 255) * (255 - a) + 127) / 255;
    unsigned green = (pixel[1] * a + ((color >> 8) & 255) * (255 - a) + 127) / 255;
    unsigned b = (pixel[2] * a + (color & 255) * (255 - a) + 127) / 255;
    color = (r << 16) | (green << 8) | b;
  }
  return color;
}
