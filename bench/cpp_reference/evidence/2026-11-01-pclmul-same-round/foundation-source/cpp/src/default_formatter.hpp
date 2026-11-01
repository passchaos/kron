#pragma once

#include <array>
#include <chrono>
#include <cstring>
#include <ctime>
#include <limits>
#include <memory>
#include <string_view>

#include <spdlog/details/fmt_helper.h>
#include <spdlog/details/log_msg.h>
#include <spdlog/details/os.h>
#include <spdlog/formatter.h>

namespace foundation::logging::detail {

inline constexpr char kDefaultPattern[] =
    "%Y-%m-%dT%H:%M:%S.%e%z [%l] [%n] [thread %t] %v";

class DefaultFormatter final : public spdlog::formatter {
 public:
  DefaultFormatter() = default;

  void format(const spdlog::details::log_msg& message,
              spdlog::memory_buf_t& destination) override {
    using namespace std::chrono;
    const auto seconds_since_epoch =
        duration_cast<seconds>(message.time.time_since_epoch());
    if (seconds_since_epoch != cached_seconds_) {
      cached_seconds_ = seconds_since_epoch;
      const auto time = spdlog::log_clock::to_time_t(message.time);
      cached_time_ = spdlog::details::os::localtime(time);
      FormatDateTime();
    }
    if (message.time - last_offset_update_ >= seconds(10)) {
      last_offset_update_ = message.time;
      FormatOffset(spdlog::details::os::utc_minutes_offset(cached_time_));
    }

    const auto millis =
        spdlog::details::fmt_helper::time_fraction<milliseconds>(message.time);
    const auto level = spdlog::level::to_string_view(message.level);
    std::array<char, std::numeric_limits<std::size_t>::digits10 + 1>
        thread_digits{};
    char* thread_end = thread_digits.data() + thread_digits.size();
    const char* thread_begin = FormatUnsigned(message.thread_id, thread_end);
    const auto thread_size = static_cast<std::size_t>(thread_end - thread_begin);

    constexpr std::string_view kLevelPrefix{" ["};
    constexpr std::string_view kLoggerPrefix{"] ["};
    constexpr std::string_view kThreadPrefix{"] [thread "};
    constexpr std::string_view kPayloadPrefix{"] "};
    const auto appended_size = date_time_size_ + 1 + 3 + offset_.size() +
                               kLevelPrefix.size() + level.size() +
                               kLoggerPrefix.size() + message.logger_name.size() +
                               kThreadPrefix.size() + thread_size +
                               kPayloadPrefix.size() + message.payload.size() + 1;
    const auto original_size = destination.size();
    destination.resize(original_size + appended_size);
    char* output = destination.data() + original_size;
    output = Copy(date_time_.data(), date_time_size_, output);
    *output++ = '.';
    const auto millisecond = static_cast<std::uint32_t>(millis.count());
    *output++ = static_cast<char>('0' + (millisecond / 100) % 10);
    *output++ = static_cast<char>('0' + (millisecond / 10) % 10);
    *output++ = static_cast<char>('0' + millisecond % 10);
    output = Copy(offset_.data(), offset_.size(), output);
    output = Copy(kLevelPrefix.data(), kLevelPrefix.size(), output);
    output = Copy(level.data(), level.size(), output);
    output = Copy(kLoggerPrefix.data(), kLoggerPrefix.size(), output);
    output = Copy(message.logger_name.data(), message.logger_name.size(), output);
    output = Copy(kThreadPrefix.data(), kThreadPrefix.size(), output);
    output = Copy(thread_begin, thread_size, output);
    output = Copy(kPayloadPrefix.data(), kPayloadPrefix.size(), output);
    output = Copy(message.payload.data(), message.payload.size(), output);
    *output = '\n';
  }

  std::unique_ptr<spdlog::formatter> clone() const override {
    return std::make_unique<DefaultFormatter>();
  }

 private:
  static char* Copy(const char* source, std::size_t size, char* destination) {
    if (size != 0) std::memcpy(destination, source, size);
    return destination + size;
  }

  static const char* FormatUnsigned(std::size_t value, char* end) {
    char* output = end;
    do {
      *--output = static_cast<char>('0' + value % 10);
      value /= 10;
    } while (value != 0);
    return output;
  }

  void FormatDateTime() {
    date_time_size_ =
        std::strftime(date_time_.data(), date_time_.size(),
                      "%Y-%m-%dT%H:%M:%S", &cached_time_);
  }

  void FormatOffset(int total_minutes) {
    const bool negative = total_minutes < 0;
    if (negative) total_minutes = -total_minutes;
    offset_[0] = negative ? '-' : '+';
    const auto hours = total_minutes / 60;
    const auto minutes = total_minutes % 60;
    offset_[1] = static_cast<char>('0' + hours / 10);
    offset_[2] = static_cast<char>('0' + hours % 10);
    offset_[3] = ':';
    offset_[4] = static_cast<char>('0' + minutes / 10);
    offset_[5] = static_cast<char>('0' + minutes % 10);
  }

  std::chrono::seconds cached_seconds_{std::chrono::seconds::min()};
  spdlog::log_clock::time_point last_offset_update_{};
  std::tm cached_time_{};
  std::array<char, 32> date_time_{};
  std::size_t date_time_size_{};
  std::array<char, 6> offset_{{'+', '0', '0', ':', '0', '0'}};
};

}  // namespace foundation::logging::detail
