#pragma once

#include <cstdint>

#if defined(__CUDACC__)
#define CT_KEYBOARD_HD __host__ __device__
#else
#define CT_KEYBOARD_HD
#endif

namespace ct::keyboard {

// Kitty's five protocol flags.  The device currently implements only
// disambiguation; the other values remain named here so the host encoder and
// a later callback increment can share the wire constants.
constexpr uint32_t DISAMBIGUATE = 1u << 0;
constexpr uint32_t REPORT_EVENTS = 1u << 1;
constexpr uint32_t REPORT_ALTERNATES = 1u << 2;
constexpr uint32_t REPORT_ALL = 1u << 3;
constexpr uint32_t REPORT_TEXT = 1u << 4;
constexpr uint32_t ALL_FLAGS = DISAMBIGUATE | REPORT_EVENTS | REPORT_ALTERNATES |
                               REPORT_ALL | REPORT_TEXT;
constexpr uint32_t DEVICE_SUPPORTED_FLAGS = DISAMBIGUATE;
constexpr int KEYBOARD_STACK_DEPTH = 8;

// This state is embedded in the CUDA parser state.  Each screen has its own
// current value and stack, matching Kitty's primary/alternate-screen rule.
struct Negotiation {
  uint32_t flags[2] = {};
  uint32_t stack[2][KEYBOARD_STACK_DEPTH] = {};
  uint8_t depth[2] = {};
};

CT_KEYBOARD_HD inline int screen(bool alternate) { return alternate ? 1 : 0; }

CT_KEYBOARD_HD inline uint32_t current(const Negotiation &state,
                                       bool alternate) {
  return state.flags[screen(alternate)];
}

CT_KEYBOARD_HD inline void clear_stack(Negotiation &state, int which) {
  state.flags[which] = 0;
  state.depth[which] = 0;
  for (int i = 0; i < KEYBOARD_STACK_DEPTH; ++i)
    state.stack[which][i] = 0;
}

CT_KEYBOARD_HD inline void reset(Negotiation &state) {
  clear_stack(state, 0);
  clear_stack(state, 1);
}

CT_KEYBOARD_HD inline void set(Negotiation &state, bool alternate,
                               uint32_t requested, uint32_t mode) {
  const int which = screen(alternate);
  const uint32_t value = requested & DEVICE_SUPPORTED_FLAGS;
  if (mode == 1)
    state.flags[which] = value;
  else if (mode == 2)
    state.flags[which] |= value;
  else if (mode == 3)
    state.flags[which] &= ~value;
}

CT_KEYBOARD_HD inline void push(Negotiation &state, bool alternate,
                                uint32_t requested) {
  const int which = screen(alternate);
  const uint32_t value = requested & DEVICE_SUPPORTED_FLAGS;
  if (state.depth[which] < KEYBOARD_STACK_DEPTH) {
    state.stack[which][state.depth[which]++] = state.flags[which];
  } else {
    // Keep the newest eight saved values.  This is the bounded equivalent of
    // Kitty's oldest-entry eviction when a push overflows the stack.
    for (int i = 1; i < KEYBOARD_STACK_DEPTH; ++i)
      state.stack[which][i - 1] = state.stack[which][i];
    state.stack[which][KEYBOARD_STACK_DEPTH - 1] = state.flags[which];
  }
  state.flags[which] = value;
}

CT_KEYBOARD_HD inline void pop(Negotiation &state, bool alternate,
                               uint32_t requested) {
  const int which = screen(alternate);
  if (!requested)
    return;
  // Popping exactly the number of saved levels is valid, including a full
  // depth-eight stack: it restores the value saved before the first push.
  // A larger request has no saved predecessor and resets the stack.
  if (requested > state.depth[which]) {
    clear_stack(state, which);
    return;
  }
  state.depth[which] = static_cast<uint8_t>(state.depth[which] - requested);
  state.flags[which] = state.stack[which][state.depth[which]];
  for (int i = state.depth[which]; i < KEYBOARD_STACK_DEPTH; ++i)
    state.stack[which][i] = 0;
}

} // namespace ct::keyboard

#undef CT_KEYBOARD_HD
