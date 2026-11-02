#include "foundation/logging/logger.hpp"

#include <chrono>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace {
void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

struct Directory {
  std::filesystem::path path = std::filesystem::temp_directory_path() /
      ("foundation-mmap-switch-" + std::to_string(
          std::chrono::steady_clock::now().time_since_epoch().count()));
  Directory() { std::filesystem::create_directories(path); }
  ~Directory() { std::filesystem::remove_all(path); }
};
}

int main() {
  Directory directory;
  foundation::logging::Settings settings;
  settings.logger_name = "switch";
  settings.log_directory = directory.path;
  settings.log_file_name = "enabled.log";
  settings.console = false;
  Require(!settings.IsMmapEnabled(), "mmap should be disabled by default");
  settings.SetMmapEnabled(true);
  Require(settings.IsMmapEnabled(), "mmap switch did not enable the backend");
  {
    foundation::logging::Logger logger{settings};
    logger.Info("enabled");
    logger.Flush();
    Require(logger.GetStats().written_records == 1, "mmap did not write the record");
  }
  Require(std::filesystem::exists(directory.path / "enabled.log.spool"),
          "mmap spool was not created");
  auto disabled = settings.WithMmapEnabled(false);
  Require(settings.IsMmapEnabled() && !disabled.IsMmapEnabled(),
          "WithMmapEnabled must return a separate settings value");
  disabled.log_file_name = "disabled.log";
  {
    foundation::logging::Logger logger{disabled};
    logger.Info("disabled");
    logger.Flush();
    Require(logger.GetStats().written_records == 1, "Memory did not write the record");
  }
  Require(!std::filesystem::exists(directory.path / "disabled.log.spool"),
          "disabled mmap created a spool");

  const auto log_directory = directory.path.string();
  const auto spool = (directory.path / "c-api.spool").string();
  foundation_log_config config{};
  config.struct_size = sizeof(config);
  config.api_version = FOUNDATION_LOG_API_VERSION;
  config.log_directory = log_directory.c_str();
  config.log_file_name = "c-api.log";
  config.max_file_bytes = 1024 * 1024;
  config.max_files = 2;
  config.queue_capacity = 8;
  config.queue_capacity_bytes = 1024;
  config.write_buffer_bytes = 256;
  config.block_when_full = 1;
  config.mmap_spool_path = spool.c_str();
  config.mmap_capacity_bytes = 4096 + 8 * 512;
  config.mmap_slot_bytes = 512;
  config.extension_version = 6;
  config.extension_version_v4 = 4;
  config.extension_version_v5 = 5;
  config.extension_version_v6 = 6;
  foundation_log_config_set_mmap_enabled(&config, 1);
  foundation_log_handle* handle = nullptr;
  Require(foundation_log_open(&config, &handle) == FOUNDATION_LOG_OK,
          "C API mmap switch failed to open");
  Require(foundation_log_submit(handle, "c record\n", 9) == FOUNDATION_LOG_OK,
          "C API mmap failed to submit");
  Require(foundation_log_flush(handle, 0) == FOUNDATION_LOG_OK, "C API flush failed");
  foundation_log_close(handle);
  Require(std::filesystem::exists(spool), "C API mmap did not create its spool");
  foundation_log_config_set_mmap_enabled(&config, 0);
  Require(config.mode == FOUNDATION_LOG_MODE_MEMORY,
          "C API switch did not select Memory");
  Require(foundation_log_open(&config, &handle) == FOUNDATION_LOG_OK,
          "C API Memory switch failed to open");
  foundation_log_close(handle);
  return 0;
}
