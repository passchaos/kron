#include "foundation/logging/cpp/src/default_formatter.hpp"

#include <chrono>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>

#include <spdlog/details/log_msg.h>
#include <spdlog/pattern_formatter.h>

namespace {

std::string Text(const spdlog::memory_buf_t& buffer) {
  return {buffer.data(), buffer.size()};
}

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

}  // namespace

int main() {
  foundation::logging::detail::DefaultFormatter candidate;
  spdlog::pattern_formatter reference{
      foundation::logging::detail::kDefaultPattern};
  const auto base = spdlog::log_clock::from_time_t(1'790'000'000);
  for (const auto level : {spdlog::level::trace, spdlog::level::info,
                           spdlog::level::warn, spdlog::level::err,
                           spdlog::level::critical}) {
    for (const auto offset : {std::chrono::milliseconds{123},
                              std::chrono::milliseconds{11'987}}) {
      spdlog::details::log_msg message{
          base + offset, {}, "formatter-test", level, "payload value=42"};
      message.thread_id = 123456;
      spdlog::memory_buf_t expected;
      spdlog::memory_buf_t actual;
      reference.format(message, expected);
      candidate.format(message, actual);
      Require(Text(actual) == Text(expected),
              "Foundation default formatter diverged from spdlog");
    }
  }
  for (const auto thread_id : {
           std::size_t{0}, std::numeric_limits<std::size_t>::max()}) {
    spdlog::details::log_msg edge{
        base + std::chrono::milliseconds{999}, {}, "", spdlog::level::off, ""};
    edge.thread_id = thread_id;
    spdlog::memory_buf_t expected_edge;
    spdlog::memory_buf_t actual_edge;
    constexpr std::string_view prefix{"existing-prefix:"};
    expected_edge.append(prefix.begin(), prefix.end());
    actual_edge.append(prefix.begin(), prefix.end());
    reference.format(edge, expected_edge);
    candidate.format(edge, actual_edge);
    Require(Text(actual_edge) == Text(expected_edge),
            "Foundation default formatter diverged on edge values");
  }
  auto clone = candidate.clone();
  spdlog::details::log_msg message{base, {}, "clone", spdlog::level::debug,
                                   "clone payload"};
  message.thread_id = 7;
  spdlog::memory_buf_t expected;
  spdlog::memory_buf_t actual;
  reference.format(message, expected);
  clone->format(message, actual);
  Require(Text(actual) == Text(expected), "formatter clone diverged from spdlog");
}
