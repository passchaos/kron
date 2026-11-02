#include <foundation/logging/failure_signal.hpp>
#include <foundation/logging/runtime.hpp>
#include <foundation/logging/core.h>

#include <chrono>
#include <csignal>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <thread>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {
void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
std::string Read(const std::filesystem::path& path) {
  std::ifstream file(path);
  return {std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
}
void ExternalHandler(int) {}
}

extern "C" __attribute__((noinline)) void FoundationFailureAbortFrame() {
  std::abort();
}
extern "C" __attribute__((noinline)) void FoundationFailureSegvFrame() {
  void* page = mmap(nullptr, 4096, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  Require(page != MAP_FAILED, "mmap failed");
  *static_cast<volatile unsigned char*>(page) = 1;
}

namespace {
void Configure(const std::filesystem::path& root) {
  setenv("FOUNDATION_LOG_DIR", root.c_str(), 1);
  setenv("FOUNDATION_LOG_CONSOLE", "0", 1);
  unsetenv("FOUNDATION_LOG_FAILURE_SIGNAL");
  unsetenv("FOUNDATION_LOG_FAILURE_FILE");
  unsetenv("FOUNDATION_LOG_FAILURE_SIGTERM");
  unsetenv("FOUNDATION_LOG_FAILURE_REPLACE_EXISTING");
  unsetenv("RLOG_REGISTER_FAIL_SIGNAL");
  unsetenv("GLOG_max_log_size");
}

void CheckLifecycle(const std::filesystem::path& root) {
  using namespace foundation::logging;
  Init("default");
  Require(!IsFailureSignalHandlerInstalled(), "Logger runtime silently installed handlers");
  Shutdown();

  foundation_log_failure_signal_config invalid{};
  invalid.struct_size = sizeof(invalid);
  invalid.api_version = FOUNDATION_LOG_FAILURE_SIGNAL_API_VERSION;
  invalid.service_name = "invalid";
  const auto path = (root / "invalid.failure.log").string();
  invalid.report_path = path.c_str();
  invalid.also_stderr = 2;
  Require(foundation_log_install_failure_signal_handler(&invalid) == FOUNDATION_LOG_INVALID_ARGUMENT,
          "invalid C ABI boolean was accepted");
  invalid.also_stderr = 1;
  invalid.struct_size = 4;
  Require(foundation_log_install_failure_signal_handler(&invalid) == FOUNDATION_LOG_INVALID_ARGUMENT,
          "short C ABI config was accepted");
  Require(foundation_log_install_failure_signal_handler(nullptr) == FOUNDATION_LOG_INVALID_ARGUMENT,
          "null C ABI config was accepted");

  struct sigaction original{};
  Require(sigaction(SIGABRT, nullptr, &original) == 0, "cannot read original signal");
  signal(SIGABRT, ExternalHandler);
  FailureSignalOptions options;
  options.service_name = "manual";
  options.report_path = root / "manual.failure.log";
  bool conflict = false;
  try { InstallFailureSignalHandler(options); } catch (const std::runtime_error&) { conflict = true; }
  Require(conflict && !IsFailureSignalHandlerInstalled(), "existing handler was silently replaced");
  options.replace_existing = true;
  InstallFailureSignalHandler(options);
  Require(IsFailureSignalHandlerInstalled(), "C++ installation failed");
  InstallFailureSignalHandler(options);
  UninstallFailureSignalHandler();
  struct sigaction restored{};
  Require(sigaction(SIGABRT, nullptr, &restored) == 0 && restored.sa_handler == ExternalHandler,
          "previous handler was not restored");
  Require(sigaction(SIGABRT, &original, nullptr) == 0, "cannot restore original signal");

  options.service_name = "runtime";
  options.report_path = root / "runtime.failure.log";
  options.replace_existing = false;
  InstallFailureSignalHandler(options);
  setenv("FOUNDATION_LOG_FAILURE_SIGNAL", "yes", 1);
  Init("runtime");
  Shutdown();
  Require(IsFailureSignalHandlerInstalled(), "runtime removed the manually owned installation");
  UninstallFailureSignalHandler();
  Init("runtime");
  Require(IsFailureSignalHandlerInstalled(), "runtime opt-in did not install handlers");
  Shutdown();
  Require(!IsFailureSignalHandlerInstalled(), "runtime did not uninstall its handlers");

  std::filesystem::create_directory(root / "bad.log");
  bool failed = false;
  try { Init("bad"); } catch (const std::exception&) { failed = true; }
  Require(failed && !IsInitialized() && !IsFailureSignalHandlerInstalled(),
          "failed logger initialization leaked signal ownership");

  unsetenv("FOUNDATION_LOG_FAILURE_SIGNAL");
  setenv("RLOG_REGISTER_FAIL_SIGNAL", "true", 1);
  Init("legacy-env");
  Require(IsFailureSignalHandlerInstalled(), "legacy opt-in was ignored");
  Shutdown();
  Require(!IsFailureSignalHandlerInstalled(), "legacy opt-in leaked handlers");
}

int Spawn(const char* executable, const std::filesystem::path& root, const char* mode) {
  const pid_t child = fork();
  Require(child >= 0, "fork failed");
  if (child == 0) {
    const auto path = root / (std::string(mode) + ".stderr");
    const int output = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (output < 0 || dup2(output, STDERR_FILENO) < 0) _exit(126);
    close(output);
    execl(executable, executable, mode, root.c_str(), nullptr);
    _exit(127);
  }
  int status = 0;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
  while (true) {
    const auto result = waitpid(child, &status, WNOHANG);
    Require(result >= 0, "waitpid failed");
    if (result == child) return status;
    if (std::chrono::steady_clock::now() >= deadline) {
      kill(child, SIGKILL);
      waitpid(child, &status, 0);
      throw std::runtime_error("failure signal child hung");
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
}
}

int main(int argc, char** argv) {
  if (argc > 2) {
    const std::filesystem::path root(argv[2]);
    Configure(root);
    const rlimit limit{0, 0};
    Require(setrlimit(RLIMIT_CORE, &limit) == 0, "cannot disable test core dumps");
    const std::string mode(argv[1]);
    if (mode == "lifecycle") { CheckLifecycle(root); return 0; }
    setenv("FOUNDATION_LOG_FAILURE_SIGNAL", "1", 1);
    foundation::logging::Init("cpp-failure");
    SPDLOG_INFO("ordinary asynchronous log before failure");
    if (mode == "abort") FoundationFailureAbortFrame();
    if (mode == "segv") FoundationFailureSegvFrame();
    throw std::runtime_error("unknown child mode");
  }
  const auto root = std::filesystem::temp_directory_path() /
      ("foundation-failure-cpp-" + std::to_string(getpid()));
  std::filesystem::create_directories(root);
  const int lifecycle = Spawn(argv[0], root, "lifecycle");
  if (!WIFEXITED(lifecycle) || WEXITSTATUS(lifecycle) != 0)
    throw std::runtime_error(Read(root / "lifecycle.stderr"));
  for (const auto* mode : {"abort", "segv"}) {
    const auto report_path = root / "cpp-failure.failure.log";
    std::filesystem::remove(report_path);
    const int status = Spawn(argv[0], root, mode);
    const int signal = std::string(mode) == "abort" ? SIGABRT : SIGSEGV;
    Require(WIFSIGNALED(status) && WTERMSIG(status) == signal, "original failure signal was lost");
    const auto report = Read(report_path);
    Require(report.find("service=cpp-failure") != std::string::npos, "service name missing");
    const char* frame = signal == SIGABRT ? "FoundationFailureAbortFrame" : "FoundationFailureSegvFrame";
    Require(report.find(frame) != std::string::npos, "C++ stack frame was not symbolized");
    Require(report.find("*** End Foundation failure report ***") != std::string::npos,
            "report did not complete");
    Require(Read(root / (std::string(mode) + ".stderr")) == report, "stderr report differs");
  }
  std::filesystem::remove_all(root);
}
