#include <foundation/logging/failure_signal.hpp>

#include <stdexcept>

#include "foundation/logging/core.h"
#include "error.hpp"

namespace foundation::logging {

void InstallFailureSignalHandler(const FailureSignalOptions& options) {
  const auto path = options.report_path.string();
  if (options.service_name.find('\0') != std::string::npos ||
      path.find('\0') != std::string::npos) {
    throw std::invalid_argument("failure signal strings must not contain NUL");
  }
  foundation_log_failure_signal_config config{};
  config.struct_size = sizeof(config);
  config.api_version = FOUNDATION_LOG_FAILURE_SIGNAL_API_VERSION;
  config.service_name = options.service_name.c_str();
  config.report_path = path.c_str();
  config.also_stderr = options.also_stderr;
  config.include_sigterm = options.include_sigterm;
  config.replace_existing = options.replace_existing;
  const int status = foundation_log_install_failure_signal_handler(&config);
  if (status != FOUNDATION_LOG_OK) throw std::runtime_error(detail::CoreError(status));
}

void UninstallFailureSignalHandler() {
  const int status = foundation_log_uninstall_failure_signal_handler();
  if (status != FOUNDATION_LOG_OK) throw std::runtime_error(detail::CoreError(status));
}

bool IsFailureSignalHandlerInstalled() {
  return foundation_log_failure_signal_handler_installed() != 0;
}

}  // namespace foundation::logging
