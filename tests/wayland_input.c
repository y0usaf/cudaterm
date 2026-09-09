#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-unstable-v1-client.h"
#include "wlr-virtual-pointer-unstable-v1-client.h"
#include "wlr-data-control-unstable-v1-client.h"

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *keyboards;
static struct zwlr_virtual_pointer_manager_v1 *pointers;
static struct zwlr_data_control_manager_v1 *control;
static struct zwlr_data_control_offer_v1 *primary;

static void mime(void *data, struct zwlr_data_control_offer_v1 *offer, const char *type) {
    (void)data; (void)offer; (void)type;
}
static void offered(void *data, struct zwlr_data_control_device_v1 *device,
                    struct zwlr_data_control_offer_v1 *offer) {
    (void)data; (void)device;
    static const struct zwlr_data_control_offer_v1_listener listener = { mime };
    zwlr_data_control_offer_v1_add_listener(offer, &listener, NULL);
}
static void clipboard(void *data, struct zwlr_data_control_device_v1 *device,
                      struct zwlr_data_control_offer_v1 *offer) {
    (void)data; (void)device;
    if (offer) zwlr_data_control_offer_v1_destroy(offer);
}
static void finished(void *data, struct zwlr_data_control_device_v1 *device) {
    (void)data; (void)device;
}
static void selection(void *data, struct zwlr_data_control_device_v1 *device,
                      struct zwlr_data_control_offer_v1 *offer) {
    (void)data; (void)device;
    if (primary) zwlr_data_control_offer_v1_destroy(primary);
    primary = offer;
}

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    (void)data;
    if (!strcmp(interface, "wl_seat") && !seat)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (!strcmp(interface, "zwp_virtual_keyboard_manager_v1"))
        keyboards = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    else if (!strcmp(interface, "zwlr_virtual_pointer_manager_v1"))
        pointers = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
    else if (!strcmp(interface, "zwlr_data_control_manager_v1") && version >= 2)
        control = wl_registry_bind(registry, name, &zwlr_data_control_manager_v1_interface, 2);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fputs("cannot connect to private Wayland display\n", stderr); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    const struct wl_registry_listener listener = { global, removed };
    wl_registry_add_listener(registry, &listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !seat || !keyboards || !pointers || !control) {
        fputs("private compositor lacks virtual input protocols\n", stderr); return 1;
    }
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    const struct xkb_rule_names names = { .rules="evdev", .model="pc105", .layout="us" };
    struct xkb_keymap *keymap = context ? xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS) : NULL;
    struct xkb_state *state = keymap ? xkb_state_new(keymap) : NULL;
    char *text = keymap ? xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1) : NULL;
    if (!state || !text) { fputs("cannot create evdev test keymap\n", stderr); return 1; }
    size_t size = strlen(text) + 1;
    int fd = memfd_create("cudaterm-test-keymap", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, size)) { perror("test keymap storage"); return 1; }
    void *mapped = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapped == MAP_FAILED) { perror("test keymap mmap"); return 1; }
    memcpy(mapped, text, size);
    struct zwp_virtual_keyboard_v1 *keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(keyboards, seat);
    struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pointers, seat);
    struct zwlr_data_control_device_v1 *data_device = zwlr_data_control_manager_v1_get_data_device(control, seat);
    static const struct zwlr_data_control_device_v1_listener data_listener = {
        offered, clipboard, finished, selection
    };
    zwlr_data_control_device_v1_add_listener(data_device, &data_listener, NULL);
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
    munmap(mapped, size); close(fd); free(text);
    if (wl_display_roundtrip(display) < 0) return 1;
    puts("ready"); fflush(stdout);
    char line[128], type;
    unsigned first, second;
    while (fgets(line, sizeof line, stdin)) {
        if (sscanf(line, " %c %u %u", &type, &first, &second) != 3) {
            fputs("invalid virtual input command\n", stderr); return 1;
        }
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        uint32_t time = (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);
        if (type == 'c') {
            // Deliberately abandon a primary transfer before the source writes.
            // The terminal must handle EPIPE without receiving fatal SIGPIPE.
            if (wl_display_roundtrip(display) < 0 || !primary) return 1;
            int pipefd[2];
            if (pipe(pipefd)) return 1;
            close(pipefd[0]);
            zwlr_data_control_offer_v1_receive(primary, "text/plain;charset=utf-8", pipefd[1]);
            close(pipefd[1]);
        } else if (type == 'k' && first < 256 && second <= 1) {
            xkb_state_update_key(state, first + 8, second ? XKB_KEY_DOWN : XKB_KEY_UP);
            zwp_virtual_keyboard_v1_modifiers(keyboard,
                xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED),
                xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED),
                xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED),
                xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE));
            zwp_virtual_keyboard_v1_key(keyboard, time, first, second);
        } else if (type == 'm' && first <= 1000 && second <= 700) {
            zwlr_virtual_pointer_v1_motion_absolute(pointer, time, first, second, 1000, 700);
            zwlr_virtual_pointer_v1_frame(pointer);
        } else if (type == 'b' && first >= 272 && first <= 274 && second <= 1) {
            zwlr_virtual_pointer_v1_button(pointer, time, first, second);
            zwlr_virtual_pointer_v1_frame(pointer);
        } else { fputs("unsupported virtual input command\n", stderr); return 1; }
        if (wl_display_roundtrip(display) < 0) return 1;
        puts("ok"); fflush(stdout);
    }
    zwlr_virtual_pointer_v1_destroy(pointer);
    zwp_virtual_keyboard_v1_destroy(keyboard);
    if (primary) zwlr_data_control_offer_v1_destroy(primary);
    zwlr_data_control_device_v1_destroy(data_device);
    wl_display_roundtrip(display);
    xkb_state_unref(state); xkb_keymap_unref(keymap); xkb_context_unref(context);
    wl_registry_destroy(registry); wl_display_disconnect(display);
    return 0;
}
