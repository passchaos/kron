#pragma once

#include <filesystem>
#include <string>

namespace foundation::logging {

struct FailureSignalOptions {
  std::string service_name;
  std::filesystem::path report_path;
  bool also_stderr{true};
  bool include_sigterm{false};
  bool replace_existing{false};
};

// Explicit process-wide lifecycle: install before workers, uninstall after
// join and before unloading Foundation. Identical options are idempotent.
// Logger construction/Close do not alter signal handlers. Existing handlers
// require replace_existing=true; removal preserves later external changes.
void InstallFailureSignalHandler(const FailureSignalOptions& options);
void UninstallFailureSignalHandler();
bool IsFailureSignalHandlerInstalled();

}  // namespace foundation::logging
