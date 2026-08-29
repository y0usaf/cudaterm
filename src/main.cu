#include "term.h"
#include <GL/glew.h>
#include <GLFW/glfw3.h>
#include <cuda_runtime.h>
#include <cuda_gl_interop.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <linux/limits.h>

void render_init(Term*, const char*);
void render_upload_grid(Term*);
void render_draw(cudaSurfaceObject_t, Term*, int, int, int, int);
void render_selftest(Term*);

static Term term;
static int PTY;
static int WIN_W = 960, WIN_H = 640;
const int COLS = 120, ROWS = 40;

static GLuint tex;
static cudaGraphicsResource* res;

static Term* g_term;

static void dump_state() {
    Term* t = g_term;
    FILE* f = fopen("/tmp/cudaterm-dump.txt", "w");
    if (!f) return;
    for (int r = 0; r < t->rows; r++) {
        for (int c = 0; c < t->cols; c++) {
            Cell* line = &t->cells[(size_t)((t->head + r) % HIST) * t->cols + c];
            fprintf(f, "r%d c%d cp=%06x fl=%02x fg=%06x bg=%06x pad=%u\n",
                    r, c, line->cf & 0xffffff, line->cf >> 24, line->fg, line->bg, line->pad);
        }
    }
    fprintf(f, "cursor r%d c%d head=%d\n", t->row, t->col, t->head);
    fclose(f);
    fprintf(stderr, "cudaterm: state dumped to /tmp/cudaterm-dump.txt\n");
}

static void key(GLFWwindow*, int k, int, int action, int mods) {
    if (action != GLFW_PRESS && action != GLFW_REPEAT) return;
    char buf[8]; int n = 0;
    if (k == GLFW_KEY_F12) { if (action == GLFW_PRESS) dump_state(); return; }
    if (mods & GLFW_MOD_CONTROL) {
        if (k >= 'A' && k <= 'Z') buf[n++] = k - 'A' + 1;
        else if (k == GLFW_KEY_SPACE) buf[n++] = 0;
    } else switch (k) {
        case GLFW_KEY_ENTER: buf[n++] = '\r'; break;
        case GLFW_KEY_TAB: buf[n++] = '\t'; break;
        case GLFW_KEY_BACKSPACE: buf[n++] = 0x7f; break;
        case GLFW_KEY_ESCAPE: buf[n++] = 0x1b; break;
        case GLFW_KEY_UP: n = 3; memcpy(buf, "\x1b[A", 3); break;
        case GLFW_KEY_DOWN: n = 3; memcpy(buf, "\x1b[B", 3); break;
        case GLFW_KEY_RIGHT: n = 3; memcpy(buf, "\x1b[C", 3); break;
        case GLFW_KEY_LEFT: n = 3; memcpy(buf, "\x1b[D", 3); break;
        case GLFW_KEY_HOME: n = 3; memcpy(buf, "\x1b[H", 3); break;
        case GLFW_KEY_END: n = 3; memcpy(buf, "\x1b[F", 3); break;
        case GLFW_KEY_PAGE_UP: n = 4; memcpy(buf, "\x1b[5~", 4); break;
        case GLFW_KEY_PAGE_DOWN: n = 4; memcpy(buf, "\x1b[6~", 4); break;
        case GLFW_KEY_DELETE: n = 4; memcpy(buf, "\x1b[3~", 4); break;
    }
    if (n) term_send(&term, buf, n);
}

static void ch(GLFWwindow*, unsigned int cp) {
    char b[4]; int n = 0;
    if (cp < 0x80) b[n++] = cp;
    else if (cp < 0x800) { b[n++] = 0xc0 | cp >> 6; b[n++] = 0x80 | (cp & 0x3f); }
    else { b[n++] = 0xe0 | cp >> 12; b[n++] = 0x80 | (cp >> 6 & 0x3f); b[n++] = 0x80 | (cp & 0x3f); }
    term_send(&term, b, n);
}

