#include "engine.cuh"
#include "runtime.hpp"
#include "input.hpp"
#include "keyboard_protocol.hpp"
#include "config.hpp"
#include "face.hpp"
#include "font.hpp"
#include "motion.hpp"
#include "uri.hpp"
#include "clipboard.hpp"
#include "reload_signal.hpp"

#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GLFW/glfw3.h>
#include "primary_selection.hpp"
#include "ime.hpp"
#include <cuda_gl_interop.h>
#include <cuda_runtime.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <fcntl.h>
#include <mutex>
#include <poll.h>
#include <pty.h>
#include <stdexcept>
#include <string>
#include <sys/ioctl.h>
#include <sys/eventfd.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <future>
#include <thread>
#include <unistd.h>
#include <vector>

namespace {
using ct::Engine;
int CellW = 8, CellH = 16;
int BaseCellW = 8, BaseCellH = 16;
int PaddingX = 0, PaddingY = 0;
constexpr int MaxCols = 512, MaxRows = 256;

struct Options {
  int cols = 120, rows = 40, bitmap_width = 8, bitmap_height = 16;
  std::string dump;
  std::string app_id = "cudaterm", title = "cudaterm", directory;
  ct::Settings settings;
  std::string config_path;
  bool config_required = false, no_config = false;
  std::vector<std::pair<std::string, std::string>> overrides;
  std::vector<char *> command;
};
struct Pty {
  int fd = -1;
  pid_t child = -1;
  ~Pty() {
    if (fd >= 0)
      close(fd);
    if (child <= 0)
      return;
    kill(child, SIGHUP);
    for (int i = 0; i < 20; ++i) {
      pid_t r = waitpid(child, nullptr, WNOHANG);
      if (r == child || (r < 0 && errno == ECHILD))
        return;
      usleep(10000);
    }
    kill(child, SIGKILL);
    while (waitpid(child, nullptr, 0) < 0 && errno == EINTR) {
    }
  }
};
struct Graphics {
  GLFWwindow *window = nullptr;
  GLuint pbo = 0;
  GLuint texture = 0;
  cudaGraphicsResource *resource = nullptr;
  ~Graphics() {
    if (resource)
      cudaGraphicsUnregisterResource(resource);
    if (pbo)
      glDeleteBuffers(1, &pbo);
    if (texture)
      glDeleteTextures(1, &texture);
    if (window)
      glfwDestroyWindow(window);
    glfwTerminate();
  }
};
struct PtyWaiter {
  std::atomic<bool> stop{false};
  std::thread worker;
  std::mutex mutex;
  bool armed = false;
  short events = POLLIN;
  int wake_fd = -1;
  int pid_fd = -1;
  std::atomic<int> failure{0};
  void init(pid_t child) {
    wake_fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    if (wake_fd < 0)
      throw std::runtime_error(std::string("eventfd: ") + std::strerror(errno));
    pid_fd = (int)syscall(SYS_pidfd_open, child, 0);
    if (pid_fd < 0)
      throw std::runtime_error(std::string("pidfd_open: ") + std::strerror(errno));
  }
  void notify() {
    uint64_t one = 1;
    for (;;) {
      ssize_t n = write(wake_fd, &one, sizeof(one));
      if (n == (ssize_t)sizeof(one) || (n < 0 && errno == EAGAIN))
        return;
      if (n < 0 && errno == EINTR)
        continue;
      failure.store(errno ? errno : EIO, std::memory_order_release);
      glfwPostEmptyEvent();
      return;
    }
  }
  void arm(short requested) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      // A zero mask must remove the PTY from poll entirely.  poll(2) still
      // reports HUP/ERR for a descriptor with events == 0, which would turn
      // the post-EOF loop into a busy wakeup while the pidfd remains useful.
      armed = requested != 0;
      events = requested;
    }
    notify();
  }
  ~PtyWaiter() {
    stop.store(true, std::memory_order_release);
    if (wake_fd >= 0) {
      notify();
      if (worker.joinable())
        worker.join();
      close(wake_fd);
    }
    if (pid_fd >= 0)
      close(pid_fd);
  }
};
struct Trace {
  FILE *file = nullptr;
  ~Trace() {
    if (file)
      std::fclose(file);
  }
  void open(const char *path) {
    if (!path || !*path)
      return;
    file = std::fopen(path, "w");
    if (!file)
      throw std::runtime_error(std::string("open CUDATERM_TRACE: ") +
                               std::strerror(errno));
    if (std::fputs("start_ns,end_ns,stage,bytes\n", file) < 0)
      throw std::runtime_error("write CUDATERM_TRACE header failed");
  }
  uint64_t now() const {
    return (uint64_t)std::chrono::duration_cast<std::chrono::nanoseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
  }
  uint64_t begin() const { return file ? now() : 0; }
  void record(uint64_t start, const char *stage, size_t bytes) {
    if (!file)
      return;
    if (std::fprintf(file, "%llu,%llu,%s,%zu\n", (unsigned long long)start,
                     (unsigned long long)now(), stage, bytes) < 0 ||
        std::fflush(file) != 0)
      throw std::runtime_error("write CUDATERM_TRACE failed");
  }
};
int dimension(const char *text, int max) {
  char *end;
  errno = 0;
  long n = std::strtol(text, &end, 10);
  if (errno || *end || end == text || n < 1 || n > max)
    throw std::runtime_error("dimension must be an integer from 1 to " +
                             std::to_string(max));
  return (int)n;
}

void fail(const char *what) {
  throw std::runtime_error(std::string(what) + ": " + std::strerror(errno));
}
void check_cuda(cudaError_t e, const char *what) {
  if (e != cudaSuccess)
    throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(e));
}
int clamp_cols(int n) { return n < 1 ? 1 : n > MaxCols ? MaxCols : n; }
int clamp_rows(int n) { return n < 1 ? 1 : n > MaxRows ? MaxRows : n; }

Options options(int argc, char **argv) {
  Options o;
  const char *config_home = std::getenv("XDG_CONFIG_HOME"), *home = std::getenv("HOME");
  o.config_path = std::string(config_home && *config_home ? config_home :
    (home ? std::string(home) + "/.config" : "/nonexistent")) + "/cudaterm/config";
  for (int i = 1; i < argc && std::strcmp(argv[i], "-e"); ++i) {
    if (!std::strcmp(argv[i], "--config") && i + 1 < argc) {
      o.config_path = argv[++i]; o.config_required = true;
    } else if (!std::strcmp(argv[i], "--no-config")) o.no_config = true;
  }
  if (!o.no_config) o.settings = ct::read_settings(o.config_path, o.config_required);
  auto setting = [&](const std::string &key, const std::string &value) {
    ct::set_setting(o.settings, key, value); o.overrides.emplace_back(key, value);
  };
  for (int i = 1; i < argc; ++i) {
    if (!std::strcmp(argv[i], "--help")) {
      std::puts("usage: cudaterm [--cols N] [--rows N] [--dump PATH] "
                "[--app-id ID] [--title TITLE] [--theme PATH] [--working-directory PATH] "
                "[--font-face PATH] [--cell-width N] [--cell-height N] "
                "[--background-opacity 0..1] [--config PATH | --no-config] "
                "[--font-family FAMILY] [--font-size PIXELS] [--line-height 0.5..3] [--font-file PATH] [--font-fallback FAMILY|file:PATH] "
                "[--padding-x N] [--padding-y N] [--cursor-style block|bar|underline] "
                "[--cursor-blink true|false] [--scroll-multiplier N] -e "
                "command [args...]\n\n"
                "Configuration: $XDG_CONFIG_HOME/cudaterm/config (or ~/.config/cudaterm/config)\n"
                "Themes: midnight, light, classic, or a theme file path.\n"
                "Shortcuts: Ctrl +/-/0 zoom; Ctrl Shift C/V copy/paste; Ctrl Shift F search;\n"
                "Ctrl Shift , reload; Ctrl Shift N new window; Ctrl click open URI;\n"
                "Ctrl right-click copy URI; Ctrl drag rectangular selection.\n"
                "Set cursor-animation=0 to disable cursor motion.");
      std::exit(0);
    } else if (!std::strcmp(argv[i], "--no-config")) continue;
    else if (!std::strcmp(argv[i], "--config") && i + 1 < argc) { ++i; continue; }
    else if ((!std::strcmp(argv[i], "--font-family") || !std::strcmp(argv[i], "--font-file") ||
              !std::strcmp(argv[i], "--font-fallback") || !std::strcmp(argv[i], "--font-size") ||
              !std::strcmp(argv[i], "--line-height") || !std::strcmp(argv[i], "--padding-x") ||
              !std::strcmp(argv[i], "--padding-y") || !std::strcmp(argv[i], "--cursor-style") ||
              !std::strcmp(argv[i], "--cursor-blink") || !std::strcmp(argv[i], "--cursor-animation") || !std::strcmp(argv[i], "--scroll-multiplier")) && i + 1 < argc) {
      std::string key = argv[i] + 2; setting(key, argv[++i]);
    } else if (!std::strcmp(argv[i], "--cols") && i + 1 < argc)
      o.cols = dimension(argv[++i], MaxCols);
    else if (!std::strcmp(argv[i], "--rows") && i + 1 < argc)
      o.rows = dimension(argv[++i], MaxRows);
    else if (!std::strcmp(argv[i], "--cell-width") && i + 1 < argc) {
      o.bitmap_width = CellW = dimension(argv[++i], 64); setting("font-family", "bitmap");
    } else if (!std::strcmp(argv[i], "--cell-height") && i + 1 < argc) {
      o.bitmap_height = CellH = dimension(argv[++i], 128); setting("font-family", "bitmap");
    }
    else if (!std::strcmp(argv[i], "--dump") && i + 1 < argc)
      o.dump = argv[++i];
    else if (!std::strcmp(argv[i], "--theme") && i + 1 < argc)
      setting("theme", argv[++i]);
    else if (!std::strcmp(argv[i], "--font-face") && i + 1 < argc)
      setting("font-face", argv[++i]);
    else if (!std::strcmp(argv[i], "--background-opacity") && i + 1 < argc) {
      setting("background-opacity", argv[++i]);
    }
    else if (!std::strncmp(argv[i], "--app-id=", 9))
      o.app_id = argv[i] + 9;
    else if (!std::strcmp(argv[i], "--app-id") && i + 1 < argc)
      o.app_id = argv[++i];
    else if (!std::strncmp(argv[i], "--title=", 8))
      o.title = argv[i] + 8;
    else if (!std::strcmp(argv[i], "--title") && i + 1 < argc)
      o.title = argv[++i];
    else if (!std::strncmp(argv[i], "--working-directory=", 20))
      o.directory = argv[i] + 20;
    else if (!std::strcmp(argv[i], "--working-directory") && i + 1 < argc)
      o.directory = argv[++i];
    else if (!std::strcmp(argv[i], "-e")) {
      for (++i; i < argc; ++i)
        o.command.push_back(argv[i]);
      if (o.command.empty())
        throw std::runtime_error("-e requires a command");
      break;
    } else
      throw std::runtime_error("unknown option (use --help)");
  }
  if (o.command.empty()) {
    o.command = {const_cast<char *>(std::getenv("SHELL") ?: "/bin/sh")};
  }
  o.cols = clamp_cols(o.cols);
  o.rows = clamp_rows(o.rows);
  o.command.push_back(nullptr);
  return o;
}

