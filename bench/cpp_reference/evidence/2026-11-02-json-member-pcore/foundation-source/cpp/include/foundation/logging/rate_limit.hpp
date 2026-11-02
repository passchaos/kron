#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>

namespace foundation::logging {
inline bool EveryN(std::atomic<std::uint64_t>& count, std::uint64_t n) {
  return n > 0 && count.fetch_add(1, std::memory_order_relaxed) % n == 0;
}
inline bool EveryMilliseconds(std::atomic<std::int64_t>& previous, std::int64_t interval) {
  if (interval <= 0) return true;
  const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count();
  auto old = previous.load(std::memory_order_relaxed);
  while (old == 0 || now - old >= interval) {
    if (previous.compare_exchange_weak(old, now, std::memory_order_relaxed)) return true;
  }
  return false;
}
}
