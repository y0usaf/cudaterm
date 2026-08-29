#include "term.h"
#include <cuda_runtime.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Glyph atlas: slots of cw x ch, packed two bytes per row (cw <= 32). A wide
// glyph takes two adjacent slots (left/right halves). Slot index lives in
// Cell.pad. cw/ch come from font metrics (render_font_init).
#define ATLAS_SLOTS 16384
#define SLOT_ROW 2
#define ATLAS_CACHE 0x110000

static Cell* d_cells;
static uint8_t* d_atlas;          // ATLAS_SLOTS * SLOT bytes, slot-major
static void atlas_touch_fwd(int);
static uint32_t atlas_next = 1;   // slot 0 reserved = no glyph
static int dirty_lo = ATLAS_SLOTS, dirty_hi = -1;
static void atlas_touch_fwd(int slot) {
    if (slot < dirty_lo) dirty_lo = slot;
    if (slot + 1 > dirty_hi) dirty_hi = slot + 1;
}
static uint16_t* slot_of;         // cp -> slot, 0 = uncached
static FT_Library ftlib;
static FT_Face ftface;
static int g_cw = 8, g_ch = 16;

void render_cell_size(int* cw, int* ch) { *cw = g_cw; *ch = g_ch; }
void render_resize_grid(Term*);

// Box-drawing arms: bit0=left bit1=right bit2=up bit3=down, bit7=heavy.
__constant__ uint8_t d_arms[0x80];
// Quadrant blocks 0x2596-0x259F: bit0=LL bit1=LR bit2=UL bit3=UR.
__constant__ uint8_t d_quads[16];

static void init_box_tables() {
    uint8_t arms[0x80] = {0};
    auto set = [&](int cp, int a) { arms[cp - 0x2500] = a; };
    auto seth = [&](int cp, int a) { arms[cp - 0x2500] = a | 0x80; };
    set(0x2500, 3);  seth(0x2501, 3);
    set(0x2502, 12); seth(0x2503, 12);
    set(0x250C, 10); seth(0x250F, 10);
    set(0x2510, 6);  seth(0x2513, 6);
    set(0x2514, 9);  seth(0x2517, 9);
    set(0x2518, 5);  seth(0x251B, 5);
    set(0x251C, 14); seth(0x2523, 14);
    set(0x2524, 11); seth(0x252B, 11);
    set(0x252C, 7);  seth(0x2533, 7);
    set(0x2534, 13); seth(0x253B, 13);
    set(0x253C, 15); seth(0x254B, 15);
    set(0x2504, 3);  seth(0x2505, 3);
    set(0x2506, 12); seth(0x2507, 12);
    set(0x2508, 3);  seth(0x2509, 3);
    set(0x250A, 12); seth(0x250B, 12);
    set(0x2574, 1); set(0x2575, 4); set(0x2576, 2); set(0x2577, 8);
    seth(0x2578, 1); seth(0x2579, 4); seth(0x257A, 2); seth(0x257B, 8);
    uint8_t quads[16] = {0};
    quads[0] = 1; quads[1] = 2; quads[2] = 4; quads[3] = 7;
    quads[4] = 5; quads[5] = 13; quads[6] = 14; quads[7] = 8;
    quads[8] = 10; quads[9] = 11;
    cudaMemcpyToSymbol(d_arms, arms, sizeof arms);
    cudaMemcpyToSymbol(d_quads, quads, sizeof quads);
}