void utf8(uint32_t cp, std::vector<unsigned char> &out) {
  if (cp < 0x80)
    out.push_back((unsigned char)cp);
  else if (cp < 0x800) {
    out.push_back(0xc0 | (cp >> 6));
    out.push_back(0x80 | (cp & 63));
  } else if (cp < 0x10000) {
    out.push_back(0xe0 | (cp >> 12));
    out.push_back(0x80 | ((cp >> 6) & 63));
    out.push_back(0x80 | (cp & 63));
  } else {
    out.push_back(0xf0 | (cp >> 18));
    out.push_back(0x80 | ((cp >> 12) & 63));
    out.push_back(0x80 | ((cp >> 6) & 63));
    out.push_back(0x80 | (cp & 63));
  }
}

struct App {
  Engine *engine;
  int pty;
  ct::input::PendingBytes input;
  bool dirty = true;
  bool selecting = false;
  bool suppress_keypad_character = false;
  bool pending_keypad_decimal = false;
  int anchor_row = 0, anchor_col = 0;
  ct::SelectionMode selection_mode = ct::SelectionMode::Cell;
  double last_selection_click = -1;
  int click_row = -1, click_col = -1, selection_clicks = 0;
  double pointer_x = 0, pointer_y = 0;
  double wheel_rows = 0, wheel_ticks = 0;
  double wheel_horizontal = 0;
  unsigned int held_buttons = 0;
  std::exception_ptr error;
  GLFWwindow *window = nullptr;
  bool decoding = false, input_closed = false;
  int pending_width = 0, pending_height = 0;
  Trace *trace = nullptr;
  bool searching = false;
  std::string search_query;
  std::string ime_preedit, ime_pending_preedit, ime_pending_commit;
  bool ime_focused = false;
  std::array<int, 4> ime_rectangle{{-1, -1, -1, -1}};
  ct::SearchMatch search_match{};
  ct::SearchDirection search_direction = ct::SearchDirection::Backward;
  int search_saved_view = 0;
  int zoom_step = 0, applied_zoom_step = 0;
  Options *options = nullptr;
  ct::Settings settings;
  float font_pixels = 0, font_line_height = 0;
  std::string loaded_family, loaded_face;
  bool reload_pending = false, focused = true, cursor_phase = true;
  bool link_click = false;
  int link_row = 0, link_col = 0;
  ct::ClipboardWrites clipboard_writes;
  double cursor_deadline = 0, selection_deadline = 0, copy_flash_deadline = 0;
  double last_input = 0;
  ct::CursorMotion cursor_motion;
  bool cursor_last_alternate = false;

};
void queue(App *a, const unsigned char *p, size_t n) {
  a->input.append(p, n);
}
void flush_input(App *a) {
  while (!a->input.empty() && !a->input_closed) {
    ssize_t n = write(a->pty, a->input.data(), a->input.size());
    if (n > 0) a->input.consume((size_t)n);
    else if (n < 0 && errno == EINTR) continue;
    else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) break;
    else a->input_closed = true;
  }
}
void follow_output(App *a) {
  a->engine->follow_output();
  a->selecting = false; a->link_click = false;
  a->last_input = glfwGetTime();
  a->dirty = true;
}
constexpr size_t SearchMaxCodepoints = 512, SearchMaxBytes = 2048;
bool append_search_utf8(std::string &query, const unsigned char *p, size_t n) {
  size_t points = 0;
  for (size_t i = 0; i < query.size();) {
    if ((query[i] & 0xc0) != 0x80) ++points;
    ++i;
  }
  while (n && query.size() < SearchMaxBytes && points < SearchMaxCodepoints) {
    unsigned char c = *p;
    size_t width = c < 0x80 ? 1 : (c >= 0xc2 && c <= 0xdf) ? 2 :
      (c >= 0xe0 && c <= 0xef) ? 3 : (c >= 0xf0 && c <= 0xf4) ? 4 : 0;
    if (!width || width > n || width > SearchMaxBytes - query.size()) break;
    bool valid = true;
    uint32_t cp = c & (width == 1 ? 0x7f : width == 2 ? 0x1f :
                       width == 3 ? 0x0f : 0x07);
    for (size_t j = 1; j < width; ++j) {
      valid = valid && (p[j] & 0xc0) == 0x80;
      cp = (cp << 6) | (p[j] & 0x3f);
    }
    valid = valid && !(width == 2 && cp < 0x80) &&
      !(width == 3 && cp < 0x800) && !(width == 4 && cp < 0x10000) &&
      cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff) && cp != '\r' && cp != '\n';
    if (!valid) { ++p; --n; continue; }
    query.append((const char *)p, width); p += width; n -= width; ++points;
  }
  return points != 0;
}
void search_prompt(App *a) {
  if (!a->searching) { a->engine->set_search_prompt({}); return; }
  std::string prompt = "Search:";
  if (!a->search_query.empty() && !a->search_match.found)
    prompt += " [no match]";
  prompt += " " + a->search_query + a->ime_preedit;
  a->engine->set_search_prompt(prompt);
  a->dirty = true;
}
void refresh_search(App *a, bool restart) {
  if (!a->searching) return;
  uint64_t trace_start = a->trace ? a->trace->begin() : 0;
  if (a->search_query.empty()) {
    a->engine->clear_search();
    a->search_match = {};
  } else {
    a->search_match = a->engine->search(a->search_query, a->search_direction, restart);
    if (a->search_match.invalidated && !restart)
      a->search_match = a->engine->search(a->search_query, a->search_direction, true);
  }
  if (a->trace)
    a->trace->record(trace_start, a->search_match.found ? "search_found" : "search_missing",
                     a->search_query.size());
  search_prompt(a);
}
void close_search(App *a) {
  if (!a->searching) return;
  a->engine->clear_search();
  a->engine->set_search_prompt({});
  auto now = a->engine->snapshot();
  a->engine->scroll_view(a->search_saved_view - now.view_offset);
  a->searching = false;
  a->search_query.clear();
  a->search_match = {};
  a->engine->set_preedit(a->ime_preedit);
  a->dirty = true;
}
void open_search(App *a) {
  if (a->searching) return;
  uint64_t trace_start = a->trace ? a->trace->begin() : 0;
  a->engine->clear_selection();
  a->search_saved_view = a->engine->snapshot().view_offset;
  a->searching = true;
  a->search_direction = ct::SearchDirection::Backward;
  a->search_query.clear();
  a->search_match = {};
  if (a->trace) a->trace->record(trace_start, "search_open", 0);
  search_prompt(a);
}
void copy_text(GLFWwindow *w, App *a, const std::string &text) {
  if (text.empty()) return;
  glfwSetClipboardString(w, text.c_str());
  ct::primary_selection::set(text.c_str());
  a->engine->set_copy_flash(true);
  a->copy_flash_deadline = glfwGetTime() + 0.2;
  a->dirty = true;
}
void copy_search_match(GLFWwindow *w, App *a) {
  if (!a->searching || !a->search_match.found) return;
  std::string text = a->engine->selected_text();
  uint64_t trace_start = a->trace ? a->trace->begin() : 0;
  if (a->trace) a->trace->record(trace_start, "search_copy", text.size());
  copy_text(w, a, text);
}
void paste_text(App *a, const std::string &text) {
  if (a->searching) {
    append_search_utf8(a->search_query, (const unsigned char *)text.data(), text.size());
    a->search_direction = ct::SearchDirection::Backward;
    refresh_search(a, true);
    return;
  }
  follow_output(a);
  const bool bracketed = a->engine->snapshot().bracketed_paste;
  if (bracketed) queue(a, (const unsigned char *)"\033[200~", 6);
  queue(a, (const unsigned char *)text.data(), text.size());
  if (bracketed) queue(a, (const unsigned char *)"\033[201~", 6);
}
void ime_cursor(App *a, const ct::Snapshot &state, bool enable = false) {
  if (!a->ime_focused) return;
  int window_w, window_h, pixels_w, pixels_h;
  glfwGetWindowSize(a->window, &window_w, &window_h);
  glfwGetFramebufferSize(a->window, &pixels_w, &pixels_h);
  if (pixels_w <= 0 || pixels_h <= 0) return;
  const float sx = float(window_w) / pixels_w, sy = float(window_h) / pixels_h;
  const int col = a->searching ? 0 : std::min(state.col, state.cols - 1);
  const int row = a->searching ? state.rows - 1 : state.row;
  std::array<int, 4> rectangle{{int((PaddingX + col * CellW) * sx),
    int((PaddingY + row * CellH) * sy),
    std::max(1, int((a->searching ? state.cols * CellW : CellW) * sx)),
    std::max(1, int(CellH * sy))}};
  if (enable) ct::ime::enable(a->window, rectangle[0], rectangle[1], rectangle[2], rectangle[3]);
  else if (rectangle != a->ime_rectangle)
    ct::ime::set_cursor_rectangle(a->window, rectangle[0], rectangle[1], rectangle[2], rectangle[3]);
  a->ime_rectangle = rectangle;
}
void ime_event(void *user, int event, const char *text, int32_t, int32_t, uint32_t, uint32_t) {
  auto *a = static_cast<App *>(user);
  try {
    switch (static_cast<ct::ime::Event>(event)) {
    case ct::ime::Event::Enter:
      a->ime_focused = true;
      ime_cursor(a, a->engine->snapshot(), true);
      return;
    case ct::ime::Event::Leave:
      a->ime_focused = false;
      ct::ime::disable(a->window);
      a->ime_pending_preedit.clear(); a->ime_pending_commit.clear();
      a->ime_preedit.clear();
      if (a->searching) search_prompt(a);
      else a->engine->set_preedit({});
      a->dirty = true;
      return;
    case ct::ime::Event::Preedit:
      a->ime_pending_preedit = text ? text : "";
      return;
    case ct::ime::Event::Commit:
      a->ime_pending_commit = text ? text : "";
      return;
    case ct::ime::Event::DeleteSurrounding:
      // A terminal cannot edit the child's input buffer and advertises no
      // surrounding text. The input method owns its uncommitted preedit.
      return;
    case ct::ime::Event::Done:
      a->ime_preedit = std::move(a->ime_pending_preedit);
      a->ime_pending_preedit.clear();
      if (a->searching) {
        append_search_utf8(a->search_query, (const unsigned char *)a->ime_pending_commit.data(),
                           a->ime_pending_commit.size());
        refresh_search(a, true);
      } else {
        if (!a->ime_pending_commit.empty()) {
          follow_output(a);
          queue(a, (const unsigned char *)a->ime_pending_commit.data(), a->ime_pending_commit.size());
        }
        a->engine->set_preedit(a->ime_preedit);
      }
      a->ime_pending_commit.clear();
      a->dirty = true;
      return;
    }
  } catch (...) { a->error = std::current_exception(); }
}
struct ImeSession {
  GLFWwindow *window;
  explicit ImeSession(App &app) : window(app.window) {
    if (ct::ime::supported()) ct::ime::set_callback(window, ime_event, &app);
  }
  ~ImeSession() {
    ct::ime::set_callback(window, nullptr, nullptr);
    ct::ime::disable(window);
  }
};
void drop_files(GLFWwindow *window, int count, const char **paths) {
  auto *a = static_cast<App *>(glfwGetWindowUserPointer(window));
  try { paste_text(a, ct::input::dropped_paths(count, paths)); }
  catch (const std::invalid_argument &error) {
    std::fprintf(stderr, "cudaterm: %s\n", error.what());
  }
  catch (...) { a->error = std::current_exception(); }
}
void resized(GLFWwindow *w, int width, int height);
void launch_detached(const std::vector<std::string> &arguments) {
  std::vector<char *> argv;
  for (const auto &arg : arguments) argv.push_back(const_cast<char *>(arg.c_str()));
  argv.push_back(nullptr);
  pid_t child = fork();
  if (child < 0) { std::perror("cudaterm: launcher"); return; }
  if (!child) {
    if (setsid() < 0) _exit(126);
    pid_t grandchild = fork();
    if (grandchild < 0) _exit(126);
    if (grandchild) _exit(0);
    if (syscall(SYS_close_range, 3u, ~0u, 0u) < 0) _exit(126);
    int null = open("/dev/null", O_RDWR);
    if (null >= 0) { dup2(null, 0); dup2(null, 1); if (null > 2) close(null); }
    execvp(argv[0], argv.data());
    constexpr char error[] = "cudaterm: could not execute launcher\n";
    (void)write(2, error, sizeof(error) - 1); _exit(127);
  }
  int status;
  while (waitpid(child, &status, 0) < 0) {
    if (errno == EINTR) continue;
    std::perror("cudaterm: launcher wait"); return;
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status))
    std::fputs("cudaterm: could not start launcher\n", stderr);
}
void new_window(App *a) {
  std::vector<std::string> command = {"/proc/self/exe"};
  if (a->options->no_config) command.push_back("--no-config");
  else if (a->options->config_required || std::filesystem::exists(a->options->config_path)) {
    command.push_back("--config"); command.push_back(a->options->config_path);
  }
  if (a->options->bitmap_width != 8) { command.push_back("--cell-width"); command.push_back(std::to_string(a->options->bitmap_width)); }
  if (a->options->bitmap_height != 16) { command.push_back("--cell-height"); command.push_back(std::to_string(a->options->bitmap_height)); }
  for (const auto &entry : a->options->overrides) {
    command.push_back("--" + entry.first); command.push_back(entry.second);
  }
  std::error_code error;
  auto directory = std::filesystem::read_symlink("/proc/" + std::to_string(tcgetpgrp(a->pty)) + "/cwd", error);
  if (!error) { command.push_back("--working-directory"); command.push_back(directory.string()); }
  launch_detached(command);
}
void key_impl(GLFWwindow *w, int key, int scancode, int action, int mods) {
  auto *a = static_cast<App *>(glfwGetWindowUserPointer(w));
  a->suppress_keypad_character = false;
  a->pending_keypad_decimal = false;
  if (action != GLFW_PRESS && action != GLFW_REPEAT)
    return;
  std::vector<unsigned char> b;
  a->cursor_deadline = glfwGetTime() + 0.6;
  a->cursor_phase = true;
  a->engine->set_cursor_phase(true, a->focused);
  a->dirty = true;
  bool ctrl = mods & GLFW_MOD_CONTROL, alt = mods & GLFW_MOD_ALT;
  if (ctrl && (mods & GLFW_MOD_SHIFT) && key == GLFW_KEY_N && !alt) {
    new_window(a); return;
  }
  if (ctrl && (mods & GLFW_MOD_SHIFT) && key == GLFW_KEY_COMMA && !alt) {
    a->reload_pending = true; return;
  }
  if (ctrl && !alt &&
      (key == GLFW_KEY_EQUAL || key == GLFW_KEY_MINUS || key == GLFW_KEY_0)) {
    a->zoom_step = key == GLFW_KEY_0 ? 0 :
      std::clamp(a->zoom_step + (key == GLFW_KEY_EQUAL ? 1 : -1), -5, 10);
    int width, height;
    glfwGetFramebufferSize(w, &width, &height);
    resized(w, width, height);
    return;
  }
  const bool paste = !alt && (mods & GLFW_MOD_SHIFT) &&
    ((ctrl && key == GLFW_KEY_V) || (!ctrl && key == GLFW_KEY_INSERT));
  if (ctrl && (mods & GLFW_MOD_SHIFT) && key == GLFW_KEY_F && !alt) {
    open_search(a); return;
  }
  if (a->searching) {
    if (key == GLFW_KEY_ESCAPE) { close_search(a); return; }
    if (ctrl && key == GLFW_KEY_U) {
      a->search_query.clear();
      a->search_direction = ct::SearchDirection::Backward;
      refresh_search(a, true); return;
    }
    if (ctrl && key == GLFW_KEY_W) {
      while (!a->search_query.empty() && a->search_query.back() == ' ') a->search_query.pop_back();
      while (!a->search_query.empty() && a->search_query.back() != ' ') a->search_query.pop_back();
      refresh_search(a, true); return;
    }
    if (key == GLFW_KEY_BACKSPACE) {
      while (!a->search_query.empty() &&
             ((unsigned char)a->search_query.back() & 0xc0) == 0x80)
        a->search_query.pop_back();
      if (!a->search_query.empty()) a->search_query.pop_back();
      a->search_direction = ct::SearchDirection::Backward;
      refresh_search(a, true); return;
    }
    if (key == GLFW_KEY_ENTER || key == GLFW_KEY_KP_ENTER ||
        (ctrl && (key == GLFW_KEY_N || key == GLFW_KEY_P))) {
      a->search_direction = ((ctrl && key == GLFW_KEY_P) || (mods & GLFW_MOD_SHIFT)) ? ct::SearchDirection::Backward :
                                                        ct::SearchDirection::Forward;
      refresh_search(a, false); return;
    }
    if (ctrl && (mods & GLFW_MOD_SHIFT) && key == GLFW_KEY_C) {
      copy_search_match(w, a); return;
    }
    if (paste) {
      const char *s = glfwGetClipboardString(w);
      if (s) paste_text(a, s);
      return;
    }
    return;
  }
  if ((mods & GLFW_MOD_SHIFT) && !(mods & (GLFW_MOD_CONTROL | GLFW_MOD_ALT)) &&
      (key == GLFW_KEY_PAGE_UP || key == GLFW_KEY_PAGE_DOWN ||
       key == GLFW_KEY_HOME || key == GLFW_KEY_END) &&
      !a->engine->snapshot().alternate_screen) {
    auto state = a->engine->snapshot();
    int page = std::max(1, state.rows - 1);
    int rows = key == GLFW_KEY_HOME ? state.history_rows :
               key == GLFW_KEY_END ? -state.view_offset :
               key == GLFW_KEY_PAGE_UP ? page : -page;
    a->engine->scroll_view(rows);
    a->selecting = false;
    a->dirty = true;
    return;
  }
  if (ctrl && key == GLFW_KEY_C && (mods & GLFW_MOD_SHIFT)) {
    std::string text = a->engine->selected_text();
    copy_text(w, a, text);
    return;
  }
  if (paste) {
    const char *s = glfwGetClipboardString(w);
    if (s) paste_text(a, s);
    return;
  }
  const auto keyboard_state = a->engine->snapshot();
  if (keyboard_state.keyboard_flags) {
    using K = ct::keyboard::Key;
    ct::keyboard::KeyEvent event;
    event.modifiers = (mods & GLFW_MOD_SHIFT ? ct::keyboard::Shift : 0) |
      (alt ? ct::keyboard::Alt : 0) | (ctrl ? ct::keyboard::Control : 0) |
      (mods & GLFW_MOD_SUPER ? ct::keyboard::Super : 0) |
      (mods & GLFW_MOD_CAPS_LOCK ? ct::keyboard::CapsLock : 0) |
      (mods & GLFW_MOD_NUM_LOCK ? ct::keyboard::NumLock : 0);
    event.action = action == GLFW_REPEAT ? ct::keyboard::Action::Repeat : ct::keyboard::Action::Press;
    if (key >= GLFW_KEY_ESCAPE && key <= GLFW_KEY_END) {
      static constexpr K functions[] = {K::Escape, K::Enter, K::Tab, K::Backspace,
        K::Insert, K::Delete, K::Right, K::Left, K::Down, K::Up,
        K::PageUp, K::PageDown, K::Home, K::End};
      event.key = functions[key - GLFW_KEY_ESCAPE];
    } else if (key >= GLFW_KEY_F1 && key <= GLFW_KEY_F12) {
      event.key = K(int(K::F1) + key - GLFW_KEY_F1);
    } else if (key >= GLFW_KEY_F13 && key <= GLFW_KEY_F25) {
      event.key = K::Functional;
      event.codepoint = 57376 + key - GLFW_KEY_F13;
    } else if (key >= GLFW_KEY_CAPS_LOCK && key <= GLFW_KEY_PAUSE) {
      static constexpr uint32_t codes[] = {57358, 57359, 57360, 57361, 57362};
      event.key = K::Functional;
      event.codepoint = codes[key - GLFW_KEY_CAPS_LOCK];
    } else if (key == GLFW_KEY_MENU) {
      event.key = K::Functional; event.codepoint = 57363;
    } else if (key >= GLFW_KEY_KP_0 && key <= GLFW_KEY_KP_EQUAL) {
      bool number = key <= GLFW_KEY_KP_9 || key == GLFW_KEY_KP_DECIMAL;
      bool text_key = key != GLFW_KEY_KP_ENTER && (!number || (mods & GLFW_MOD_NUM_LOCK));
      if (text_key && !(mods & (GLFW_MOD_CONTROL | GLFW_MOD_ALT | GLFW_MOD_SUPER)))
        return; // GLFW supplies the layout-resolved text, including decimal separators.
      event.key = K::Functional;
      static constexpr uint32_t keypad_codes[] = {57399, 57400, 57401, 57402, 57403,
        57404, 57405, 57406, 57407, 57408, 57409, 57410, 57411, 57412, 57413, 57414, 57415};
      event.codepoint = keypad_codes[key - GLFW_KEY_KP_0];
      if (number && !(mods & GLFW_MOD_NUM_LOCK)) {
        static constexpr uint32_t navigation[] = {57425, 57424, 57420, 57422, 57417,
          57427, 57418, 57423, 57419, 57421, 57426};
        event.codepoint = navigation[key - GLFW_KEY_KP_0];
        if (key == GLFW_KEY_KP_5) event.key = K::Begin;
      }
    } else if (mods & (GLFW_MOD_CONTROL | GLFW_MOD_ALT | GLFW_MOD_SUPER)) {
      const char *name = glfwGetKeyName(key, scancode);
      if (name) event.codepoint = ct::keyboard::first_codepoint(name);
      if (!event.codepoint && key == GLFW_KEY_SPACE) event.codepoint = ' ';
      if (event.codepoint) {
        event.key = K::Character;
        event.unshifted_codepoint = event.codepoint;
      }
    }
    const auto bytes = ct::keyboard::encode(event, keyboard_state.keyboard_flags);
    if (!bytes.empty()) {
      a->suppress_keypad_character = true;
      follow_output(a);
      queue(a, (const unsigned char *)bytes.data(), bytes.size());
      return;
    }
  }
  if (key >= GLFW_KEY_KP_0 && key <= GLFW_KEY_KP_EQUAL) {
    using ct::input::Keypad;
    Keypad keypad = key <= GLFW_KEY_KP_9 ? Keypad(key - GLFW_KEY_KP_0) :
      key == GLFW_KEY_KP_DECIMAL ? Keypad::Decimal :
      key == GLFW_KEY_KP_ENTER ? Keypad::Enter :
      key == GLFW_KEY_KP_ADD ? Keypad::Add :
      key == GLFW_KEY_KP_SUBTRACT ? Keypad::Subtract :
      key == GLFW_KEY_KP_MULTIPLY ? Keypad::Multiply :
      key == GLFW_KEY_KP_DIVIDE ? Keypad::Divide : Keypad::Equal;
    // Wait for the layout-resolved symbol before encoding Decimal/Separator.
    if (keypad == Keypad::Decimal && (mods & GLFW_MOD_NUM_LOCK)) {
      a->pending_keypad_decimal = true;
      return;
    }
    auto state = a->engine->snapshot();
    auto bytes = ct::input::keypad_sequence(keypad,
      (mods & GLFW_MOD_SHIFT ? ct::input::Shift : 0) |
      (alt ? ct::input::Alt : 0) | (ctrl ? ct::input::Control : 0),
      mods & GLFW_MOD_NUM_LOCK,
      state.application_keypad && !state.numlock_override,
      state.application_cursor);
    // GLFW can also deliver a text callback for this same keypad press.
    a->suppress_keypad_character = true;
    follow_output(a);
    queue(a, (const unsigned char *)bytes.data(), bytes.size());
    return;
  }
  const char *seq = nullptr;
  ct::input::Key input_key{};
  bool has_input_key = false;
  switch (key) {
  case GLFW_KEY_ENTER:
    seq = "\r";
    break;
  case GLFW_KEY_BACKSPACE:
    seq = "\177";
    break;
  case GLFW_KEY_TAB:
    seq = (mods & GLFW_MOD_SHIFT) ? "\033[Z" : "\t";
    break;
  case GLFW_KEY_ESCAPE:
    seq = "\033";
    break;
  case GLFW_KEY_UP:
    input_key = ct::input::Key::Up;
    has_input_key = true;
    break;
  case GLFW_KEY_DOWN:
    input_key = ct::input::Key::Down;
    has_input_key = true;
    break;
  case GLFW_KEY_RIGHT:
    input_key = ct::input::Key::Right;
    has_input_key = true;
    break;
  case GLFW_KEY_LEFT:
    input_key = ct::input::Key::Left;
    has_input_key = true;
    break;
  case GLFW_KEY_HOME:
    input_key = ct::input::Key::Home;
    has_input_key = true;
    break;
  case GLFW_KEY_END:
    input_key = ct::input::Key::End;
    has_input_key = true;
    break;
  case GLFW_KEY_INSERT:
    input_key = ct::input::Key::Insert;
    has_input_key = true;
    break;
  case GLFW_KEY_DELETE:
    input_key = ct::input::Key::Delete;
    has_input_key = true;
    break;
  case GLFW_KEY_PAGE_UP:
    input_key = ct::input::Key::PageUp;
    has_input_key = true;
    break;
  case GLFW_KEY_PAGE_DOWN:
    input_key = ct::input::Key::PageDown;
    has_input_key = true;
    break;
  case GLFW_KEY_F1:
    input_key = ct::input::Key::F1;
    has_input_key = true;
    break;
  case GLFW_KEY_F2:
    input_key = ct::input::Key::F2;
    has_input_key = true;
    break;
  case GLFW_KEY_F3:
    input_key = ct::input::Key::F3;
    has_input_key = true;
    break;
  case GLFW_KEY_F4:
    input_key = ct::input::Key::F4;
    has_input_key = true;
    break;
  case GLFW_KEY_F5:
    input_key = ct::input::Key::F5;
    has_input_key = true;
    break;
  case GLFW_KEY_F6:
    input_key = ct::input::Key::F6;
    has_input_key = true;
    break;
  case GLFW_KEY_F7:
    input_key = ct::input::Key::F7;
    has_input_key = true;
    break;
  case GLFW_KEY_F8:
    input_key = ct::input::Key::F8;
    has_input_key = true;
    break;
  case GLFW_KEY_F9:
    input_key = ct::input::Key::F9;
    has_input_key = true;
    break;
  case GLFW_KEY_F10:
    input_key = ct::input::Key::F10;
    has_input_key = true;
    break;
  case GLFW_KEY_F11:
    input_key = ct::input::Key::F11;
    has_input_key = true;
    break;
  case GLFW_KEY_F12:
    input_key = ct::input::Key::F12;
    has_input_key = true;
    break;
  default:
    break;
  }
  std::string input_sequence;
  if (has_input_key)
    input_sequence = ct::input::sequence(
        input_key,
        (mods & GLFW_MOD_SHIFT ? ct::input::Shift : 0) |
            (alt ? ct::input::Alt : 0) | (ctrl ? ct::input::Control : 0),
        a->engine->snapshot().application_cursor);
  if (ctrl && key >= GLFW_KEY_A && key <= GLFW_KEY_Z)
    b.push_back((unsigned char)(key - GLFW_KEY_A + 1));
  else if (ctrl) {
    // The C0 controls generated by the ASCII punctuation keys.
    switch (key) {
    case GLFW_KEY_SPACE: // Ctrl-Space
    case GLFW_KEY_2: // Ctrl-@
      b.push_back(0);
      break;
    case GLFW_KEY_LEFT_BRACKET:
      b.push_back(0x1b);
      break;
    case GLFW_KEY_BACKSLASH:
      b.push_back(0x1c);
      break;
    case GLFW_KEY_RIGHT_BRACKET:
      b.push_back(0x1d);
      break;
    case GLFW_KEY_6: // Ctrl-^
      b.push_back(0x1e);
      break;
    case GLFW_KEY_MINUS: // Ctrl-_
      b.push_back(0x1f);
      break;
    case GLFW_KEY_SLASH: // Ctrl-?
      b.push_back(0x7f);
      break;
    default:
      break;
    }
  }
  if (b.empty() && has_input_key)
    b.assign(input_sequence.begin(), input_sequence.end());
  if (b.empty() && seq)
    b.assign((const unsigned char *)seq,
             (const unsigned char *)seq + std::strlen(seq));
  if (b.empty())
    return;
  follow_output(a);
  if (alt && !has_input_key)
    b.insert(b.begin(), 27);
  queue(a, b.data(), b.size());
}
void key(GLFWwindow *w, int code, int scancode, int action, int mods) {
  try {
    key_impl(w, code, scancode, action, mods);
  } catch (...) {
    static_cast<App *>(glfwGetWindowUserPointer(w))->error =
        std::current_exception();
  }
}
void character(GLFWwindow *w, unsigned int cp) {
  auto *a = static_cast<App *>(glfwGetWindowUserPointer(w));
  try {
    if (a->suppress_keypad_character) {
      a->suppress_keypad_character = false;
      return;
    }
    if (a->searching) {
      std::vector<unsigned char> encoded;
      utf8(cp, encoded);
      append_search_utf8(a->search_query, encoded.data(), encoded.size());
      a->search_direction = ct::SearchDirection::Backward;
      refresh_search(a, true);
      return;
    }
    std::vector<unsigned char> b;
    if (glfwGetKey(w, GLFW_KEY_LEFT_ALT) == GLFW_PRESS ||
        glfwGetKey(w, GLFW_KEY_RIGHT_ALT) == GLFW_PRESS)
      b.push_back(27);
    utf8(cp, b);
    follow_output(a);
    queue(a, b.data(), b.size());
  } catch (...) {
    a->error = std::current_exception();
  }
}
void character_modifiers(GLFWwindow *w, unsigned int cp, int mods) {
  auto *a = static_cast<App *>(glfwGetWindowUserPointer(w));
  if (!a->pending_keypad_decimal) {
    // GLFW excludes Alt text from its plain character callback. Deliver the
    // layout/compose-resolved character here unless the key path encoded it.
    if ((mods & GLFW_MOD_ALT) && !(mods & GLFW_MOD_CONTROL) &&
        !a->suppress_keypad_character) {
      character(w, cp);
      a->suppress_keypad_character = true;
    }
    return;
  }
  a->pending_keypad_decimal = false;
  // GLFW delivers this callback before the plain character callback, including
  // Alt/Control input and repeats. Consume that later callback exactly once.
  if (cp != '.' && cp != ',') {
    character(w, cp);
    a->suppress_keypad_character = true;
    return;
  }
  a->suppress_keypad_character = true;
  try {
    auto state = a->engine->snapshot();
    auto bytes = ct::input::keypad_sequence(ct::input::Keypad::Decimal,
      (mods & GLFW_MOD_SHIFT ? ct::input::Shift : 0) |
      (mods & GLFW_MOD_ALT ? ct::input::Alt : 0) |
      (mods & GLFW_MOD_CONTROL ? ct::input::Control : 0), true,
      state.application_keypad && !state.numlock_override,
      state.application_cursor, cp == ',');
    follow_output(a);
    queue(a, (const unsigned char *)bytes.data(), bytes.size());
  } catch (...) { a->error = std::current_exception(); }
}
void selection_position(GLFWwindow *w, double x, double y, int &row, int &col) {
  int width, height, pixels_w, pixels_h;
  glfwGetWindowSize(w, &width, &height);
  glfwGetFramebufferSize(w, &pixels_w, &pixels_h);
  // Cursor positions use window coordinates; glyphs use framebuffer pixels.
  x = std::max(0.0, std::min(x, static_cast<double>(width)));
  y = std::max(0.0, std::min(y, static_cast<double>(height)));
  col = width > 0 ? std::max(0, static_cast<int>(x * pixels_w / width) - PaddingX) / CellW : 0;
  row = height > 0 ? std::max(0, static_cast<int>(y * pixels_h / height) - PaddingY) / CellH : 0;
}
int mouse_modifiers(GLFWwindow *w) {
  int mods = 0;
  if (glfwGetKey(w, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS ||
      glfwGetKey(w, GLFW_KEY_RIGHT_SHIFT) == GLFW_PRESS)
    mods |= 4;
  if (glfwGetKey(w, GLFW_KEY_LEFT_ALT) == GLFW_PRESS ||
      glfwGetKey(w, GLFW_KEY_RIGHT_ALT) == GLFW_PRESS)
    mods |= 8;
  if (glfwGetKey(w, GLFW_KEY_LEFT_CONTROL) == GLFW_PRESS ||
      glfwGetKey(w, GLFW_KEY_RIGHT_CONTROL) == GLFW_PRESS)
    mods |= 16;
  return mods;
}
int mouse_button_code(int button) {
  switch (button) {
  case GLFW_MOUSE_BUTTON_LEFT:
    return 0;
  case GLFW_MOUSE_BUTTON_MIDDLE:
    return 1;
  case GLFW_MOUSE_BUTTON_RIGHT:
    return 2;
  default:
    return 3;
  }
}
bool report_mouse(App *a, GLFWwindow *w, int button, int row, int col,
                  int modifiers, int action) {
  int width, height, pixels_w, pixels_h;
  glfwGetWindowSize(w, &width, &height);
  glfwGetFramebufferSize(w, &pixels_w, &pixels_h);
  int x = width > 0 ? int(a->pointer_x * pixels_w / width) : 0;
  int y = height > 0 ? int(a->pointer_y * pixels_h / height) : 0;
  bool reported = a->engine->mouse(button, row, col, modifiers, action,
                                   std::max(0, x - PaddingX), std::max(0, y - PaddingY));
  std::string replies = a->engine->take_replies();
  if (!replies.empty())
    queue(a, (const unsigned char *)replies.data(), replies.size());
  return reported;
}
void pointer_moved(GLFWwindow *w, double x, double y) {
  auto *a = static_cast<App *>(glfwGetWindowUserPointer(w));
  a->pointer_x = x;
  a->pointer_y = y;
  try {
    int row, col;
    selection_position(w, x, y, row, col);
    if (a->link_click && (row != a->link_row || col != a->link_col)) a->link_click = false;
    if (a->selecting) {
      auto state = a->engine->snapshot();
      a->engine->select(a->anchor_row + state.view_offset, a->anchor_col,
                        std::min(row, state.rows - 1), std::min(col, state.cols - 1),
                        a->selection_mode, true);
      a->dirty = true;
      return;
    }
    if (mouse_modifiers(w) & 4)
      return;
    int button = 3;
    if (a->held_buttons & (1u << GLFW_MOUSE_BUTTON_LEFT))
      button = 0;
    else if (a->held_buttons & (1u << GLFW_MOUSE_BUTTON_MIDDLE))
      button = 1;
    else if (a->held_buttons & (1u << GLFW_MOUSE_BUTTON_RIGHT))
      button = 2;
    report_mouse(a, w, button, row, col, mouse_modifiers(w), 2);
  } catch (...) {
    a->error = std::current_exception();
  }
}
void begin_selection(App *a, int row, int col, int mods) {
  auto state = a->engine->snapshot();
  row = std::clamp(row, 0, state.rows - 1); col = std::clamp(col, 0, state.cols - 1);
  double now = glfwGetTime();
  if (now - a->last_selection_click <= 0.4 && row == a->click_row &&
      col == a->click_col)
    a->selection_clicks = a->selection_clicks % 3 + 1;
  else
    a->selection_clicks = 1;
  a->last_selection_click = now;
  a->click_row = row;
  a->anchor_row = row - state.view_offset;
  a->click_col = a->anchor_col = col;
  a->selection_mode = a->selection_clicks == 2 ? ct::SelectionMode::Word :
                      a->selection_clicks == 3 ? ct::SelectionMode::Line :
                                                ct::SelectionMode::Cell;
  if (mods & GLFW_MOD_CONTROL) a->selection_mode = ct::SelectionMode::Rectangle;
  a->selection_deadline = glfwGetTime() + 0.04;
  a->selecting = true;
}
void mouse_button(GLFWwindow *w, int button, int action, int mods) {
  if (button != GLFW_MOUSE_BUTTON_LEFT && button != GLFW_MOUSE_BUTTON_MIDDLE &&
      button != GLFW_MOUSE_BUTTON_RIGHT)
    return;
  auto *a = static_cast<App *>(glfwGetWindowUserPointer(w));
  a->last_input = glfwGetTime();
  try {
    // Use event-ordered coordinates: querying the pointer here can see a
    // later move already queued behind this button event.
    double x = a->pointer_x, y = a->pointer_y;
    int row, col;
    selection_position(w, x, y, row, col);
    auto state = a->engine->snapshot();
    bool link_modifier = (mods & GLFW_MOD_CONTROL) && !(mods & GLFW_MOD_ALT) &&
                         (!state.mouse_tracking || (mods & GLFW_MOD_SHIFT));
    if (action == GLFW_RELEASE && button == GLFW_MOUSE_BUTTON_LEFT && a->link_click) {
      a->link_click = false; a->selecting = false;
      a->engine->select(row, col, row, col, ct::SelectionMode::Link);
      auto target = a->engine->hyperlink_at(row, col);
      auto uri = target.empty() ? ct::detected_uri(a->engine->selected_text()) : ct::explicit_uri(target);
      a->dirty = true;
      if (!uri.empty()) launch_detached({CUDATERM_XDG_OPEN, uri});
      return;
    }
    if (link_modifier && action == GLFW_PRESS) {
      if (button == GLFW_MOUSE_BUTTON_RIGHT) {
        a->engine->select(row, col, row, col, ct::SelectionMode::Link);
        auto target = a->engine->hyperlink_at(row, col);
        auto uri = target.empty() ? ct::detected_uri(a->engine->selected_text()) : ct::explicit_uri(target);
        copy_text(w, a, uri);
        a->dirty = true; return;
      }
      if (button == GLFW_MOUSE_BUTTON_LEFT) {
        a->link_click = true; a->link_row = row; a->link_col = col;
      }
    }
    bool local = a->selecting ||
                 ((mods & GLFW_MOD_SHIFT) && !(a->held_buttons & (1u << button)));
    if (button == GLFW_MOUSE_BUTTON_MIDDLE && (!state.mouse_tracking || local || a->searching)) {
      if (action == GLFW_PRESS) {
        if (const char *text = ct::primary_selection::get()) paste_text(a, text);
      }
      return;
    }
    if (local && button == GLFW_MOUSE_BUTTON_LEFT) {
      if (action == GLFW_PRESS) {
        begin_selection(a, row, col, mods);
      }
      pointer_moved(w, x, y);
      if (action == GLFW_RELEASE) {
        a->selecting = false;
        copy_text(w, a, a->engine->selected_text());
      }
      return;
    }
    if (local)
      return;
    int mapped = mouse_button_code(button);
    int mouse_action = action == GLFW_PRESS ? 0 : 1;
    bool reported = report_mouse(
        a, w, mapped, row, col,
        ((mods & GLFW_MOD_SHIFT) ? 4 : 0) |
            ((mods & GLFW_MOD_ALT) ? 8 : 0) |
            ((mods & GLFW_MOD_CONTROL) ? 16 : 0),
        mouse_action);
    if (!reported && button == GLFW_MOUSE_BUTTON_LEFT) {
      if (action == GLFW_PRESS) {
        begin_selection(a, row, col, mods);
      }
      pointer_moved(w, x, y);
      if (action == GLFW_RELEASE) {
        a->selecting = false;
        copy_text(w, a, a->engine->selected_text());
      }
      return;
    }
    if (action == GLFW_PRESS)
      a->held_buttons |= 1u << button;
    if (action == GLFW_RELEASE)
      a->held_buttons &= ~(1u << button);
  } catch (...) {
    a->error = std::current_exception();
  }
}
void wheel(GLFWwindow *w, double x, double y) {
  auto *a = static_cast<App *>(glfwGetWindowUserPointer(w));
  a->last_input = glfwGetTime();
  try {
    int mods = mouse_modifiers(w);
    int row, col;
    selection_position(w, a->pointer_x, a->pointer_y, row, col);
    auto state = a->engine->snapshot();
    if (!(mods & 4) && !a->selecting && state.mouse_tracking && !state.view_offset) {
      a->wheel_ticks = std::max(-4096.0, std::min(4096.0, a->wheel_ticks + y));
      int ticks = static_cast<int>(a->wheel_ticks);
      a->wheel_ticks -= ticks;
      for (int i = 0; i < std::abs(ticks); ++i)
        report_mouse(a, w, ticks > 0 ? 64 : 65, row, col, mods, 0);
      a->wheel_horizontal = std::clamp(a->wheel_horizontal + x, -4096.0, 4096.0);
      int horizontal = static_cast<int>(a->wheel_horizontal);
      a->wheel_horizontal -= horizontal;
      for (int i = 0; i < std::abs(horizontal); ++i)
        report_mouse(a, w, horizontal > 0 ? 67 : 66, row, col, mods, 0);
      return;
    }
    a->wheel_ticks = 0;
    a->wheel_horizontal = 0;
    a->wheel_rows = std::max(-4096.0, std::min(4096.0, a->wheel_rows + y * a->settings.scroll_multiplier));
    int rows = static_cast<int>(a->wheel_rows);
    if (rows) {
      a->wheel_rows -= rows;
      if (state.alternate_screen && !(mods & 4)) {
        auto arrow = ct::input::sequence(rows > 0 ? ct::input::Key::Up : ct::input::Key::Down,
                                         0, state.application_cursor);
        for (int i = 0; i < std::abs(rows); ++i)
          queue(a, (const unsigned char *)arrow.data(), arrow.size());
      } else a->engine->scroll_view(rows);
      a->selecting = false;
      a->dirty = true;
    }
  } catch (...) {
    a->error = std::current_exception();
  }
}
void focus_changed(GLFWwindow *w, int focused) {
  auto *a = static_cast<App *>(glfwGetWindowUserPointer(w));
  try {
    a->focused = focused != 0;
    a->engine->set_cursor_phase(true, a->focused);
    a->cursor_phase = true; a->cursor_deadline = glfwGetTime() + 0.6; a->dirty = true;
    a->engine->focus(focused != 0);
    std::string reports = a->engine->take_replies();
    if (!reports.empty())
      queue(a, (const unsigned char *)reports.data(), reports.size());
  } catch (...) { a->error = std::current_exception(); }
  if (!focused) {
    a->pending_keypad_decimal = a->suppress_keypad_character = false;
    a->selecting = false; a->link_click = false;
    a->held_buttons = 0;
  }
}
void resized(GLFWwindow *w, int width, int height) {
  auto *a = static_cast<App *>(glfwGetWindowUserPointer(w));
  if (width <= 0 || height <= 0)
    return;
  if (a->decoding) {
    a->pending_width = width; a->pending_height = height;
    return;
  }
  try {
    a->selecting = false;
    a->engine->clear_selection(); a->link_click = false;
    a->cursor_motion.initialized = false;
    float scale_x, scale_y;
    glfwGetWindowContentScale(w, &scale_x, &scale_y);
    float zoom = 1.0f + a->zoom_step * 0.1f;
    int cw, ch;
    if (a->settings.font_family != "bitmap") {
      float pixels = std::min(128.0f / a->settings.line_height,
                             a->settings.font_size * scale_y * zoom);
      if (pixels != a->font_pixels || a->loaded_family != a->settings.font_family ||
          a->font_line_height != a->settings.line_height) {
        auto font = ct::rasterize_font(a->settings.font_family, pixels, a->settings.line_height, a->settings.font_fallback);
        a->engine->load_faces(font.faces);
        BaseCellW = font.width; BaseCellH = font.height;
        a->font_pixels = pixels; a->font_line_height = a->settings.line_height;
        a->loaded_family = a->settings.font_family; a->loaded_face.clear();
      }
      cw = std::clamp(int(BaseCellW * scale_x / scale_y + 0.5f), 1, 64);
      ch = BaseCellH;
    } else {
      if (a->loaded_face != a->settings.font_face || !a->loaded_family.empty()) {
        if (a->settings.font_face.empty()) {
          a->engine->load_faces({}); BaseCellW = a->options->bitmap_width; BaseCellH = a->options->bitmap_height;
        } else {
          auto face = ct::face_header(a->settings.font_face);
          a->engine->load_face(a->settings.font_face);
          BaseCellW = face.width; BaseCellH = face.height;
        }
        a->loaded_family.clear(); a->loaded_face = a->settings.font_face; a->font_pixels = 0;
      }
      cw = std::clamp(int(BaseCellW * scale_x * zoom + 0.5f), 1, 64);
      ch = std::clamp(int(BaseCellH * scale_y * zoom + 0.5f), 1, 128);
    }
    PaddingX = std::min(400, int(a->settings.padding_x * scale_x + 0.5f));
    PaddingY = std::min(400, int(a->settings.padding_y * scale_y + 0.5f));
    a->engine->set_presentation(PaddingX, PaddingY,
      a->settings.cursor_style - (a->settings.cursor_blink ? 1 : 0));
    if (cw != CellW || ch != CellH) {
      CellW = cw; CellH = ch;
      a->engine->set_cell_size(CellW, CellH);
    }
    int c = clamp_cols((width - 2 * PaddingX) / CellW),
        r = clamp_rows((height - 2 * PaddingY) / CellH);
    auto old = a->engine->snapshot();
    if (old.cols != c || old.rows != r)
      a->engine->resize(c, r);
    refresh_search(a, true);
    struct winsize ws{(unsigned short)r, (unsigned short)c,
                      (unsigned short)(c * CellW), (unsigned short)(r * CellH)};
    if (ioctl(a->pty, TIOCSWINSZ, &ws) < 0)
      fail("TIOCSWINSZ");
    a->applied_zoom_step = a->zoom_step;
    a->dirty = true;
  } catch (...) {
    if (a->zoom_step != a->applied_zoom_step) {
      a->zoom_step = a->applied_zoom_step;
      try { throw; } catch (const std::exception &e) {
        std::fprintf(stderr, "cudaterm: zoom unchanged: %s\n", e.what());
      }
      resized(w, width, height);
      return;
    }
    a->error = std::current_exception();
  }
}
void reload_settings(App *a) {
  a->reload_pending = false;
  try {
    auto candidate = a->options->no_config ? ct::Settings{} :
      ct::read_settings(a->options->config_path, a->options->config_required);
    for (const auto &entry : a->options->overrides) ct::set_setting(candidate, entry.first, entry.second);
    auto theme = ct::settings_theme(candidate);
    // Prepare and validate before replacing the current configuration or atlas.
    ct::FontAtlas font;
    float sx, sy; glfwGetWindowContentScale(a->window, &sx, &sy);
    float pixels = std::min(128.0f / candidate.line_height,
      candidate.font_size * sy * (1.0f + a->zoom_step * 0.1f));
    if (candidate.font_family != "bitmap") {
      font = ct::rasterize_font(candidate.font_family, pixels, candidate.line_height, candidate.font_fallback);
      a->engine->load_faces(font.faces);
      BaseCellW = font.width; BaseCellH = font.height;
    } else if (!candidate.font_face.empty()) {
      auto face = ct::face_header(candidate.font_face);
      a->engine->load_face(candidate.font_face);
      BaseCellW = face.width; BaseCellH = face.height;
    } else {
      a->engine->load_faces({}); BaseCellW = a->options->bitmap_width; BaseCellH = a->options->bitmap_height;
    }
    a->settings = candidate;
    a->loaded_family = candidate.font_family == "bitmap" ? "" : candidate.font_family;
    a->loaded_face = candidate.font_face;
    a->font_pixels = pixels; a->font_line_height = candidate.line_height;
    a->engine->set_theme(theme);
    a->engine->set_background_opacity(candidate.opacity);
    int width, height; glfwGetFramebufferSize(a->window, &width, &height);
    resized(a->window, width, height);
  } catch (const std::exception &e) {
    std::fprintf(stderr, "cudaterm: config reload failed: %s\n", e.what());
  }
}
void scale_changed(GLFWwindow *window, float, float) {
  int width, height;
  glfwGetFramebufferSize(window, &width, &height);
  resized(window, width, height);
}
void pump_decode(void *context, bool busy) {
  auto *a = static_cast<App *>(context);
  a->decoding = busy;
  if (busy) {
    // Keep OS input and GPU mouse encoding responsive without parsing the next
    // PTY frame or presenting a partially decoded image.
    uint64_t start = a->trace->begin();
    glfwWaitEventsTimeout(0.001);
    flush_input(a);
    a->trace->record(start, "decode_input_pump", a->input.size());
  } else if (a->pending_width && a->pending_height) {
    resized(a->window, a->pending_width, a->pending_height);
    a->pending_width = a->pending_height = 0;
  }
}
} // namespace

