#pragma once

#include <memory>
#include <string_view>

#include "foundation/logging/types.hpp"

namespace spdlog { class logger; }

namespace foundation::logging {
// The spdlog call path formats synchronously, then submits the completed record
// to the Rust backend. The backend owns the only asynchronous queue.
class Logger {
 public:
  explicit Logger(Settings settings);
  ~Logger();

  Logger(const Logger&) = delete;
  Logger& operator=(const Logger&) = delete;
  Logger(Logger&&) noexcept;
  Logger& operator=(Logger&&) noexcept;

  void Log(Level level, std::string_view message);
  void Trace(std::string_view message);
  void Debug(std::string_view message);
  void Info(std::string_view message);
  void Warn(std::string_view message);
  void Error(std::string_view message);
  void Critical(std::string_view message);

  void SetLevel(Level level);
  bool ShouldLog(Level level) const;
  void Flush(bool durable = false);
  Stats GetStats() const;
  void Close() noexcept;

  std::shared_ptr<spdlog::logger> NativeShared();
  spdlog::logger& Native();
  const spdlog::logger& Native() const;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace foundation::logging