int main(int argc, char** argv) {
    const char* font = getenv("CUDATERM_FONT");
    if (!font) {
        static char p[4096], exe[4096];
        ssize_t l = readlink("/proc/self/exe", exe, sizeof exe - 1);
        if (l < 0) l = 0;
        exe[l] = 0;
        char* slash = strrchr(exe, '/');
        if (slash) *slash = 0;
        snprintf(p, sizeof p, "%s/../share/cudaterm/font.pcf.gz", exe);
        font = p;
    }
    const char* shell = getenv("SHELL");
    if (!shell) shell = "/bin/sh";

    if (argc > 1 && !strcmp(argv[1], "--test")) {
        term_init(&term, COLS, ROWS, nullptr);
        render_init(&term, font);
        render_selftest(&term);
        return 0;
    }
    g_term = &term;
    term_init(&term, COLS, ROWS, shell);
    PTY = term.pty_fd;

    glfwInit();
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
    GLFWwindow* win = glfwCreateWindow(WIN_W, WIN_H, "cudaterm", nullptr, nullptr);
    if (!win) { fprintf(stderr, "cudaterm: window creation failed\n"); return 1; }
    glfwMakeContextCurrent(win);
    glfwSwapInterval(1);
    glfwSetKeyCallback(win, key);
    glfwSetCharCallback(win, ch);
    glewInit();

    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, WIN_W, WIN_H, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    cudaGraphicsGLRegisterImage(&res, tex, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsSurfaceLoadStore);

    render_init(&term, font);
    render_upload_grid(&term);

    while (!glfwWindowShouldClose(win)) {
        char buf[65536];
        for (;;) {
            ssize_t n = read(PTY, buf, sizeof buf);
            if (n > 0) { term_feed(&term, buf, n); continue; }
            if (n == 0 || errno != EAGAIN) goto done;
            break;
        }
        render_upload_grid(&term);

        cudaGraphicsMapResources(1, &res);
        cudaArray_t arr;
        cudaGraphicsSubResourceGetMappedArray(&arr, res, 0, 0);
        cudaResourceDesc rd = {};
        rd.resType = cudaResourceTypeArray;
        rd.res.array.array = arr;
        cudaSurfaceObject_t surf;
        cudaCreateSurfaceObject(&surf, &rd);
        render_draw(surf, &term, WIN_W, WIN_H, term.row, term.col);
        cudaDestroySurfaceObject(surf);
        cudaGraphicsUnmapResources(1, &res);
        cudaDeviceSynchronize();
        static int frames = 0;
        static int probe_frames = -1;
        if (probe_frames < 0) { const char* f = getenv("CUDATERM_PROBE_FRAMES"); probe_frames = f ? atoi(f) : 30; }
        if (getenv("CUDATERM_PROBE") && ++frames == probe_frames) {
            uint32_t* px = (uint32_t*)malloc((size_t)WIN_W * WIN_H * 4);
            cudaMemcpy2DFromArray(px, WIN_W * 4, arr, 0, 0, WIN_W * 4, WIN_H, cudaMemcpyDeviceToHost);

            int lit_rows = 0, lit_total = 0;
            for (int r = 0; r < 3; r++) {
                int lit = 0;
                for (int y = r * 16; y < (r + 1) * 16; y++)
                    for (int x = 0; x < WIN_W; x++) {
                        uint32_t p = px[y * WIN_W + x];
                        if ((p & 0xffffff) != 0) lit++;
                    }
                if (lit > 100) lit_rows++;
                lit_total += lit;
            }
            fprintf(stderr, "probe: lit rows %d/3, lit px %d\n", lit_rows, lit_total);
            // scan whole surface for yellow-ish pixels and where they cluster
            long yellow = 0, magenta = 0, white = 0;
            int yrow_first = -1, yrow_last = -1;
            for (int y = 0; y < WIN_H; y++) {
                int yrow = 0;
                for (int x = 0; x < WIN_W; x++) {
                    uint32_t p = px[y * WIN_W + x];
                    uint32_t r = p & 0xff, g = (p >> 8) & 0xff, b = (p >> 16) & 0xff;
                    if (r > 150 && g > 120 && b < 90) { yellow++; yrow++; }
                    if (r > 150 && b > 150 && g < 90) magenta++;
                    if (r > 180 && g > 180 && b > 180) white++;
                }
                if (yrow > 50) { if (yrow_first < 0) yrow_first = y; yrow_last = y; }
            }
            fprintf(stderr, "probe: yellow=%ld rows %d-%d magenta=%ld white=%ld\n",
                    yellow, yrow_first, yrow_last, magenta, white);
            free(px);
            for (int r = 0; r < term.rows; r++) {
                Cell* line = &term.cells[(size_t)((term.head + r) % HIST) * term.cols];
                char out[256]; int o = 0;
                for (int c = 0; c < term.cols && o < 250; c++) {
                    uint32_t cp = line[c].cf & 0xffffff;
                    if ((line[c].cf >> 24) & 2) continue;
                    out[o++] = cp >= 0x20 && cp < 0x7f ? cp : cp ? '?' : ' ';
                }
                while (o && out[o-1] == ' ') o--;
                out[o] = 0;
                fprintf(stderr, "|%s\n", out);
            }
            goto done;
        }

        glClear(GL_COLOR_BUFFER_BIT);
        glEnable(GL_TEXTURE_2D);
        glBindTexture(GL_TEXTURE_2D, tex);
        glBegin(GL_QUADS);
        glTexCoord2f(0, 1); glVertex2f(-1, -1);
        glTexCoord2f(1, 1); glVertex2f(1, -1);
        glTexCoord2f(1, 0); glVertex2f(1, 1);
        glTexCoord2f(0, 0); glVertex2f(-1, 1);
        glEnd();
        glfwSwapBuffers(win);
        glfwPollEvents();
    }
done:
    term_destroy(&term);
    return 0;
}