int main(int argc, char **argv) {
  try {
    Trace trace;
    trace.open(std::getenv("CUDATERM_TRACE"));
    auto startup_stage = trace.begin();
    auto startup_checkpoint = [&](const char *stage) {
      trace.record(startup_stage, stage, 0);
      startup_stage = trace.begin();
    };
    Options o = options(argc, argv);
    startup_checkpoint("startup_options");
    ct::FontAtlas initial_font;
    if (o.settings.font_family != "bitmap") {
      initial_font = ct::rasterize_font(o.settings.font_family, o.settings.font_size, o.settings.line_height, o.settings.font_fallback);
      CellW = initial_font.width; CellH = initial_font.height;
    } else if (!o.settings.font_face.empty()) {
      auto face = ct::face_header(o.settings.font_face);
      CellW = face.width; CellH = face.height;
    }
    BaseCellW = CellW; BaseCellH = CellH;
    ct::Theme theme = ct::settings_theme(o.settings);
    startup_checkpoint("startup_fonts");
    struct winsize ws{(unsigned short)o.rows, (unsigned short)o.cols,
                      (unsigned short)(o.cols * CellW),
                      (unsigned short)(o.rows * CellH)};
    Pty p;
    p.child = forkpty(&p.fd, nullptr, nullptr, &ws);
    if (p.child < 0)
      fail("forkpty");
    if (!p.child) {
      if (!o.directory.empty() && chdir(o.directory.c_str()) < 0) {
        std::perror("cudaterm: working directory");
        _exit(126);
      }
      setenv("TERM", "xterm-256color", 1);
      setenv("COLORTERM", "truecolor", 1);
      execvp(o.command[0], o.command.data());
      _exit(127);
    }
    int flags = fcntl(p.fd, F_GETFL, 0);
    if (flags < 0 || fcntl(p.fd, F_SETFL, flags | O_NONBLOCK) < 0)
      fail("fcntl");
    startup_checkpoint("startup_pty");
    // Keep GLFW and the GL context on the main thread while CUDA initializes.
    // Environment defaults are installed before either initialization can read them.
    ct::configure_runtime();
    std::unique_ptr<Engine> engine_owner;
    Graphics graphics; // The worker joins before graphics cleanup on startup failure.
    auto engine_task = std::async(std::launch::async | std::launch::deferred,
        [&, font = std::move(initial_font)]() mutable {
          auto start = trace.begin();
          auto engine = std::make_unique<Engine>(o.cols, o.rows);
          trace.record(start, "startup_engine_worker", 0);
          start = trace.begin();
          engine->set_cell_size(CellW, CellH);
          if (!font.faces[0].empty()) engine->load_faces(font.faces);
          else if (!o.settings.font_face.empty()) engine->load_face(o.settings.font_face);
          font = {};
          engine->set_theme(theme);
          engine->set_background_opacity(o.settings.opacity);
          trace.record(start, "startup_upload_worker", 0);
          return engine;
        });
    startup_checkpoint("startup_engine_dispatch");
    // The compositor owns window decorations. Loading libdecor's GTK plugin
    // adds a second UI toolkit (and fails on seatless headless compositors).
    glfwInitHint(GLFW_WAYLAND_LIBDECOR, GLFW_WAYLAND_DISABLE_LIBDECOR);
    if (!glfwInit())
      throw std::runtime_error("glfwInit failed");
    startup_checkpoint("startup_glfw");
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
    glfwWindowHint(GLFW_TRANSPARENT_FRAMEBUFFER, GLFW_TRUE);
    glfwWindowHintString(GLFW_WAYLAND_APP_ID, o.app_id.c_str());
    glfwWindowHintString(GLFW_X11_CLASS_NAME, o.app_id.c_str());
    glfwWindowHintString(GLFW_X11_INSTANCE_NAME, o.app_id.c_str());
    GLFWwindow *&win = graphics.window;
    win = glfwCreateWindow(o.cols * CellW + 2 * o.settings.padding_x,
                           o.rows * CellH + 2 * o.settings.padding_y, o.title.c_str(), nullptr,
                           nullptr);
    if (!win)
      throw std::runtime_error("glfwCreateWindow failed");
    glfwMakeContextCurrent(win);
    startup_checkpoint("startup_gl_context");
    engine_owner = engine_task.get();
    Engine &engine = *engine_owner;
    startup_checkpoint("startup_engine_join");
    App app{&engine, p.fd};
    app.window = win;
    app.options = &o; app.settings = o.settings;
    app.loaded_face = o.settings.font_face;
    if (o.settings.font_family != "bitmap") {
      app.loaded_family = o.settings.font_family;
      app.font_pixels = o.settings.font_size; app.font_line_height = o.settings.line_height;
    }
    app.cursor_deadline = glfwGetTime() + 0.6;
    app.trace = &trace;
    engine.set_decode_pump(pump_decode, &app);
    glfwSetWindowUserPointer(win, &app);
    glfwGetCursorPos(win, &app.pointer_x, &app.pointer_y);
    glfwSetKeyCallback(win, key);
    glfwSetCharCallback(win, character);
    glfwSetCharModsCallback(win, character_modifiers);
    glfwSetInputMode(win, GLFW_LOCK_KEY_MODS, GLFW_TRUE);
    glfwSetMouseButtonCallback(win, mouse_button);
    glfwSetDropCallback(win, drop_files);
    glfwSetScrollCallback(win, wheel);
    glfwSetCursorPosCallback(win, pointer_moved);
    glfwSetWindowFocusCallback(win, focus_changed);
    glfwSetFramebufferSizeCallback(win, resized);
    glfwSetWindowContentScaleCallback(win, scale_changed);
    glfwSwapInterval(0);
    int initial_w, initial_h;
    glfwGetFramebufferSize(win, &initial_w, &initial_h);
    resized(win, initial_w, initial_h);
    if (app.error)
      std::rethrow_exception(app.error);
    ImeSession ime_session(app);
    startup_checkpoint("startup_resize");
    GLuint &pbo = graphics.pbo;
    size_t pbo_capacity = (size_t)o.cols * CellW * o.rows * CellH * 4;
    glGenBuffers(1, &pbo);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
    glBufferData(GL_PIXEL_UNPACK_BUFFER, pbo_capacity, nullptr, GL_STREAM_DRAW);
    glGenTextures(1, &graphics.texture);
    glBindTexture(GL_TEXTURE_2D, graphics.texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    cudaGraphicsResource *&resource = graphics.resource;
    check_cuda(cudaGraphicsGLRegisterBuffer(
                   &resource, pbo, cudaGraphicsRegisterFlagsWriteDiscard),
               "cudaGraphicsGLRegisterBuffer");
    startup_checkpoint("startup_interop");
    bool eof = false;
    int status = 0;
    int texture_w = 0, texture_h = 0;
    PtyWaiter waiter;
    waiter.init(p.child);
    ct::ReloadSignal reload_signal(waiter.wake_fd);
    waiter.worker = std::thread([&] {
      pollfd f[3]{{p.fd, POLLIN, 0}, {waiter.wake_fd, POLLIN, 0},
                  {waiter.pid_fd, POLLIN, 0}};
      for (;;) {
        {
          std::lock_guard<std::mutex> lock(waiter.mutex);
          f[0].fd = waiter.armed ? p.fd : -1;
          f[0].events = waiter.events;
        }
        int ready = poll(f, 3, -1);
        if (ready < 0) {
          if (errno == EINTR)
            continue;
          waiter.failure.store(errno, std::memory_order_release);
          glfwPostEmptyEvent();
          break;
        }
        if (f[1].revents) {
          uint64_t value;
          while (read(waiter.wake_fd, &value, sizeof(value)) == sizeof(value)) {}
          if (ct::ReloadSignal::pending()) glfwPostEmptyEvent();
          if (waiter.stop.load(std::memory_order_acquire))
            return;
          continue;
        }
        if (f[2].revents) {
          f[2].fd = -1; // pidfds remain readable after exit.
          glfwPostEmptyEvent();
        }
        if (f[0].revents) {
          std::lock_guard<std::mutex> lock(waiter.mutex);
          waiter.armed = false;
          glfwPostEmptyEvent();
        }
      }
    });
    auto next_frame = std::chrono::steady_clock::now();
    auto sync_started = next_frame;
    bool sync_active = false;
    bool coalescing = false;
    auto coalesce_until = next_frame;
    unsigned char buf[65536];
    size_t pending = 0;
    auto reap_child = [&] {
      if (p.child <= 0)
        return;
      pid_t r = waitpid(p.child, &status, WNOHANG);
      if (r == p.child)
        p.child = -1;
      else if (r < 0 && errno != EINTR && errno != ECHILD)
        fail("waitpid");
    };
    while (!glfwWindowShouldClose(win) && (!eof || p.child > 0 || pending)) {
      if (app.error)
        std::rethrow_exception(app.error);
      int waiter_error = waiter.failure.load(std::memory_order_acquire);
      if (waiter_error)
        throw std::runtime_error(std::string("PTY waiter: ") + std::strerror(waiter_error));
      if (ct::ReloadSignal::take()) app.reload_pending = true;
      if (app.reload_pending) reload_settings(&app);
      reap_child();
      pollfd f{p.fd, POLLIN, 0};
      int ready = eof ? 0 : poll(&f, 1, 0);
      if (ready < 0 && errno != EINTR)
        fail("poll");
      // This decision is driven by the pidfd readiness event.  A zero-result
      // poll on the PTY alone is only EAGAIN and must not end the session.
      if (ready >= 0 && p.child < 0 && !pending && !(f.revents & POLLIN))
        eof = true;
      size_t drained = 0;
      bool frame_complete = false;
      if (!pending && !eof && f.revents & (POLLIN | POLLHUP | POLLERR)) {
        while (drained < sizeof buf) {
          ssize_t n = read(p.fd, buf + drained, sizeof buf - drained);
          if (n > 0)
            drained += (size_t)n;
          else if (n < 0 && errno == EINTR)
            continue;
          else {
            if (n == 0 || (n < 0 && errno == EIO))
              eof = true;
            else if (errno != EAGAIN)
              fail("PTY read");
            break;
          }
        }
        pending = drained;
      }
      if (pending) {
        if (!coalescing) {
          coalesce_until = std::chrono::steady_clock::now() + std::chrono::milliseconds(1);
          coalescing = true;
        }
        uint64_t trace_start = trace.begin();
        auto result = engine.feed_frame(buf, pending);
        drained = result.consumed;
        frame_complete = result.frame_complete;
        app.clipboard_writes.feed(buf, drained, [&](const std::string &text) {
          glfwSetClipboardString(win, text.c_str());
        });
        pending -= drained;
        std::memmove(buf, buf + drained, pending);
        std::string replies = engine.take_replies();
        std::string title;
        if (engine.take_title(title)) glfwSetWindowTitle(win, title.c_str());
        bool syncing = engine.synchronized_updates();
        // Only an idle/abandoned update expires. Long, actively arriving
        // browser uploads must keep the previously presented frame intact.
        if (syncing) sync_started = std::chrono::steady_clock::now();
        sync_active = syncing;
        trace.record(trace_start, "pty_engine_feed", drained);
        app.dirty = true;
        app.selecting = false; app.link_click = false;
        if (!replies.empty())
          queue(&app, (const unsigned char *)replies.data(), replies.size());
        refresh_search(&app, false);
      }
      flush_input(&app);
      eof = eof || app.input_closed;
      if (app.copy_flash_deadline && glfwGetTime() >= app.copy_flash_deadline) {
        engine.set_copy_flash(false);
        app.copy_flash_deadline = 0;
        app.dirty = true;
      }
      auto cursor_state = engine.snapshot();
      ime_cursor(&app, cursor_state);
      bool autoscroll = false;
      if (app.selecting && !cursor_state.alternate_screen) {
        int window_w, window_h, pixels_w, pixels_h;
        glfwGetWindowSize(win, &window_w, &window_h);
        glfwGetFramebufferSize(win, &pixels_w, &pixels_h);
        double y = window_h > 0 ? app.pointer_y * pixels_h / window_h : 0;
        int direction = y < PaddingY + CellH / 2 ? 1 :
                        y >= pixels_h - PaddingY - CellH / 2 ? -1 : 0;
        autoscroll = direction && (direction > 0 ? cursor_state.view_offset < cursor_state.history_rows :
                                                            cursor_state.view_offset > 0);
        if (autoscroll && glfwGetTime() >= app.selection_deadline) {
          engine.scroll_view(direction);
          pointer_moved(win, app.pointer_x, app.pointer_y);
          app.selection_deadline = glfwGetTime() + 0.04;
        }
      }
      float previous_x = app.cursor_motion.x, previous_y = app.cursor_motion.y;
      bool cursor_animating = app.cursor_motion.update(cursor_state.col, cursor_state.row, glfwGetTime(),
        app.settings.cursor_animation, !app.focused || !cursor_state.cursor_visible || app.searching ||
        cursor_state.view_offset || app.cursor_last_alternate != cursor_state.alternate_screen ||
        glfwGetTime() - app.last_input > ct::kUserInputWindow);
      app.cursor_last_alternate = cursor_state.alternate_screen;
      if (app.cursor_motion.x != previous_x || app.cursor_motion.y != previous_y || app.dirty) {
        engine.set_cursor_position(app.cursor_motion.x, app.cursor_motion.y);
        app.dirty = true;
      }
      bool blinking = app.focused && cursor_state.cursor_visible &&
                      !cursor_state.view_offset && (cursor_state.cursor_style & 1);
      if (blinking && glfwGetTime() >= app.cursor_deadline) {
        app.cursor_phase = !app.cursor_phase;
        app.cursor_deadline = glfwGetTime() + 0.6;
        engine.set_cursor_phase(app.cursor_phase, app.focused);
        app.dirty = true;
      }
      int wsx, wsy;
      glfwGetFramebufferSize(win, &wsx, &wsy);
      size_t needed = (size_t)wsx * wsy * 4;
      if (needed && (needed > pbo_capacity || needed < pbo_capacity / 2)) {
        check_cuda(cudaGraphicsUnregisterResource(resource),
                   "cudaGraphicsUnregisterResource");
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
        glBufferData(GL_PIXEL_UNPACK_BUFFER, needed, nullptr, GL_STREAM_DRAW);
        pbo_capacity = needed;
        check_cuda(cudaGraphicsGLRegisterBuffer(
                       &resource, pbo, cudaGraphicsRegisterFlagsWriteDiscard),
                   "cudaGraphicsGLRegisterBuffer");
      }
      if (wsx > 0 && wsy > 0 && (texture_w != wsx || texture_h != wsy)) {
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
        glBindTexture(GL_TEXTURE_2D, graphics.texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, wsx, wsy, 0, GL_RGBA,
                     GL_UNSIGNED_BYTE, nullptr);
        texture_w = wsx;
        texture_h = wsy;
      }
      if (app.dirty && wsx > 0 && wsy > 0 &&
          (!sync_active || (eof && !pending) || std::chrono::steady_clock::now() - sync_started >=
                                   std::chrono::seconds(1)) &&
          (frame_complete || std::chrono::steady_clock::now() >= next_frame)) {
        // Consume immediately available burst input before drawing a partial
        // update, but stop coalescing after 1 ms so continuous output gets frames.
        // Explicit synchronized-update boundaries always remain immediate.
        if (coalescing && !frame_complete && !eof &&
            std::chrono::steady_clock::now() < coalesce_until) {
          pollfd more{p.fd, POLLIN, 0};
          int available = pending ? 0 : poll(&more, 1, 0);
          if (available < 0 && errno != EINTR) fail("poll before render");
          if (pending || (available > 0 && (more.revents & POLLIN))) {
            glfwPollEvents();
            continue;
          }
        }
        glViewport(0, 0, wsx, wsy);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
        void *device = nullptr;
        size_t bytes = 0;
        uint64_t trace_start = trace.begin();
        check_cuda(cudaGraphicsMapResources(1, &resource),
                   "cudaGraphicsMapResources");
        check_cuda(
            cudaGraphicsResourceGetMappedPointer(&device, &bytes, resource),
            "cudaGraphicsResourceGetMappedPointer");
        trace.record(trace_start, "graphics_map_pointer", bytes);
        trace_start = trace.begin();
        engine.render((uint32_t *)device, wsx, wsy);
        check_cuda(cudaGraphicsUnmapResources(1, &resource),
                   "cudaGraphicsUnmapResources");
        trace.record(trace_start, "engine_render_unmap", bytes);
        glClear(GL_COLOR_BUFFER_BIT);
        trace_start = trace.begin();
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
        glBindTexture(GL_TEXTURE_2D, graphics.texture);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, wsx, wsy, GL_RGBA,
                        GL_UNSIGNED_BYTE, nullptr);
        glEnable(GL_TEXTURE_2D);
        glBegin(GL_QUADS);
        glTexCoord2f(0.0f, 1.0f);
        glVertex2f(-1.0f, -1.0f);
        glTexCoord2f(1.0f, 1.0f);
        glVertex2f(1.0f, -1.0f);
        glTexCoord2f(1.0f, 0.0f);
        glVertex2f(1.0f, 1.0f);
        glTexCoord2f(0.0f, 0.0f);
        glVertex2f(-1.0f, 1.0f);
        glEnd();
        glDisable(GL_TEXTURE_2D);
        glfwSwapBuffers(win);
        trace.record(trace_start, "gl_texture_swap", needed);
        app.dirty = false;
        coalescing = false;
        next_frame =
            std::chrono::steady_clock::now() + std::chrono::microseconds(8333);
      }
      if (drained)
        glfwPollEvents();
      else {
        if (eof && !pending && p.child <= 0)
          break;
        waiter.arm(eof ? 0 : POLLIN | (app.input.empty() ? 0 : POLLOUT));
        int arm_error = waiter.failure.load(std::memory_order_acquire);
        if (arm_error)
          throw std::runtime_error(std::string("PTY waiter: ") + std::strerror(arm_error));
        auto now = std::chrono::steady_clock::now();
        uint64_t trace_start = trace.begin();
        if (app.dirty && wsx > 0 && wsy > 0) {
          auto deadline = next_frame;
          if (sync_active && !(eof && !pending))
            deadline = std::max(deadline, sync_started + std::chrono::seconds(1));
          double timeout = std::chrono::duration<double>(deadline - now).count();
          glfwWaitEventsTimeout(std::max(0.0001, timeout));
        } else if (blinking || autoscroll || cursor_animating || app.copy_flash_deadline) {
          double deadline = blinking ? app.cursor_deadline : glfwGetTime() + 1;
          if (app.copy_flash_deadline) deadline = std::min(deadline, app.copy_flash_deadline);
          if (autoscroll) deadline = std::min(deadline, app.selection_deadline);
          if (cursor_animating) deadline = std::min(deadline, glfwGetTime() + 1.0 / 120);
          glfwWaitEventsTimeout(std::max(0.0001, deadline - glfwGetTime()));
        } else {
          glfwWaitEvents();
        }
        trace.record(trace_start, "event_wait", 0);
      }
      reap_child();
    }
    if (!o.dump.empty()) {
      FILE *out = std::fopen(o.dump.c_str(), "w");
      if (!out)
        fail("open dump");
      {
        auto s = engine.snapshot();
        auto cells = engine.cells();
        std::fprintf(out, "snapshot %d %d %d %d\n", s.cols, s.rows, s.row,
                     s.col);
        for (int y = 0; y < s.rows; ++y) {
          for (int x = 0; x < s.cols; ++x)
            std::fputc((cells[(size_t)y * s.cols + x].cp >= 32 &&
                        cells[(size_t)y * s.cols + x].cp < 127)
                           ? (int)cells[(size_t)y * s.cols + x].cp
                           : ' ',
                       out);
          std::fputc('\n', out);
        }
        std::fclose(out);
      }
    }
    return p.child > 0         ? 0
           : WIFEXITED(status) ? WEXITSTATUS(status)
                               : 128 + WTERMSIG(status);
  } catch (const std::exception &e) {
    std::fprintf(stderr, "cudaterm: %s\n", e.what());
    return 1;
  }
}
