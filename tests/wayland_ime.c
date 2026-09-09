#define _GNU_SOURCE

#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "input-method-unstable-v2-client.h"

static struct wl_display *display;
static struct wl_seat *seat;
static struct zwp_input_method_manager_v2 *manager;
static struct zwp_input_method_v2 *input_method;
static struct zwp_input_method_keyboard_grab_v2 *keyboard_grab;
static bool active;
static bool active_pending;
static bool quit;
static uint32_t commit_serial;

static void status(const char *message) {
    puts(message);
    fflush(stdout);
}

static void status_error(const char *message) {
    fputs("error ", stdout);
    puts(message);
    fflush(stdout);
}

static void input_method_activate(void *data, struct zwp_input_method_v2 *object) {
    (void)data;
    if (object != input_method)
        return;
    active = true;
    active_pending = true;
}

static void input_method_deactivate(void *data, struct zwp_input_method_v2 *object) {
    (void)data;
    if (object != input_method)
        return;
    const bool was_active = active || active_pending;
    active = false;
    active_pending = false;
    if (was_active)
        status("inactive");
}

static void input_method_surrounding_text(void *data,
                                          struct zwp_input_method_v2 *object,
                                          const char *text,
                                          uint32_t cursor,
                                          uint32_t anchor) {
    (void)data;
    (void)object;
    (void)text;
    (void)cursor;
    (void)anchor;
}

static void input_method_text_change_cause(void *data,
                                           struct zwp_input_method_v2 *object,
                                           uint32_t cause) {
    (void)data;
    (void)object;
    (void)cause;
}

static void input_method_content_type(void *data,
                                      struct zwp_input_method_v2 *object,
                                      uint32_t hint,
                                      uint32_t purpose) {
    (void)data;
    (void)object;
    (void)hint;
    (void)purpose;
}

static void input_method_done(void *data, struct zwp_input_method_v2 *object) {
    (void)data;
    if (object != input_method)
        return;
    // v2 commit serials count done events received by this input method.
    commit_serial++;
    if (active_pending) {
        active_pending = false;
        status("active");
    }
}

static void input_method_unavailable(void *data,
                                     struct zwp_input_method_v2 *object) {
    (void)data;
    if (object != input_method)
        return;
    status_error("unavailable");
    input_method = NULL;
    quit = true;
}

static const struct zwp_input_method_v2_listener input_method_listener = {
    .activate = input_method_activate,
    .deactivate = input_method_deactivate,
    .surrounding_text = input_method_surrounding_text,
    .text_change_cause = input_method_text_change_cause,
    .content_type = input_method_content_type,
    .done = input_method_done,
    .unavailable = input_method_unavailable,
};

static void keyboard_grab_keymap(void *data,
                                 struct zwp_input_method_keyboard_grab_v2 *grab,
                                 uint32_t format,
                                 int32_t fd,
                                 uint32_t size) {
    (void)data;
    (void)grab;
    (void)format;
    (void)size;
    close(fd);
}

// The grab deliberately consumes key events without committing text.  This
// isolates the no-double-insert assertion: while the grab is active, a key
// must not reach Cudaterm's ordinary GLFW character path.  The following c
// command supplies the explicit commit used by the test.

static void keyboard_grab_key(void *data,
                              struct zwp_input_method_keyboard_grab_v2 *grab,
                              uint32_t serial,
                              uint32_t time,
                              uint32_t key,
                              uint32_t state) {
    (void)data;
    (void)grab;
    (void)serial;
    (void)time;
    (void)key;
    (void)state;
    // Consume both press and release events.  No protocol commit is sent for
    // a grabbed key, so the harness can prove that ordinary GLFW character
    // delivery was suppressed by the compositor's keyboard grab.
}

static void keyboard_grab_modifiers(void *data,
                                    struct zwp_input_method_keyboard_grab_v2 *grab,
                                    uint32_t serial,
                                    uint32_t mods_depressed,
                                    uint32_t mods_latched,
                                    uint32_t mods_locked,
                                    uint32_t group) {
    (void)data;
    (void)grab;
    (void)serial;
    (void)mods_depressed;
    (void)mods_latched;
    (void)mods_locked;
    (void)group;
}

static void keyboard_grab_repeat_info(void *data,
                                      struct zwp_input_method_keyboard_grab_v2 *grab,
                                      int32_t rate,
                                      int32_t delay) {
    (void)data;
    (void)grab;
    (void)rate;
    (void)delay;
}

static const struct zwp_input_method_keyboard_grab_v2_listener keyboard_grab_listener = {
    .keymap = keyboard_grab_keymap,
    .key = keyboard_grab_key,
    .modifiers = keyboard_grab_modifiers,
    .repeat_info = keyboard_grab_repeat_info,
};

static void global(void *data,
                   struct wl_registry *registry,
                   uint32_t name,
                   const char *interface,
                   uint32_t version) {
    (void)data;
    if (!strcmp(interface, "wl_seat") && !seat) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface,
                                version < 1 ? 1 : version > 4 ? 4 : version);
    } else if (!strcmp(interface, "zwp_input_method_manager_v2") && !manager) {
        manager = wl_registry_bind(registry, name,
                                   &zwp_input_method_manager_v2_interface, 1);
    }
}

