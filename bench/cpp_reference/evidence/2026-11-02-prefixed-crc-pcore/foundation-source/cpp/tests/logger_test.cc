#include "foundation/logging/logger.hpp"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <spdlog/logger.h>
#include <spdlog/pattern_formatter.h>

namespace {

class TestDirectory {
 public:
  explicit TestDirectory(const char* name) {
    path_ = std::filesystem::temp_directory_path() /
            (std::string{"foundation-logging-cpp-"} + name + "-" +
             std::to_string(std::chrono::steady_clock::now()
                                .time_since_epoch()
                                .count()));
    std::filesystem::create_directories(path_);
  }

  ~TestDirectory() { std::filesystem::remove_all(path_); }
  const std::filesystem::path& path() const { return path_; }

 private:
  std::filesystem::path path_;
};

std::string Read(const std::filesystem::path& path) {
  std::ifstream stream(path);
  return {std::istreambuf_iterator<char>(stream),
          std::istreambuf_iterator<char>()};
}

void Require(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

foundation::logging::Settings BaseSettings(const TestDirectory& directory,
                                            const char* name) {
  foundation::logging::Settings settings;
  settings.logger_name = name;
  settings.log_directory = directory.path();
  settings.log_file_name = "service.log";
  settings.max_file_bytes = 256U;
  settings.max_files = 3U;
  settings.queue_capacity = 2U;
  settings.write_buffer_bytes = 128U;
  settings.console = false;
  return settings;
}

void ExerciseLogger(foundation::logging::Settings settings) {
  foundation::logging::Logger logger{settings};
  for (const char marker : std::string{"abcde"}) {
    logger.Info(std::string(300U, marker));
  }
  logger.Flush();
  const auto stats = logger.GetStats();
  Require(stats.submitted_records == 5U, "Rust core did not accept all records");
  Require(stats.written_records == 5U, "Rust core did not write all records");
  logger.Close();
  logger.Close();
}

void CheckRotation(const TestDirectory& directory) {
  const auto active = directory.path() / "service.log";
  Require(std::filesystem::exists(active), "active log file is missing");
  Require(std::filesystem::exists(directory.path() / "service.log.1"),
          "newest archive is missing");
  Require(std::filesystem::exists(directory.path() / "service.log.2"),
          "oldest retained archive is missing");
  Require(!std::filesystem::exists(directory.path() / "service.log.3"),
          "too many archives were retained");
  Require(Read(active).find(std::string(32U, 'e')) != std::string::npos,
          "active file does not contain the newest record");
  Require(Read(directory.path() / "service.log.1")
              .find(std::string(32U, 'd')) != std::string::npos,
          "archive order is incorrect");
}

void CheckPatternChanges() {
  TestDirectory directory{"patterns"};
  auto settings = BaseSettings(directory, "pattern-test");
  settings.max_file_bytes = 1024U * 1024U;
  foundation::logging::Logger logger{settings};

  logger.Native().set_pattern("%v");
  logger.Info("plain");
  logger.Native().set_pattern("[%l] %v");
  logger.Warn("pattern");
  logger.Native().set_formatter(
      std::make_unique<spdlog::pattern_formatter>("<%v>"));
  logger.Info("custom");
  logger.Native().set_pattern("%v");
  logger.Info("plain-again");
  logger.Flush();

  Require(Read(directory.path() / "service.log") ==
              "plain\n[warning] pattern\n<custom>\nplain-again\n",
          "pattern or custom formatter update was not preserved");
}

void CheckConcurrentFormatting() {
  TestDirectory directory{"concurrent-formatting"};
  auto settings = BaseSettings(directory, "concurrent-formatting-test");
  settings.max_file_bytes = 16U * 1024U * 1024U;
  settings.queue_capacity = 64U;
  foundation::logging::Logger logger{settings};
  logger.Native().set_pattern("[%t] %v");

  std::vector<std::thread> producers;
  for (std::size_t producer = 0; producer < 8U; ++producer) {
    producers.emplace_back([&logger, producer] {
      for (std::size_t sequence = 0; sequence < 200U; ++sequence) {
        logger.Native().info("producer={} sequence={}", producer, sequence);
      }
    });
  }
  for (auto& producer : producers) {
    producer.join();
  }
  logger.Flush();

  const auto contents = Read(directory.path() / "service.log");
  Require(static_cast<std::size_t>(
              std::count(contents.begin(), contents.end(), '\n')) == 1600U,
          "concurrent spdlog records were lost");
  const auto stats = logger.GetStats();
  Require(stats.submitted_records == 1600U,
          "concurrent spdlog records were not all submitted");
  Require(stats.written_records == 1600U,
          "concurrent spdlog records were not all written");
}

void CheckAlternatingLoggersKeepIndependentFormatters() {
  TestDirectory directory{"alternating-loggers"};
  auto first_settings = BaseSettings(directory, "first-logger");
  first_settings.log_file_name = "first.log";
  first_settings.max_file_bytes = 1024U * 1024U;
  auto second_settings = BaseSettings(directory, "second-logger");
  second_settings.log_file_name = "second.log";
  second_settings.max_file_bytes = 1024U * 1024U;
  foundation::logging::Logger first{first_settings};
  foundation::logging::Logger second{second_settings};
  first.Native().set_pattern("first:%v");
  second.Native().set_pattern("second:%v");
  for (int sequence = 0; sequence < 32; ++sequence) {
    first.Native().info("{}", sequence);
    second.Native().info("{}", sequence);
  }
  first.Native().set_pattern("updated:%v");
  first.Info("done");
  first.Flush();
  second.Flush();
  const auto first_output = Read(directory.path() / "first.log");
  const auto second_output = Read(directory.path() / "second.log");
  Require(first_output.find("first:31\n") != std::string::npos,
          "first formatter was lost while alternating loggers");
  const std::string updated{"updated:done\n"};
  Require(first_output.size() >= updated.size() &&
              first_output.compare(first_output.size() - updated.size(),
                                   updated.size(), updated) == 0,
          "formatter generation update missed the TLS fast cache");
  Require(second_output.find("second:31\n") != std::string::npos,
          "second formatter was lost while alternating loggers");
}

void CheckQueueByteCapacity() {
  TestDirectory directory{"queue-byte-capacity"};
  auto settings = BaseSettings(directory, "queue-byte-capacity-test");
  settings.max_file_bytes = 1024U * 1024U;
  settings.queue_capacity_bytes = 4U;
  foundation::logging::Logger logger{settings};
  logger.Native().set_pattern("%v");
  bool oversized_rejected = false;
  logger.Native().set_error_handler(
      [&oversized_rejected](const std::string&) { oversized_rejected = true; });
  logger.Info("1234");
  Require(!oversized_rejected, "native oversized record reached the error handler");
  logger.Info("123");
  logger.Flush();
  Require(Read(directory.path() / "service.log") == "...\n123\n",
          "oversized marker or exact byte-capacity record was not written");
}

}  // namespace

int main() {
  TestDirectory memory_directory{"memory"};
  ExerciseLogger(BaseSettings(memory_directory, "memory-test"));
  CheckRotation(memory_directory);

  TestDirectory mmap_directory{"mmap"};
  auto mmap_settings = BaseSettings(mmap_directory, "mmap-test");
  mmap_settings.backend_mode = foundation::logging::BackendMode::kMmap;
  mmap_settings.mmap_spool_path = mmap_directory.path() / "service.spool";
  mmap_settings.mmap_capacity_bytes = 4096U + 8U * 1024U;
  mmap_settings.mmap_slot_bytes = 1024U;
  ExerciseLogger(mmap_settings);
  CheckRotation(mmap_directory);

  CheckPatternChanges();
  CheckConcurrentFormatting();
  CheckAlternatingLoggersKeepIndependentFormatters();
  CheckQueueByteCapacity();
  return 0;
}
