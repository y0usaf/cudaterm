#include <libweston/libweston.h>
#include <libweston/desktop.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

// Backend API declarations from the pinned Weston 16 libweston-internal.h.
// A virtual seat makes seat-dependent clients usable in an isolated compositor;
// this module never opens input devices or connects to the user's desktop.
void weston_seat_init(struct weston_seat *, struct weston_compositor *, const char *);
int weston_seat_init_pointer(struct weston_seat *);
int weston_seat_init_keyboard(struct weston_seat *, struct xkb_keymap *);
void weston_seat_release(struct weston_seat *);
void notify_key(const struct weston_key_event *);
void notify_motion(const struct weston_pointer_motion_event *);
void notify_button(const struct weston_pointer_button_event *);
void notify_pointer_frame(struct weston_seat *);
struct test_seat {
  struct weston_seat seat;
  struct wl_listener destroy;
  int input;
  struct wl_event_source *source;
};
static int keys(int fd, uint32_t mask, void *data) {
  (void)mask;
  struct test_seat *test = data;
  uint32_t packet[2];
  while (read(fd, packet, sizeof packet) == sizeof packet) {
    struct timespec now;
    weston_compositor_get_time(&now);
    if (packet[0] == 768) {
      struct weston_pointer_motion_event motion;
      struct weston_coord_global position = { .c = { packet[1] >> 16, packet[1] & 65535 } };
      weston_pointer_motion_event_init(&motion, &now, &test->seat,
        WESTON_POINTER_MOTION_ABS, &position, NULL, NULL);
      notify_motion(&motion);
      notify_pointer_frame(&test->seat);
      continue;
    }
    if (packet[0] == 769) {
      struct weston_pointer_button_event button;
      weston_pointer_button_event_init(&button, &now, &test->seat,
        packet[1] >> 1, packet[1] & 1);
      notify_button(&button);
      notify_pointer_frame(&test->seat);
      continue;
    }
    if (packet[0] == 770) {
      int width = packet[1] >> 16, height = packet[1] & 65535;
      struct weston_keyboard *keyboard = weston_seat_get_keyboard(&test->seat);
      if (keyboard && keyboard->focus && width > 0 && height > 0 &&
          weston_surface_is_desktop_surface(keyboard->focus)) {
        struct weston_desktop_surface *surface =
          weston_surface_get_desktop_surface(keyboard->focus);
        if (surface)
          weston_desktop_surface_set_size(surface, width, height);
      }
      continue;
    }
    if (packet[0] == 771) {
      struct weston_keyboard *keyboard = weston_seat_get_keyboard(&test->seat);
      if (keyboard && keyboard->focus && weston_surface_is_desktop_surface(keyboard->focus)) {
        struct weston_desktop_surface *surface =
          weston_surface_get_desktop_surface(keyboard->focus);
        if (surface)
          weston_desktop_surface_close(surface);
      }
      continue;
    }
    if (packet[0] > 767 || packet[1] > 1) continue;
    struct weston_key_event event;
    weston_key_event_init(&event, &now, &test->seat, packet[0], packet[1], STATE_UPDATE_AUTOMATIC);
    notify_key(&event);
  }
  return 0;
}
static void cleanup(struct wl_listener *listener, void *data) {
  (void)data;
  struct test_seat *test = wl_container_of(listener, test, destroy);
  wl_list_remove(&test->destroy.link);
  if (test->source) wl_event_source_remove(test->source);
  if (test->input >= 0) close(test->input);
  weston_seat_release(&test->seat);
  free(test);
}
WL_EXPORT int wet_module_init(struct weston_compositor *compositor, int *argc, char *argv[]) {
  (void)argc; (void)argv;
  struct test_seat *test = calloc(1, sizeof(*test));
  if (!test) return -1;
  test->input = -1;
  weston_seat_init(&test->seat, compositor, "cudaterm-test");
  if (weston_seat_init_pointer(&test->seat) < 0 ||
      weston_seat_init_keyboard(&test->seat, NULL) < 0) {
    weston_seat_release(&test->seat); free(test); return -1;
  }
  const char *input = getenv("CUDATERM_TEST_KEYS");
  if (input) {
    test->input = open(input, O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (test->input < 0) { weston_seat_release(&test->seat); free(test); return -1; }
    test->source = wl_event_loop_add_fd(wl_display_get_event_loop(compositor->wl_display),
      test->input, WL_EVENT_READABLE, keys, test);
    if (!test->source) { close(test->input); weston_seat_release(&test->seat); free(test); return -1; }
  }
  test->destroy.notify = cleanup;
  wl_signal_add(&compositor->destroy_signal, &test->destroy);
  return 0;
}