// Geometry-only coverage for U+2500-0x259F. (bx,by) normalized to an 8x16
// cell regardless of the real cw/ch, so the logic stays resolution-free.
__device__ bool box_cover(uint32_t cp, int bx, int by) {
    if (cp >= 0x2500 && cp < 0x2580) {
        uint8_t a = d_arms[cp - 0x2500];
        if (!a) return false;
        bool heavy = a & 0x80;
        int cy1 = heavy ? 8 : 7;
        int cx1 = heavy ? 4 : 3;
        if ((a & 1) && by >= 7 && by <= cy1 && bx <= cx1) return true;
        if ((a & 2) && by >= 7 && by <= cy1 && bx >= 3) return true;
        if ((a & 4) && bx >= 3 && bx <= cx1 && by <= cy1) return true;
        if ((a & 8) && bx >= 3 && bx <= cx1 && by >= 7) return true;
        return false;
    }
    if (cp >= 0x2596 && cp <= 0x259F) {
        uint8_t q = d_quads[cp - 0x2596];
        if ((q & 4) && bx < 4 && by < 8) return true;
        if ((q & 8) && bx >= 4 && by < 8) return true;
        if ((q & 1) && bx < 4 && by >= 8) return true;
        if ((q & 2) && bx >= 4 && by >= 8) return true;
        return false;
    }
    switch (cp) {
    case 0x2580: return by < 8;
    case 0x2581: return by >= 14;
    case 0x2582: return by >= 12;
    case 0x2583: return by >= 10;
    case 0x2584: return by >= 8;
    case 0x2585: return by >= 6;
    case 0x2586: return by >= 4;
    case 0x2587: return by >= 2;
    case 0x2588: return true;
    case 0x258C: return bx < 4;
    case 0x2590: return bx >= 4;
    case 0x2591: return (bx % 2 == 0) && (by % 2 == 0);
    case 0x2592: return (bx + by) % 2 == 0;
    case 0x2593: return !((bx % 2) && (by % 2));
    case 0x2594: return by < 2;
    case 0x2595: return by < 6;
    }
    return false;
}

// Rasterize cp into a cw x ch slot pair; returns left slot (0 on failure).
static uint32_t glyph_raster(uint32_t cp) {
    FT_UInt gi = FT_Get_Char_Index(ftface, cp);
    if (!gi) return 0;
    if (FT_Load_Glyph(ftface, gi, FT_LOAD_DEFAULT) || FT_Render_Glyph(ftface->glyph, FT_RENDER_MODE_MONO))
        return 0;
    FT_GlyphSlot g = ftface->glyph;
    FT_Bitmap& bm = g->bitmap;
    if (atlas_next >= ATLAS_SLOTS - 2) return 0;  // atlas full
    uint32_t slot = atlas_next;
    int asc = ftface->size->metrics.ascender >> 6;
    int top = asc - g->bitmap_top;
    uint8_t buf[2][SLOT_ROW * 16] = {{0}, {0}};
    for (int row = 0; row < g_ch; row++) {
        int sy = row - top;
        if (sy < 0 || sy >= (int)bm.rows) continue;
        const uint8_t* src = bm.buffer + (size_t)sy * bm.pitch;
        for (int bit = 0; bit < g_cw; bit++) {
            int sx = bit - (int)g->bitmap_left;
            if (sx < 0 || sx >= (int)bm.width) continue;
            int on = (bm.pixel_mode == FT_PIXEL_MODE_MONO)
                ? (src[sx >> 3] >> (7 - (sx & 7))) & 1
                : (src[sx] > 127);
            if (on) buf[bit >> 3][row] |= 0x80 >> (bit & 7);
        }
    }
    int sb = SLOT_ROW * g_ch;
    cudaMemcpy(d_atlas + (size_t)slot * sb, buf[0], sb, cudaMemcpyHostToDevice);
    cudaMemcpy(d_atlas + (size_t)(slot + 1) * sb, buf[1], sb, cudaMemcpyHostToDevice);
    atlas_touch_fwd(slot); atlas_touch_fwd(slot + 1);
    atlas_next += 2;
    return slot;
}

uint32_t glyph_slot(uint32_t cp, int wide) {
    if (cp >= 0x2500 && cp <= 0x259F) return 0;   // procedural on GPU
    if (cp >= ATLAS_CACHE) return 0;
    uint16_t s = slot_of[cp];
    if (!s) {
        s = glyph_raster(cp);
        slot_of[cp] = s;
    }
    return s;
}

