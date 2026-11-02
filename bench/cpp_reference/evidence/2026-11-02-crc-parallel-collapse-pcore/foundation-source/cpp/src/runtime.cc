#include <foundation/logging/runtime.hpp>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdlib>
#include <mutex>
#include <optional>
#include <stdexcept>

namespace foundation::logging {
namespace {
std::shared_ptr<Logger> current;
std::shared_ptr<spdlog::logger> previous_default;
std::shared_ptr<spdlog::logger> previous_named;
std::mutex lifecycle;
bool failure_signal_owned = false;
const char* Value(const char* name) {
  const auto* value = std::getenv(name);
  return value != nullptr && *value != '\0' ? value : nullptr;
}
Level EnvironmentLevel() {
  if (const auto* value = Value("FOUNDATION_LOG_LEVEL")) {
    const std::string text(value);
    if (text == "trace") return Level::kTrace;
    if (text == "debug") return Level::kDebug;
    if (text == "info") return Level::kInfo;
    if (text == "warn" || text == "warning") return Level::kWarn;
    if (text == "error") return Level::kError;
    if (text == "critical" || text == "fatal") return Level::kCritical;
    throw std::invalid_argument("invalid FOUNDATION_LOG_LEVEL");
  }
  const auto* value = Value("GLOG_minloglevel");
  if (value == nullptr) return Level::kInfo;
  const int level = std::stoi(value);
  return level < 0 ? Level::kDebug : level == 0 ? Level::kInfo :
      level == 1 ? Level::kWarn : level == 2 ? Level::kError : Level::kCritical;
}
bool Boolean(const char* value, const char* name) {
  std::string text(value);
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char byte) { return std::tolower(byte); });
  if (text == "1" || text == "true" || text == "yes") return true;
  if (text == "0" || text == "false" || text == "no") return false;
  throw std::invalid_argument(std::string("invalid boolean for ") + name);
}
std::optional<FailureSignalOptions> FailureOptions(const Settings& settings) {
  const auto* enabled = Value("FOUNDATION_LOG_FAILURE_SIGNAL");
  if (enabled == nullptr) enabled = Value("RLOG_REGISTER_FAIL_SIGNAL");
  if (enabled == nullptr || !Boolean(enabled, "FOUNDATION_LOG_FAILURE_SIGNAL"))
    return std::nullopt;
  FailureSignalOptions options;
  options.service_name = settings.logger_name;
  options.report_path = settings.log_directory / (settings.logger_name + ".failure.log");
  if (const auto* file = Value("FOUNDATION_LOG_FAILURE_FILE")) options.report_path = file;
  if (const auto* term = Value("FOUNDATION_LOG_FAILURE_SIGTERM"))
    options.include_sigterm = Boolean(term, "FOUNDATION_LOG_FAILURE_SIGTERM");
  if (const auto* replace = Value("FOUNDATION_LOG_FAILURE_REPLACE_EXISTING"))
    options.replace_existing = Boolean(replace, "FOUNDATION_LOG_FAILURE_REPLACE_EXISTING");
  return options;
}
}  // namespace

void Init(const std::string& name) {
  std::lock_guard<std::mutex> lock(lifecycle);
  if (std::atomic_load(&current)) return;
  Settings settings;
  settings.logger_name = name;
  settings.log_file_name = name + ".log";
  const auto* directory = Value("FOUNDATION_LOG_DIR");
  if (directory == nullptr) directory = Value("GLOG_log_dir");
  if (directory == nullptr) directory = Value("GOOGLE_LOG_DIR");
  if (directory == nullptr) directory = Value("TEST_TMPDIR");
  settings.log_directory = directory ? std::filesystem::path(directory) : std::filesystem::current_path();
  settings.level = EnvironmentLevel();
  settings.block_when_full = false;
  const auto* console = Value("FOUNDATION_LOG_CONSOLE");
  if (console == nullptr) console = Value("GLOG_alsologtostderr");
  settings.console_stdout = true;
  settings.console = console != nullptr && std::string(console) != "0";
  if (const auto* size = Value("GLOG_max_log_size")) {
    const auto megabytes = std::stoull(size);
    if (megabytes == 0 || megabytes > SIZE_MAX / (1024U * 1024U))
      throw std::invalid_argument("invalid GLOG_max_log_size");
    settings.max_file_bytes = megabytes * 1024U * 1024U;
  }
  const auto* mmap = Value("FOUNDATION_LOG_MMAP");
  settings.SetMmapEnabled(mmap != nullptr && std::string(mmap) != "0");
  bool acquired_failure_signal = false;
  if (const auto options = FailureOptions(settings)) {
    acquired_failure_signal = !IsFailureSignalHandlerInstalled();
    InstallFailureSignalHandler(*options);
  }
  try {
    auto logger = std::make_shared<Logger>(std::move(settings));
    previous_default = spdlog::default_logger();
    previous_named = spdlog::get(name);
    spdlog::set_default_logger(logger->NativeShared());
    std::atomic_store(&current, std::move(logger));
    failure_signal_owned = failure_signal_owned || acquired_failure_signal;
  } catch (...) {
    if (acquired_failure_signal) foundation_log_uninstall_failure_signal_handler();
    throw;
  }
}

void Shutdown() noexcept {
  std::lock_guard<std::mutex> lock(lifecycle);
  auto logger = std::atomic_exchange(&current, std::shared_ptr<Logger>{});
  if (failure_signal_owned &&
      foundation_log_uninstall_failure_signal_handler() == FOUNDATION_LOG_OK)
    failure_signal_owned = false;
  if (logger) {
    const auto native = logger->NativeShared();
    if (spdlog::default_logger() == native) spdlog::set_default_logger(previous_default);
    const auto registered = spdlog::get(native->name());
    if (!registered || registered == native) {
      if (registered) spdlog::drop(native->name());
      if (previous_named) spdlog::register_logger(previous_named);
    }
    previous_default.reset();
    previous_named.reset();
    logger->Close();
  }
}

std::shared_ptr<Logger> GetLogger() noexcept { return std::atomic_load(&current); }
bool IsInitialized() noexcept { return static_cast<bool>(GetLogger()); }
void Flush(bool durable) {
  if (auto logger = GetLogger()) logger->Flush(durable);
}
}  // namespace foundation::logging
