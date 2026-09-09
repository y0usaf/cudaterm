#pragma once
#include <atomic>
#include <cerrno>
#include <csignal>
#include <cstdint>
#include <stdexcept>
#include <unistd.h>

namespace ct {
// The handler only wakes the existing eventfd waiter. Configuration and GLFW
// calls stay on the window thread, including when the terminal was idle.
class ReloadSignal {
  inline static std::atomic<int> descriptor{-1};
  inline static std::atomic<bool> requested{false};
  struct sigaction previous{};
  static void handle(int) {
    int saved = errno;
    requested.store(true, std::memory_order_relaxed);
    int fd = descriptor.load(std::memory_order_relaxed);
    uint64_t one = 1;
    if (fd >= 0) {
      while (write(fd, &one, sizeof one) < 0 && errno == EINTR) {}
    }
    errno = saved;
  }
public:
  static_assert(std::atomic<int>::is_always_lock_free && std::atomic<bool>::is_always_lock_free,
                "signal handler atomics must be lock free");
  explicit ReloadSignal(int fd) {
    struct sigaction action{};
    action.sa_handler = handle;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    descriptor.store(fd, std::memory_order_relaxed);
    if (sigaction(SIGUSR1, &action, &previous)) {
      descriptor.store(-1, std::memory_order_relaxed);
      throw std::runtime_error("cannot install SIGUSR1 config reload handler");
    }
  }
  ReloadSignal(const ReloadSignal &) = delete;
  ReloadSignal &operator=(const ReloadSignal &) = delete;
  ~ReloadSignal() {
    sigaction(SIGUSR1, &previous, nullptr);
    descriptor.store(-1, std::memory_order_relaxed);
    requested.store(false, std::memory_order_relaxed);
  }
  static bool pending() { return requested.load(std::memory_order_relaxed); }
  static bool take() { return requested.exchange(false, std::memory_order_relaxed); }
};
}