void render_font_init(const char* font_path) {
    if (FT_Init_FreeType(&ftlib) || FT_New_Face(ftlib, font_path, 0, &ftface)) {
        fprintf(stderr, "cudaterm: cannot load font %s\n", font_path);
        exit(1);
    }
    int px = 16;
    if (const char* s = getenv("CUDATERM_SIZE")) px = atoi(s);
    if (px < 4) px = 4;
    if (FT_Set_Pixel_Sizes(ftface, 0, (FT_UInt)px)) {
        fprintf(stderr, "cudaterm: cannot set pixel size %d\n", px);
        exit(1);
    }
    int cw = ftface->size->metrics.max_advance >> 6;
    int ch = ftface->size->metrics.height >> 6;
    if (cw < 1) cw = 8;
    if (ch < 1) ch = 16;
    if (cw > 32) { fprintf(stderr, "cudaterm: cell width %d exceeds 32, clamping\n", cw); cw = 32; }
    g_cw = cw; g_ch = ch;
    fprintf(stderr, "cudaterm: cell %dx%d (font %s @ %dpx)\n", g_cw, g_ch, font_path, px);
}

void render_init(Term* t, const char*) {
    slot_of = (uint16_t*)calloc(ATLAS_CACHE, 2);
    cudaError_t e = cudaMalloc(&d_cells, (size_t)HIST * t->cols * sizeof(Cell));
    if (e != cudaSuccess) { fprintf(stderr, "cudaterm: cudaMalloc: %s\n", cudaGetErrorString(e)); exit(1); }
    cudaMemcpy(d_cells, t->cells, (size_t)HIST * t->cols * sizeof(Cell), cudaMemcpyHostToDevice);
    memset(t->dirty, 0, HIST);
    e = cudaMalloc(&d_atlas, (size_t)ATLAS_SLOTS * SLOT_ROW * g_ch);
    if (e != cudaSuccess) { fprintf(stderr, "cudaterm: cudaMalloc atlas: %s\n", cudaGetErrorString(e)); exit(1); }
    cudaMemset(d_atlas, 0, (size_t)ATLAS_SLOTS * SLOT_ROW * g_ch);
    init_box_tables();
}

// Reallocate the device grid after a terminal resize; full re-upload.
void render_resize_grid(Term* t) {
    cudaFree(d_cells);
    cudaMalloc(&d_cells, (size_t)HIST * t->cols * sizeof(Cell));
    cudaMemcpy(d_cells, t->cells, (size_t)HIST * t->cols * sizeof(Cell), cudaMemcpyHostToDevice);
    memset(t->dirty, 0, HIST);
}

// Upload parser-touched rows.
void render_upload_grid(Term* t) {
    size_t rowbytes = (size_t)t->cols * sizeof(Cell);
    for (int r = 0; r < HIST; r++) {
        if (!t->dirty[r]) continue;
        cudaMemcpy((uint8_t*)d_cells + (size_t)r * rowbytes,
                   (uint8_t*)t->cells + (size_t)r * rowbytes,
                   rowbytes, cudaMemcpyHostToDevice);
        t->dirty[r] = 0;
    }
}

