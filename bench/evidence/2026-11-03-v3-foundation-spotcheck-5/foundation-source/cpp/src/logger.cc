#include "foundation/logging/logger.hpp"

#include <atomic>
#include <limits>
#include <mutex>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

#include <spdlog/logger.h>
#include <spdlog/pattern_formatter.h>
#include <spdlog/sinks/sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/spdlog.h>

#include "foundation/logging/core.h"
#include "default_formatter.hpp"
#include "error.hpp"

namespace foundation::logging {
namespace {
using detail::CoreError;

spdlog::level::level_enum ToSpdlogLevel(Level level) {
  switch (level) {
    case Level::kTrace:
      return spdlog::level::trace;
    case Level::kDebug:
      return spdlog::level::debug;
    case Level::kInfo:
      return spdlog::level::info;
    case Level::kWarn:
      return spdlog::level::warn;
    case Level::kError:
      return spdlog::level::err;
    case Level::kCritical:
      return spdlog::level::critical;
    case Level::kOff:
      return spdlog::level::off;
  }
  return spdlog::level::info;
}

std::uint32_t CheckedU32(std::size_t value, const char* name) {
  if (value > std::numeric_limits<std::uint32_t>::max()) {
    throw std::invalid_argument(std::string{name} + " exceeds uint32 range");
  }
  return static_cast<std::uint32_t>(value);
}

class CoreSink final : public spdlog::sinks::sink {
 public:
  explicit CoreSink(const Settings& settings)
      : id_(NextId()), formatter_(std::make_unique<detail::DefaultFormatter>()) {
    const auto directory = settings.log_directory.string();
    const auto spool_path =
        (settings.mmap_spool_path.empty()
             ? settings.log_directory / (settings.log_file_name + ".spool")
             : settings.mmap_spool_path)
            .string();
    foundation_log_config config{};
    config.struct_size = sizeof(config);
    config.api_version = FOUNDATION_LOG_API_VERSION;
    config.log_directory = directory.c_str();
    config.log_file_name = settings.log_file_name.c_str();
    config.max_file_bytes = settings.max_file_bytes;
    config.max_files = CheckedU32(settings.max_files, "max_files");
    config.queue_capacity =
        CheckedU32(settings.queue_capacity, "queue_capacity");
    config.queue_capacity_bytes = settings.queue_capacity_bytes;
    config.critical_reserve_records =
        CheckedU32(settings.critical_reserve_records,
                   "critical_reserve_records");
    config.critical_reserve_bytes = settings.critical_reserve_bytes;
    config.write_buffer_bytes =
        CheckedU32(settings.write_buffer_bytes, "write_buffer_bytes");
    config.block_when_full = settings.block_when_full ? 1U : 0U;
    config.mode = settings.backend_mode == BackendMode::kMmap
                      ? FOUNDATION_LOG_MODE_MMAP
                      : FOUNDATION_LOG_MODE_MEMORY;
    config.mmap_spool_path = spool_path.c_str();
    config.mmap_capacity_bytes = settings.mmap_capacity_bytes;
    config.mmap_slot_bytes =
        CheckedU32(settings.mmap_slot_bytes, "mmap_slot_bytes");
    config.extension_version = 7U;
    config.extension_version_v4 = 4U;
    config.extension_version_v5 = 5U;
    config.extension_version_v6 = 6U;
    config.extension_version_v7 = 7U;
    const int status = foundation_log_open(&config, &handle_);
    if (status != FOUNDATION_LOG_OK) {
      throw std::runtime_error(CoreError(status));
    }
  }

  ~CoreSink() override { foundation_log_close(handle_); }

  void log(const spdlog::details::log_msg& message) override {
    spdlog::memory_buf_t formatted;
    auto& state = StateForCurrentThread();
    state.formatter->format(message, formatted);
    const auto priority = message.level >= spdlog::level::err
                              ? FOUNDATION_LOG_PRIORITY_CRITICAL
                              : FOUNDATION_LOG_PRIORITY_NORMAL;
    const int status = foundation_log_submit_native(
        handle_, formatted.data(), formatted.size(), priority);
    if (status != FOUNDATION_LOG_OK && status != FOUNDATION_LOG_QUEUE_FULL) {
      throw spdlog::spdlog_ex(CoreError(status));
    }
  }

  void flush() override { Flush(false); }

  void set_pattern(const std::string& pattern) override {
    if (pattern == detail::kDefaultPattern) {
      InstallFormatter(std::make_unique<detail::DefaultFormatter>());
    } else {
      InstallFormatter(std::make_unique<spdlog::pattern_formatter>(pattern));
    }
  }

  void set_formatter(
      std::unique_ptr<spdlog::formatter> formatter) override {
    if (!formatter) {
      throw std::invalid_argument("spdlog formatter must not be null");
    }
    InstallFormatter(std::move(formatter));
  }

  Stats GetStats() const {
    foundation_log_stats_v2 stats{};
    stats.struct_size = sizeof(stats);
    const int status = foundation_log_get_stats_v2(handle_, &stats);
    if (status != FOUNDATION_LOG_OK) {
      throw std::runtime_error(CoreError(status));
    }
    return {
        stats.submitted_records,
        stats.submitted_bytes,
        stats.written_records,
        stats.written_bytes,
        stats.recovered_records,
        stats.queue_full_count,
        stats.write_error_count,
    };
  }

  void Flush(bool durable) {
    const int status = foundation_log_flush(handle_, durable ? 1U : 0U);
    if (status != FOUNDATION_LOG_OK) {
      throw std::runtime_error(CoreError(status));
    }
  }

