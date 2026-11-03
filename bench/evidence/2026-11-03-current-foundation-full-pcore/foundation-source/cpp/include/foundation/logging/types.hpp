#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>

#include "foundation/logging/core.h"

namespace foundation::logging {
inline constexpr std::size_t kDefaultMaxFileBytes = 100U * 1024U * 1024U;
inline constexpr std::size_t kDefaultMaxFiles = 10U;
inline constexpr std::size_t kDefaultQueueCapacity = 8192U;
inline constexpr std::size_t kDefaultQueueCapacityBytes =
    100U * 1024U * 1024U;
inline constexpr std::size_t kDefaultCriticalReserveRecords = 32U;
inline constexpr std::size_t kDefaultCriticalReserveBytes = 256U * 1024U;
inline constexpr std::size_t kDefaultWriteBufferBytes = 256U * 1024U;
inline constexpr std::size_t kDefaultMmapCapacityBytes = 64U * 1024U * 1024U;
inline constexpr std::size_t kDefaultMmapSlotBytes = 8U * 1024U;

enum class Level {
  kTrace,
  kDebug,
  kInfo,
  kWarn,
  kError,
  kCritical,
  kOff,
};

enum class BackendMode {
  kMemory,
  kMmap,
};

struct Settings {
  std::string logger_name;
  std::filesystem::path log_directory;
  std::string log_file_name;
  Level level{Level::kInfo};
  std::size_t max_file_bytes{kDefaultMaxFileBytes};
  std::size_t max_files{kDefaultMaxFiles};
  std::size_t queue_capacity{kDefaultQueueCapacity};
  std::size_t queue_capacity_bytes{kDefaultQueueCapacityBytes};
  std::size_t critical_reserve_records{kDefaultCriticalReserveRecords};
  std::size_t critical_reserve_bytes{kDefaultCriticalReserveBytes};
  std::size_t write_buffer_bytes{kDefaultWriteBufferBytes};
  // False discards new native log records at capacity; accepted records remain.
  bool block_when_full{true};
  bool console{true};
  bool console_stdout{false};
  BackendMode backend_mode{BackendMode::kMemory};
  std::filesystem::path mmap_spool_path;
  std::size_t mmap_capacity_bytes{kDefaultMmapCapacityBytes};
  std::size_t mmap_slot_bytes{kDefaultMmapSlotBytes};

  // Configure before constructing Logger. Fresh settings use one globally
  // ordered mmap spool; explicit mmap dimensions remain configurable.
  void SetMmapEnabled(bool enabled) noexcept {
    backend_mode = enabled ? BackendMode::kMmap : BackendMode::kMemory;
  }

  Settings WithMmapEnabled(bool enabled) const {
    auto settings = *this;
    settings.SetMmapEnabled(enabled);
    return settings;
  }

  bool IsMmapEnabled() const noexcept {
    return backend_mode == BackendMode::kMmap;
  }
};

struct Stats {
  std::uint64_t submitted_records{};
  std::uint64_t submitted_bytes{};
  std::uint64_t written_records{};
  std::uint64_t written_bytes{};
  std::uint64_t recovered_records{};
  std::uint64_t queue_full_count{};
  std::uint64_t write_error_count{};
};

}  // namespace foundation::logging