__global__ void render_kernel(cudaSurfaceObject_t surf, const Cell* __restrict__ cells,
                              const uint8_t* __restrict__ atlas, int cols, int hist, int head,
                              int W, int H, int cw, int ch,
                              int cur_row, int cur_col) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= W || y >= H) return;
    int col = x / cw, row = y / ch;
    Cell c = cells[(size_t)((head + row) % hist) * cols + col];
    uint32_t cp = c.cf & 0xffffff;
    uint32_t flags = c.cf >> 24;
    int bx = x - col * cw, by = y - row * ch;

    uint32_t fg = c.fg, bg = c.bg;
    bool cursor = (row == cur_row && col == cur_col);
    if (flags & 16) { uint32_t t = fg; fg = bg; bg = t; }
    if (cursor) { uint32_t t = fg; fg = bg; bg = t; }

    bool lit = false;
    if (c.pad) {
        int sb = 2 * ch;
        const uint8_t* slot = atlas + (size_t)c.pad * sb;
        uint8_t b = slot[(bx >> 3) * ch + by];
        lit = (b >> (7 - (bx & 7))) & 1;
        if (lit && (flags & 4) && bx < cw - 1) {
            uint8_t b2 = slot[((bx + 1) >> 3) * ch + by];
            lit = lit | ((b2 >> (7 - ((bx + 1) & 7))) & 1);
        }
    } else if (cp >= 0x2500 && cp <= 0x259F) {
        lit = box_cover(cp, bx * 8 / cw, by * 16 / ch);
    }
    if (!lit && (flags & 8) && by == ch - 2) lit = true;
    const uint8_t* rgb = lit ? (const uint8_t*)&fg : (const uint8_t*)&bg;
    uchar4 px = {rgb[2], rgb[1], rgb[0], 255};
    surf2Dwrite(px, surf, x * 4, y);
}

void render_draw(cudaSurfaceObject_t surf, Term* t, int W, int H, int cur_row, int cur_col) {
    dim3 block(16, 16);
    dim3 grid((W + 15) / 16, (H + 15) / 16);
    render_kernel<<<grid, block>>>(surf, d_cells, d_atlas, t->cols, HIST, t->head,
                                   W, H, g_cw, g_ch, cur_row, cur_col);
}

// Headless check: render a canned frame and print it as ASCII.
void render_selftest(Term* t) {
    const char* canned = "\x1b[31mred\x1b[0m white \r\nhello world \xe2\x86\x92 \xe2\x89\xa4 \xc3\xa9 \r\n"
        "\x1b[32m\xe2\x94\x8c\xe2\x94\x80\xe2\x94\x90\x1b[0m \xe4\xbd\xa0\xe5\xa5\xbd \r\n"
        "\x1b[1;4mbold underline\x1b[0m \x1b[38;5;208morange\x1b[0m\r\n"
        "\x1b[7minverse\x1b[0m \xe2\x96\x88\xe2\x96\x93\xe2\x96\x91 \xe2\x94\x82\r\n";
    term_feed(t, canned, strlen(canned));
    int W = t->cols * g_cw, H = t->rows * g_ch;
    cudaChannelFormatDesc fmt = cudaCreateChannelDesc<uchar4>();
    cudaArray_t arr;
    cudaMallocArray(&arr, &fmt, W, H, cudaArraySurfaceLoadStore);
    cudaResourceDesc rd = {};
    rd.resType = cudaResourceTypeArray;
    rd.res.array.array = arr;
    cudaSurfaceObject_t surf;
    cudaCreateSurfaceObject(&surf, &rd);
    render_upload_grid(t);
    render_draw(surf, t, W, H, t->row, t->col);
    cudaError_t e = cudaDeviceSynchronize();
    if (e != cudaSuccess) fprintf(stderr, "cuda: %s\n", cudaGetErrorString(e));
    uchar4* host = (uchar4*)malloc((size_t)W * H * 4);
    cudaMemcpy2DFromArray(host, W * 4, arr, 0, 0, W * 4, H, cudaMemcpyDeviceToHost);
    for (int r = 0; r < 5; r++) {
        for (int y = r * g_ch; y < (r + 1) * g_ch; y++) {
            for (int x = 0; x < 20 * g_cw; x += 2) {
                uchar4 p = host[y * W + x];
                putchar((p.x > 40 || p.y > 40 || p.z > 40) ? '#' : '.');
            }
            putchar('\n');
        }
        putchar('\n');
    }
    free(host);
    cudaDestroySurfaceObject(surf);
    cudaFreeArray(arr);
}