 private:
  struct ThreadState {
    std::uint64_t generation{};
    std::unique_ptr<spdlog::formatter> formatter;
  };

  struct ThreadCache {
    std::uint64_t last_id{};
    ThreadState* last_state{};
    std::unordered_map<std::uint64_t, ThreadState> states;
  };

  static std::uint64_t NextId() {
    static std::atomic<std::uint64_t> next_id{1U};
    return next_id.fetch_add(1U, std::memory_order_relaxed);
  }

  void InstallFormatter(std::unique_ptr<spdlog::formatter> formatter) {
    {
      std::lock_guard<std::mutex> lock{formatter_mutex_};
      formatter_ = std::move(formatter);
    }
    formatter_generation_.fetch_add(1U, std::memory_order_release);
  }

  ThreadState& StateForCurrentThread() {
    static thread_local ThreadCache cache;
    ThreadState* state = cache.last_id == id_ ? cache.last_state : nullptr;
    if (state == nullptr) {
      state = &cache.states[id_];
      cache.last_id = id_;
      cache.last_state = state;
    }
    const auto generation =
        formatter_generation_.load(std::memory_order_acquire);
    if (!state->formatter || state->generation != generation) {
      std::lock_guard<std::mutex> lock{formatter_mutex_};
      state->formatter = formatter_->clone();
      state->generation =
          formatter_generation_.load(std::memory_order_relaxed);
    }
    return *state;
  }

  foundation_log_handle* handle_{nullptr};
  const std::uint64_t id_;
  std::atomic<std::uint64_t> formatter_generation_{1U};
  std::mutex formatter_mutex_;
  std::unique_ptr<spdlog::formatter> formatter_;
};

}  // namespace

class Logger::Impl {
 public:
  explicit Impl(Settings settings) {
    if (settings.logger_name.empty()) {
      throw std::invalid_argument("logger_name must not be empty");
    }
    core_sink_ = std::make_shared<CoreSink>(settings);
    std::vector<spdlog::sink_ptr> sinks{core_sink_};
    if (settings.console) {
      spdlog::sink_ptr console;
      if (settings.console_stdout) {
        console = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
      } else {
        console = std::make_shared<spdlog::sinks::stderr_color_sink_mt>();
      }
      console->set_pattern(detail::kDefaultPattern);
      sinks.push_back(std::move(console));
    }
    logger_ = std::make_shared<spdlog::logger>(
        std::move(settings.logger_name), sinks.begin(), sinks.end());
    logger_->set_level(ToSpdlogLevel(settings.level));
  }

  ~Impl() { Close(); }

  void Close() noexcept {
    if (!logger_) {
      return;
    }
    try {
      logger_->flush();
    } catch (...) {
    }
    logger_.reset();
    core_sink_.reset();
  }

  std::shared_ptr<spdlog::logger> Share() {
    if (!logger_) throw std::logic_error("logger is already closed");
    return logger_;
  }

  spdlog::logger& Get() {
    if (!logger_) {
      throw std::logic_error("logger is already closed");
    }
    return *logger_;
  }

  const spdlog::logger& Get() const {
    if (!logger_) {
      throw std::logic_error("logger is already closed");
    }
    return *logger_;
  }

  void Flush(bool durable) {
    if (!core_sink_) {
      throw std::logic_error("logger is already closed");
    }
    core_sink_->Flush(durable);
  }

  Stats GetStats() const {
    if (!core_sink_) {
      throw std::logic_error("logger is already closed");
    }
    return core_sink_->GetStats();
  }

 private:
  std::shared_ptr<CoreSink> core_sink_;
  std::shared_ptr<spdlog::logger> logger_;
};

Logger::Logger(Settings settings)
    : impl_(std::make_unique<Impl>(std::move(settings))) {}

Logger::~Logger() = default;
Logger::Logger(Logger&&) noexcept = default;
Logger& Logger::operator=(Logger&&) noexcept = default;

void Logger::Log(Level level, std::string_view message) {
  Native().log(ToSpdlogLevel(level),
               spdlog::string_view_t{message.data(), message.size()});
}

void Logger::Trace(std::string_view message) { Log(Level::kTrace, message); }
void Logger::Debug(std::string_view message) { Log(Level::kDebug, message); }
void Logger::Info(std::string_view message) { Log(Level::kInfo, message); }
void Logger::Warn(std::string_view message) { Log(Level::kWarn, message); }
void Logger::Error(std::string_view message) { Log(Level::kError, message); }
void Logger::Critical(std::string_view message) {
  Log(Level::kCritical, message);
}

void Logger::SetLevel(Level level) {
  Native().set_level(ToSpdlogLevel(level));
}

bool Logger::ShouldLog(Level level) const {
  return Native().should_log(ToSpdlogLevel(level));
}

void Logger::Flush(bool durable) { impl_->Flush(durable); }
Stats Logger::GetStats() const { return impl_->GetStats(); }
void Logger::Close() noexcept {
  if (impl_) {
    impl_->Close();
  }
}

std::shared_ptr<spdlog::logger> Logger::NativeShared() { return impl_->Share(); }

spdlog::logger& Logger::Native() {
  if (!impl_) {
    throw std::logic_error("logger has been moved from");
  }
  return impl_->Get();
}

const spdlog::logger& Logger::Native() const {
  if (!impl_) {
    throw std::logic_error("logger has been moved from");
  }
  return impl_->Get();
}

}  // namespace foundation::logging
