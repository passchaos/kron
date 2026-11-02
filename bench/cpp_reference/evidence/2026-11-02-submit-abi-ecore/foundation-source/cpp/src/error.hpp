#pragma once

#include <string>
#include "foundation/logging/core.h"

namespace foundation::logging::detail {
inline std::string CoreError(int status) {
  const char* message = foundation_log_last_error_message();
  return "Rust logging core error " + std::to_string(status) + ": " +
         (message == nullptr ? "unknown error" : message);
}
}  // namespace foundation::logging::detail
