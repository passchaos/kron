#include <foundation/logging/runtime.hpp>
#include <foundation/logging/rate_limit.hpp>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/null_sink.h>
#include <cassert>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <thread>
#include <vector>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char** argv) {
  if (argc > 1) {
    foundation::logging::Init("fatal");
    SPDLOG_CRITICAL("Check failed: false fatal evidence");
    foundation::logging::Flush(true);
    std::abort();
  }
  const auto directory = std::filesystem::temp_directory_path() /
      ("foundation-runtime-" + std::to_string(getpid()));
  setenv("FOUNDATION_LOG_DIR", directory.c_str(), 1);
  setenv("FOUNDATION_LOG_CONSOLE", "0", 1);
  unsetenv("FOUNDATION_LOG_LEVEL");
  const auto previous = spdlog::default_logger();
  auto shadow = std::make_shared<spdlog::logger>("runtime", std::make_shared<spdlog::sinks::null_sink_mt>());
  spdlog::register_logger(shadow);
  foundation::logging::Init("runtime");
  const auto native = foundation::logging::GetLogger()->NativeShared();
  assert(spdlog::default_logger() == native);
  assert(spdlog::get("runtime") == native);
  int evaluated = 0;
  SPDLOG_DEBUG("runtime filtered {}", ++evaluated);
#if SPDLOG_ACTIVE_LEVEL <= SPDLOG_LEVEL_DEBUG
  assert(evaluated == 1);
#else
  assert(evaluated == 0);
#endif
  const int compiled_evaluations = evaluated;
  if (spdlog::should_log(spdlog::level::debug)) SPDLOG_DEBUG("guarded {}", ++evaluated);
  assert(evaluated == compiled_evaluations);
  if (true) SPDLOG_INFO("unbraced branch");
  else SPDLOG_ERROR("unexpected branch");
  spdlog::info("default API value={} string={}", 42, "native");
  native->set_pattern("%s:%# %v");
  SPDLOG_INFO("macro source metadata");
  std::vector<std::thread> threads;
  std::atomic<std::uint64_t> occurrences{0};
  for (int i = 0; i < 4; ++i) threads.emplace_back([&] {
    for (int j = 0; j < 100; ++j)
      if (foundation::logging::EveryN(occurrences, 10)) SPDLOG_INFO("rate limited");
  });
  for (auto& thread : threads) thread.join();
  foundation::logging::Shutdown();
  assert(!foundation::logging::IsInitialized());
  assert(spdlog::default_logger() == previous);
  assert(spdlog::get("runtime") == shadow);
  spdlog::drop("runtime");
  foundation::logging::Init("temporary-default");
  auto external = std::make_shared<spdlog::logger>("external-default", std::make_shared<spdlog::sinks::null_sink_mt>());
  spdlog::set_default_logger(external);
  foundation::logging::Shutdown();
  assert(spdlog::default_logger() == external);
  spdlog::set_default_logger(previous);
  spdlog::drop("external-default");
  std::ifstream file(directory / "runtime.log");
  const std::string output((std::istreambuf_iterator<char>(file)), {});
  assert(output.find("unbraced branch") != std::string::npos);
  assert(output.find("unexpected branch") == std::string::npos);
  assert(output.find("default API value=42 string=native") != std::string::npos);
  assert(output.find("runtime_test.cc:") != std::string::npos);
  assert(output.find("runtime filtered") == std::string::npos);
  std::size_t found = 0, count = 0;
  while ((found = output.find("rate limited", found)) != std::string::npos) { ++found; ++count; }
  assert(count == 40);
  const auto child = fork();
  if (child < 0) return 1;
  if (child == 0) { execl(argv[0], argv[0], "--fatal", nullptr); _exit(127); }
  int status = 0;
  if (waitpid(child, &status, 0) != child || !WIFSIGNALED(status) ||
      WTERMSIG(status) != SIGABRT) {
    return 1;
  }
  std::ifstream fatal_file(directory / "fatal.log");
  const std::string fatal((std::istreambuf_iterator<char>(fatal_file)), {});
  assert(fatal.find("fatal evidence") != std::string::npos);
  std::filesystem::remove_all(directory);
}
