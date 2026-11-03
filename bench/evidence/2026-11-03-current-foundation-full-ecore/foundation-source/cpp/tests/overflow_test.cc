#include "foundation/logging/logger.hpp"

#include <spdlog/logger.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <thread>

#ifdef __linux__
#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

std::string ReadRecord(int descriptor) {
  std::string bytes;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds{5};
  while (bytes.find('\n') == std::string::npos) {
    char buffer[4096];
    const auto count = read(descriptor, buffer, sizeof(buffer));
    if (count > 0) {
      bytes.append(buffer, static_cast<std::size_t>(count));
    } else {
      Require(count < 0 && errno == EAGAIN, "proxy read failed");
      Require(std::chrono::steady_clock::now() < deadline, "record output timed out");
      std::this_thread::sleep_for(std::chrono::milliseconds{1});
    }
  }
  return bytes;
}

void RunCase(const std::filesystem::path& root, bool mmap) {
  const auto output = root / "app.log";
  Require(mkfifo(output.c_str(), 0600) == 0, "mkfifo failed");
  const int proxy = open(output.c_str(), O_RDWR | O_NONBLOCK);
  Require(proxy >= 0, "proxy open failed");
  Require(fcntl(proxy, F_SETPIPE_SZ, 4096) == 4096, "pipe resize failed");
  foundation::logging::Settings settings;
  settings.logger_name = "overflow";
  settings.log_directory = root;
  settings.log_file_name = "app.log";
  settings.console = false;
  settings.queue_capacity = 1;
  settings.queue_capacity_bytes = 32U * 1024U;
  settings.write_buffer_bytes = 1;
  settings.block_when_full = false;
  settings.SetMmapEnabled(mmap);
  settings.mmap_capacity_bytes = 4096U + 16U * 1024U;
  settings.mmap_slot_bytes = 16U * 1024U;
  foundation::logging::Logger logger{settings};
  std::size_t errors = 0;
  logger.Native().set_error_handler([&errors](const std::string&) { ++errors; });
  const std::string retained(8192, 'a');
  logger.Info(retained);
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds{5};
  for (;;) {
    int queued = 0;
    Require(ioctl(proxy, FIONREAD, &queued) == 0, "proxy inspection failed");
    if (queued == 4096) break;
    Require(std::chrono::steady_clock::now() < deadline, "writer did not fill proxy");
    std::this_thread::sleep_for(std::chrono::milliseconds{1});
  }
  for (int i = 0; i < 3; ++i) logger.Native().info("discard-me");
  const auto expected_drops = 3U;
  const auto stats = logger.GetStats();
  Require(errors == 0, "expected overflow reached spdlog error handler");
  Require(stats.submitted_records == 1, "overflow records were accepted");
  Require(stats.queue_full_count == expected_drops, "drop count is incorrect");
  Require(stats.write_error_count == 0, "overflow became an output failure");
  const auto first = ReadRecord(proxy);
  Require(first.find(retained) != std::string::npos, "accepted record was overwritten");
  Require(std::count(first.begin(), first.end(), '\n') == 1, "unexpected output records");
  logger.Flush();
  logger.Native().info("resumed");
  logger.Flush();
  const auto second = ReadRecord(proxy);
  Require(second.find("resumed") != std::string::npos, "logging did not resume");
  Require(second.find("discard") == std::string::npos, "dropped record reached output");
  Require(logger.GetStats().written_records == 2, "output count is incorrect");
  logger.Close();
  close(proxy);
}

}  // namespace
#endif

int main() {
#ifdef __linux__
  for (const bool mmap : {false, true}) {
    const auto root = std::filesystem::temp_directory_path() /
        ("foundation-overflow-cpp-" + std::to_string(getpid()) +
         (mmap ? "-mmap" : "-memory"));
    std::filesystem::create_directories(root);
    // Isolate a stalled writer so even a regression cannot hang the test runner.
    const auto child = fork();
    Require(child >= 0, "fork failed");
    if (child == 0) {
      try { RunCase(root, mmap); }
      catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        _exit(1);
      }
      _exit(0);
    }
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds{10};
    int status = 0;
    for (;;) {
      const auto waited = waitpid(child, &status, WNOHANG);
      Require(waited >= 0, "waitpid failed");
      if (waited == child) break;
      if (std::chrono::steady_clock::now() >= deadline) {
        kill(child, SIGKILL);
        waitpid(child, &status, 0);
        break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds{1});
    }
    std::filesystem::remove_all(root);
    Require(WIFEXITED(status) && WEXITSTATUS(status) == 0, "overflow child failed");
  }
#endif
}
