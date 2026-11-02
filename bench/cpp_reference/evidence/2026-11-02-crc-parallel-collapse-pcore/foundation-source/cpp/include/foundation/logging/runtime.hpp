#pragma once

#include <memory>
#include <string>
#include <foundation/logging/logger.hpp>
#include <foundation/logging/failure_signal.hpp>
#include <spdlog/spdlog.h>

namespace foundation::logging {
// The application owns initialization before workers and shutdown after join.
// Do not call logging between fork and exec or from a signal handler.
void Init(const std::string& name);
void Shutdown() noexcept;
bool IsInitialized() noexcept;
std::shared_ptr<Logger> GetLogger() noexcept;
void Flush(bool durable = false);

class Session {
 public:
  explicit Session(const std::string& name) : owned_(!IsInitialized()) {
    if (owned_) Init(name);
  }
  ~Session() { if (owned_) Shutdown(); }
  Session(const Session&) = delete;
  Session& operator=(const Session&) = delete;
 private:
  bool owned_;
};
}  // namespace foundation::logging