static void removed(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static int send_commit(const char *text, size_t length, bool clear_preedit) {
    if (!active || !input_method) {
        status_error("inactive");
        return 0;
    }
    if (length > 3900) {
        status_error("text too long");
        return 0;
    }

    if (clear_preedit)
        zwp_input_method_v2_set_preedit_string(input_method, "", 0, 0);
    zwp_input_method_v2_commit_string(input_method, text);
    zwp_input_method_v2_commit(input_method, commit_serial);
    if (wl_display_flush(display) < 0 && errno != EAGAIN) {
        status_error("flush failed");
        return -1;
    }
    status("ok");
    return 0;
}

static int send_preedit(const char *text, size_t length) {
    if (!active || !input_method) {
        status_error("inactive");
        return 0;
    }
    if (length > 3900 || length > INT32_MAX) {
        status_error("text too long");
        return 0;
    }

    const int32_t cursor = (int32_t)length;
    zwp_input_method_v2_set_preedit_string(input_method, text, cursor, cursor);
    zwp_input_method_v2_commit(input_method, commit_serial);
    if (wl_display_flush(display) < 0 && errno != EAGAIN) {
        status_error("flush failed");
        return -1;
    }
    status("ok");
    return 0;
}

static int command(char *line) {
    size_t length = strlen(line);
    while (length && (line[length - 1] == '\n' || line[length - 1] == '\r'))
        line[--length] = '\0';
    if (length == 1 && line[0] == 'q') {
        quit = true;
        return 0;
    }
    if (length >= 2 && line[1] == ' ' && (line[0] == 'p' || line[0] == 'c')) {
        if (line[0] == 'p')
            return send_preedit(line + 2, length - 2);
        return send_commit(line + 2, length - 2, true);
    }
    if (length == 1 && line[0] == 'g') {
        if (!active || !input_method) {
            status_error("inactive");
            return 0;
        }
        if (keyboard_grab) {
            zwp_input_method_keyboard_grab_v2_release(keyboard_grab);
            keyboard_grab = NULL;
            if (wl_display_flush(display) < 0 && errno != EAGAIN) {
                status_error("flush failed");
                return -1;
            }
            status("ok");
            return 0;
        }
        keyboard_grab = zwp_input_method_v2_grab_keyboard(input_method);
        if (!keyboard_grab ||
            zwp_input_method_keyboard_grab_v2_add_listener(
                keyboard_grab, &keyboard_grab_listener, NULL) < 0) {
            status_error("grab failed");
            keyboard_grab = NULL;
            return 0;
        }
        if (wl_display_roundtrip(display) < 0) {
            status_error("grab roundtrip failed");
            return -1;
        }
        status("ok");
        return 0;
    }
    status_error("command (p TEXT | c TEXT | g | q)");
    return 0;
}

int main(void) {
    display = wl_display_connect(NULL);
    if (!display) {
        fputs("cannot connect to private Wayland display\n", stderr);
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    static const struct wl_registry_listener registry_listener = { global, removed };
    if (wl_registry_add_listener(registry, &registry_listener, NULL) < 0 ||
        wl_display_roundtrip(display) < 0 || !seat || !manager) {
        fputs("private compositor lacks input-method-v2\n", stderr);
        return 1;
    }

    input_method = zwp_input_method_manager_v2_get_input_method(manager, seat);
    if (!input_method ||
        zwp_input_method_v2_add_listener(input_method, &input_method_listener, NULL) < 0 ||
        wl_display_roundtrip(display) < 0) {
        fputs("cannot create input method\n", stderr);
        return 1;
    }
    status("ready");

    const int display_fd = wl_display_get_fd(display);
    char line[8192];
    while (!quit) {
        if (wl_display_dispatch_pending(display) < 0)
            break;
        if (wl_display_flush(display) < 0 && errno != EAGAIN)
            break;

        struct pollfd fds[2] = {
            { display_fd, POLLIN, 0 },
            { STDIN_FILENO, POLLIN, 0 },
        };
        int result;
        do {
            result = poll(fds, 2, -1);
        } while (result < 0 && errno == EINTR);
        if (result < 0)
            break;
        if (fds[0].revents & (POLLIN | POLLERR | POLLHUP)) {
            if (wl_display_dispatch(display) < 0)
                break;
        }
        if (fds[1].revents & (POLLIN | POLLHUP)) {
            if (!fgets(line, sizeof line, stdin))
                break;
            if (command(line) < 0)
                break;
        }
    }

    if (keyboard_grab)
        zwp_input_method_keyboard_grab_v2_release(keyboard_grab);
    if (input_method)
        zwp_input_method_v2_destroy(input_method);
    if (manager)
        zwp_input_method_manager_v2_destroy(manager);
    if (seat)
        wl_seat_destroy(seat);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    return 0;
}
