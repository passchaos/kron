// Bounded file-output comparison. Both variants use identical JSON payloads.
// LIB_SPDLOG captures preformatted bytes; LIB_QUILL also supports deferred fmt.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <exception>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <memory>
#include <mutex>
#include <numeric>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>
#include <sys/resource.h>
#include <time.h>

#if defined(LIB_SPDLOG)
#include <spdlog/async_logger.h>
#include <spdlog/details/thread_pool.h>
#include <spdlog/sinks/base_sink.h>
#include <spdlog/version.h>
#elif defined(LIB_QUILL)
#include <quill/Backend.h>
#include <quill/Frontend.h>
#include <quill/LogMacros.h>
#include <quill/Logger.h>
#include <quill/sinks/FileSink.h>
#elif defined(LIB_FOUNDATION)
#include <foundation/logging/logger.hpp>
#include <spdlog/logger.h>
#include <spdlog/formatter.h>
#endif

namespace {
uint64_t awake() {
  timespec value{};
  if (::clock_gettime(CLOCK_MONOTONIC, &value)) throw std::runtime_error("clock_gettime");
  return uint64_t(value.tv_sec) * 1000000000 + uint64_t(value.tv_nsec);
}
struct Options {
  size_t events = 10000, producers = 1, warmup = 1000, queue_slots = 256;
  std::string output, phase = "sampled", strategy = "producer_format", metadata = "minimal", storage = "memory";
};
Options parse(int argc, char** argv) {
  Options result;
  for (int i = 1; i < argc; ++i) {
    std::string option = argv[i];
    auto equal = option.find('=');
    if (equal == std::string::npos) throw std::runtime_error("expected --key=value");
    auto key = option.substr(0, equal), value = option.substr(equal + 1);
    if (key == "--output") result.output = value;
    else if (key == "--phase") result.phase = value;
    else if (key == "--strategy") result.strategy = value;
    else if (key == "--metadata") result.metadata = value;
    else if (key == "--storage") result.storage = value;
    else if (key == "--events") result.events = std::stoull(value);
    else if (key == "--producers") result.producers = std::stoull(value);
    else if (key == "--warmup") result.warmup = std::stoull(value);
    else if (key == "--queue-slots") result.queue_slots = std::stoull(value);
    else throw std::runtime_error("unknown option");
  }
  if (!result.events || result.events > 1000000 || result.warmup > 1000000 ||
      (result.producers != 1 && result.producers != 4) || result.output.empty() ||
      !result.queue_slots || result.queue_slots > 65536 ||
      (result.phase != "sampled" && result.phase != "batch") ||
      (result.strategy != "producer_format" && result.strategy != "deferred_format") ||
      (result.metadata != "minimal" && result.metadata != "full" && result.metadata != "default_text") ||
      (result.storage != "memory" && result.storage != "mmap"))
    throw std::runtime_error("invalid options");
  return result;
}
size_t share(size_t total, size_t producers, size_t id) { return total / producers + (id < total % producers); }
size_t payload(char* buffer, size_t capacity, uint64_t n, bool full = false, uint32_t channel = 0, uint64_t sequence = 0) {
  if (full) {
    int size = std::snprintf(buffer, capacity,
      ",\"message\":\"event\",\"session\":\"18446744073709551615\",\"channel\":%u,\"sequence\":%llu,\"route_mask\":1,\"config_generation\":1,\"trace_flags\":0,\"attributes\":{\"field0\":%llu,\"field1\":%llu,\"field2\":%llu,\"field3\":%llu,\"field4\":%llu}}",
      channel, (unsigned long long)sequence, (unsigned long long)n, (unsigned long long)(n+1),
      (unsigned long long)(n+2), (unsigned long long)(n+3), (unsigned long long)(n+4));
    if (size < 0 || size_t(size) >= capacity) throw std::runtime_error("record too large");
    return size_t(size);
  }
  int size = std::snprintf(buffer, capacity,
    "{\"message\":\"event\",\"attributes\":{\"field0\":%llu,\"field1\":%llu,\"field2\":%llu,\"field3\":%llu,\"field4\":%llu}}",
    (unsigned long long)n, (unsigned long long)(n+1), (unsigned long long)(n+2),
    (unsigned long long)(n+3), (unsigned long long)(n+4));
  if (size < 0 || size_t(size) >= capacity) throw std::runtime_error("record too large");
  return size_t(size);
}
uint64_t percentile(std::vector<uint64_t> const& samples, size_t thousandths) {
  return samples[(samples.size()*thousandths+999)/1000-1];
}
uint64_t validate(std::string const& path, Options const& options) {
  std::ifstream input(path);
  if (!input) throw std::runtime_error("output unavailable");
  std::vector<bool> seen(options.events + options.warmup, false);
  std::string line;
  size_t count = 0;
  uint64_t warmup_bytes = 0;
  while (std::getline(input, line)) {
    auto position = line.find("\"field0\":");
    if (position == std::string::npos) throw std::runtime_error("missing numeric field");
    uint64_t n = std::stoull(line.substr(position+9));
    if (n >= seen.size() || seen[n]) throw std::runtime_error("duplicate or unexpected record");
    char expected[512];
    uint32_t channel = 0; uint64_t sequence = 0;
    std::string prefix;
    if (options.metadata == "default_text") {
      const auto payload_start = line.find("{\"message\":\"event\"");
      if (payload_start==std::string::npos || line.substr(0,payload_start).find(" [info] [reference] [thread ")==std::string::npos)
        throw std::runtime_error("missing default metadata");
      prefix=line.substr(0,payload_start);
    }
    if (options.metadata == "full") {
      std::string const beginning = "{\"timestamp_ns\":\"";
      if (line.compare(0, beginning.size(), beginning) != 0) throw std::runtime_error("missing system timestamp");
      size_t end = line.find('"', beginning.size());
      if (end != beginning.size()+19 || line.substr(beginning.size(),19).find_first_not_of("0123456789") != std::string::npos)
        throw std::runtime_error("invalid system timestamp");
      prefix = beginning + line.substr(beginning.size(),19) + "\",\"severity\":\"info\",\"scope\":\"reference\"";
      channel = uint32_t(std::stoull(line.substr(line.find("\"channel\":")+10)));
      sequence = std::stoull(line.substr(line.find("\"sequence\":")+11));
      if (!sequence || channel > options.producers) throw std::runtime_error("invalid correlation metadata");
    }
    size_t length = payload(expected, sizeof(expected), n, options.metadata == "full", channel, sequence);
    if (line != prefix + std::string(expected,length)) throw std::runtime_error("partial or damaged record");
    if (n >= options.events) warmup_bytes += line.size()+1;
    seen[n] = true;
    ++count;
  }
  if (count != seen.size() || std::find(seen.begin(),seen.end(),false) != seen.end())
    throw std::runtime_error("missing records after drain");
  return warmup_bytes;
}

#if defined(LIB_SPDLOG)
class FileSink : public spdlog::sinks::base_sink<std::mutex> {
public:
  explicit FileSink(std::string const& path, bool full) : full_(full) {
    file_ = std::fopen(path.c_str(),"wb");
    if (!file_) throw std::runtime_error("fopen");
    if (std::setvbuf(file_, buffer_, _IOFBF, sizeof(buffer_))) throw std::runtime_error("setvbuf");
  }
  ~FileSink() override { if (file_) std::fclose(file_); }
  uint64_t records() { std::lock_guard<std::mutex> lock(this->mutex_); return records_; }
  uint64_t bytes() { std::lock_guard<std::mutex> lock(this->mutex_); return bytes_; }
  uint64_t generation() { std::lock_guard<std::mutex> lock(wait_mutex_); return generation_; }
  void wait_flush(uint64_t generation) {
    std::unique_lock<std::mutex> lock(wait_mutex_);
    if (!condition_.wait_for(lock,std::chrono::seconds(20),[&]{return generation_>generation;}))
      throw std::runtime_error("flush completion timeout");
  }
protected:
  void sink_it_(spdlog::details::log_msg const& message) override {
    size_t prefix_bytes = 0;
    if (full_) {
      const auto timestamp = std::chrono::duration_cast<std::chrono::nanoseconds>(message.time.time_since_epoch()).count();
      char prefix[128];
      int size = std::snprintf(prefix, sizeof(prefix), "{\"timestamp_ns\":\"%lld\",\"severity\":\"info\",\"scope\":\"reference\"", (long long)timestamp);
      if (size <= 0 || size_t(size) >= sizeof(prefix) || std::fwrite(prefix,1,size_t(size),file_) != size_t(size)) throw std::runtime_error("metadata fwrite");
      prefix_bytes = size_t(size);
    }
    size_t done = 0;
    while (done < message.payload.size()) {
      size_t n = std::fwrite(message.payload.data()+done,1,message.payload.size()-done,file_);
      if (!n) throw std::runtime_error("fwrite");
      done += n;
    }
    if (std::fputc('\n',file_) == EOF) throw std::runtime_error("fputc");
    ++records_; bytes_ += prefix_bytes+done+1;
  }
  void flush_() override {
    if (std::fflush(file_)) throw std::runtime_error("fflush");
    { std::lock_guard<std::mutex> lock(wait_mutex_); ++generation_; }
    condition_.notify_all();
  }
private:
  FILE* file_ = nullptr;
  bool full_;
  char buffer_[65536];
  uint64_t records_ = 0, bytes_ = 0, generation_ = 0;
  std::mutex wait_mutex_;
  std::condition_variable condition_;
};
class Engine {
public:
  static constexpr char const* library = "spdlog";
  static constexpr char const* version = "1.17.0";
  explicit Engine(Options const& options) : sink_(std::make_shared<FileSink>(options.output,options.metadata=="full")), full_(options.metadata=="full") {
    if (options.strategy != "producer_format") throw std::runtime_error("spdlog formats on producer; deferred unsupported");
    pool_ = std::make_shared<spdlog::details::thread_pool>(options.queue_slots,1);
    logger_ = std::make_shared<spdlog::async_logger>("reference",sink_,pool_,spdlog::async_overflow_policy::block);
    logger_->set_error_handler([this](std::string const&) { errors_.fetch_add(1); });
  }
  void prepare() {}
  void emit(uint64_t n, uint32_t, uint64_t) {
    char bytes[512]; size_t length=payload(bytes,sizeof(bytes),n,full_,0,n+1);
    logger_->log(spdlog::level::info,spdlog::string_view_t(bytes,length));
  }
  void flush() { auto previous=sink_->generation(); logger_->flush(); sink_->wait_flush(previous); }
  void stop() { pool_.reset(); logger_.reset(); sink_->flush(); }
  uint64_t errors() const { return errors_.load(); }
  uint64_t blocking_notifications() const { return 0; }
  size_t slot_bytes() const { return sizeof(spdlog::details::async_msg); }
private:
  std::shared_ptr<FileSink> sink_;
  std::shared_ptr<spdlog::details::thread_pool> pool_;
  std::shared_ptr<spdlog::async_logger> logger_;
  std::atomic<uint64_t> errors_{0};
  bool full_;
};
#elif defined(LIB_QUILL)
#ifndef QUILL_REFERENCE_QUEUE_BYTES
#define QUILL_REFERENCE_QUEUE_BYTES 65536
#endif
struct FrontendOptions : quill::FrontendOptions {
  static constexpr quill::QueueType queue_type = quill::QueueType::BoundedBlocking;
  static constexpr size_t initial_queue_capacity = QUILL_REFERENCE_QUEUE_BYTES;
  static constexpr uint32_t blocking_queue_retry_interval_ns = 800;
};
using Frontend = quill::FrontendImpl<FrontendOptions>;
using Logger = quill::LoggerImpl<FrontendOptions>;
class Engine {
public:
  static constexpr char const* library = "quill";
  static constexpr char const* version = "13.1.0";
  explicit Engine(Options const& options) : deferred_(options.strategy=="deferred_format"), full_(options.metadata=="full") {
    quill::BackendOptions backend;
    backend.sleep_duration = std::chrono::nanoseconds{500};
    backend.transit_event_buffer_initial_capacity = 128;
    backend.transit_events_soft_limit = 256;
    backend.transit_events_hard_limit = 256;
    backend.log_timestamp_ordering_grace_period = std::chrono::microseconds{0};
    backend.error_notifier = [this](std::string const& message) {
      // The pinned Quill notifier also emits INFO for a blocked bounded queue.
      // Count that separately from actual delivery failures or dropped messages.
      if (message.find("Quill INFO: Experienced ") != std::string::npos && message.find(" blocking occurrences on thread ") != std::string::npos) blocking_.fetch_add(1);
      else errors_.fetch_add(1);
    };
    quill::Backend::start(backend);
    quill::FileSinkConfig config; config.set_open_mode('w'); config.set_write_buffer_size(65536);
    sink_ = Frontend::create_or_get_sink<quill::FileSink>(options.output,config);
    logger_ = Frontend::create_or_get_logger("reference",sink_,
      quill::PatternFormatterOptions{full_ ? "{\"timestamp_ns\":\"%(time)\",\"severity\":\"info\",\"scope\":\"reference\"%(message)" : "%(message)",full_ ? "%s%Qns" : "",quill::Timezone::GmtTime,false},quill::ClockSourceType::System);
  }
  void prepare() { Frontend::preallocate(); }
  void emit(uint64_t n, uint32_t channel, uint64_t sequence) {
    if (deferred_) {
      if (full_) {
        LOG_INFO(logger_,",\"message\":\"event\",\"session\":\"18446744073709551615\",\"channel\":{},\"sequence\":{},\"route_mask\":1,\"config_generation\":1,\"trace_flags\":0,\"attributes\":{{\"field0\":{},\"field1\":{},\"field2\":{},\"field3\":{},\"field4\":{}}}}}",channel,sequence,n,n+1,n+2,n+3,n+4);
      } else {
      LOG_INFO(logger_,"{{\"message\":\"event\",\"attributes\":{{\"field0\":{},\"field1\":{},\"field2\":{},\"field3\":{},\"field4\":{}}}}}",n,n+1,n+2,n+3,n+4);
      }
    } else {
      char bytes[512]; size_t length=payload(bytes,sizeof(bytes),n,full_,channel,sequence);
      LOG_INFO(logger_,"{}",std::string_view(bytes,length));
    }
  }
  void flush() { logger_->flush_log(); }
  void stop() { Frontend::remove_logger_blocking(logger_); logger_=nullptr; quill::Backend::stop(); }
  uint64_t errors() const { return errors_.load(); }
  uint64_t blocking_notifications() const { return blocking_.load(); }
  size_t slot_bytes() const { return 0; }
private:
  Logger* logger_ = nullptr;
  std::shared_ptr<quill::Sink> sink_;
  bool deferred_;
  bool full_;
  std::atomic<uint64_t> errors_{0};
  std::atomic<uint64_t> blocking_{0};
};
#endif

#if defined(LIB_FOUNDATION)
class MetadataFormatter final : public spdlog::formatter {
public:
  explicit MetadataFormatter(bool full) : full_(full) {}
  void format(spdlog::details::log_msg const& message, spdlog::memory_buf_t& out) override {
    if (full_) {
      const auto timestamp = std::chrono::duration_cast<std::chrono::nanoseconds>(message.time.time_since_epoch()).count();
      char prefix[128];
      int size = std::snprintf(prefix,sizeof(prefix),"{\"timestamp_ns\":\"%lld\",\"severity\":\"info\",\"scope\":\"reference\"",(long long)timestamp);
      if (size <= 0 || size_t(size) >= sizeof(prefix)) throw std::runtime_error("metadata formatting");
      out.append(prefix,prefix+size);
    }
    out.append(message.payload.data(),message.payload.data()+message.payload.size());
    out.push_back('\n');
  }
  std::unique_ptr<spdlog::formatter> clone() const override { return std::make_unique<MetadataFormatter>(full_); }
private:
  bool full_;
};

class Engine {
public:
  static constexpr char const* library="foundation";
  static constexpr char const* version="workspace-0.1.0";
  explicit Engine(Options const& options) : full_(options.metadata=="full"), mapped_(options.storage=="mmap") {
    if (options.strategy!="producer_format") throw std::runtime_error("Foundation formats on producer");
    foundation::logging::Settings settings;
    std::filesystem::path output(options.output);
    settings.logger_name="reference";
    settings.log_directory=output.parent_path();
    settings.log_file_name=output.filename().string();
    settings.console=false;
    settings.block_when_full=true;
    settings.queue_capacity=options.queue_slots;
    settings.queue_capacity_bytes=options.queue_slots*512;
    settings.critical_reserve_records=0;
    settings.critical_reserve_bytes=0;
    settings.write_buffer_bytes=65536;
    settings.max_file_bytes=1ULL<<30;
    settings.max_files=2;
    settings.SetMmapEnabled(mapped_);
    settings.mmap_spool_path=options.output+".spool";
    settings.mmap_slot_bytes=576;
    settings.mmap_capacity_bytes=4096+options.queue_slots*576;
    logger_=std::make_unique<foundation::logging::Logger>(settings);
    if (options.metadata!="default_text") logger_->Native().set_formatter(std::make_unique<MetadataFormatter>(full_));
    logger_->Native().set_error_handler([this](std::string const&){ errors_.fetch_add(1); });
  }
  void prepare() {}
  void emit(uint64_t n,uint32_t,uint64_t) {
    char bytes[512];
    size_t length=payload(bytes,sizeof(bytes),n,full_,0,n+1);
    logger_->Native().log(spdlog::level::info,spdlog::string_view_t(bytes,length));
  }
  void flush() { logger_->Flush(); }
  void stop() {
    stats_=logger_->GetStats();
    logger_->Close();
  }
  uint64_t errors() const { return errors_.load()+stats_.write_error_count; }
  uint64_t blocking_notifications() const { return stats_.queue_full_count; }
  size_t slot_bytes() const { return 0; }
  foundation::logging::Stats stats() const { return stats_; }
private:
  bool full_,mapped_;
  std::unique_ptr<foundation::logging::Logger> logger_;
  foundation::logging::Stats stats_{};
  std::atomic<uint64_t> errors_{0};
};
#endif

void run(Options const& options) {
  std::cout<<std::setprecision(17);
  auto lifecycle_begin=awake();
  auto engine=std::make_unique<Engine>(options);
  auto initialized=awake();
  std::vector<std::vector<uint64_t>> samples(options.producers);
  std::vector<uint64_t> attempts(options.producers,0);
  std::vector<std::exception_ptr> failures(options.producers);
  std::mutex gate_mutex; std::condition_variable gate;
  size_t ready=0; bool start=false;
  std::vector<std::thread> threads;
  for (size_t id=0;id<options.producers;++id) {
    samples[id].reserve(options.phase=="sampled"?share(options.events,options.producers,id):0);
    threads.emplace_back([&,id] {
      try {
        engine->prepare();
        for (size_t i=0;i<share(options.warmup,options.producers,id);++i)
          engine->emit(options.events+i*options.producers+id,uint32_t(id+1),i+1);
      } catch (...) { failures[id]=std::current_exception(); }
      { std::unique_lock<std::mutex> lock(gate_mutex); ++ready; gate.notify_all(); gate.wait(lock,[&]{return start;}); }
      if (failures[id]) return;
      try {
        for (size_t i=0;i<share(options.events,options.producers,id);++i) {
          auto before = options.phase=="sampled"?awake():0;
          engine->emit(i*options.producers+id,uint32_t(id+1),share(options.warmup,options.producers,id)+i+1);
          if (options.phase=="sampled") samples[id].push_back(awake()-before);
          ++attempts[id];
        }
      } catch (...) { failures[id]=std::current_exception(); }
    });
  }
  { std::unique_lock<std::mutex> lock(gate_mutex); gate.wait(lock,[&]{return ready==options.producers;}); }
  engine->flush();
  auto begin=awake();
  { std::lock_guard<std::mutex> lock(gate_mutex); start=true; } gate.notify_all();
  for (auto& thread:threads) thread.join();
  auto produced=awake(); engine->flush(); auto flushed=awake(); engine->stop(); auto end=awake();
  for (auto failure:failures) if (failure) std::rethrow_exception(failure);
  if (engine->errors()) throw std::runtime_error("library reported delivery error");
  size_t accepted=std::accumulate(attempts.begin(),attempts.end(),size_t(0));
  if (accepted!=options.events) throw std::runtime_error("attempt counter mismatch");
  const auto blocking_notifications=engine->blocking_notifications();
  const auto slot_bytes=engine->slot_bytes();
#if defined(LIB_FOUNDATION)
  const auto foundation_stats=engine->stats();
  if (foundation_stats.submitted_records!=options.events+options.warmup ||
      foundation_stats.written_records!=foundation_stats.submitted_records ||
      foundation_stats.recovered_records!=0) throw std::runtime_error("Foundation completion counters mismatch");
#endif
  engine.reset();
  auto cleaned=awake();
  const uint64_t warmup_bytes=validate(options.output,options);
  std::ifstream file(options.output,std::ios::binary|std::ios::ate); uint64_t bytes=file.tellg();
  std::vector<uint64_t> combined;
  for (auto const& part:samples) combined.insert(combined.end(),part.begin(),part.end());
  std::sort(combined.begin(),combined.end());
  std::vector<uint64_t> noop; noop.reserve(10000);
  for (size_t i=0;i<10000;++i) { auto before=awake(); asm volatile("" : : "r"(i)); noop.push_back(awake()-before); }
  std::sort(noop.begin(),noop.end());
  rusage usage{}; getrusage(RUSAGE_SELF,&usage);
  std::cout << "{\"schema_version\":2,\"status\":\"ok\",\"library\":\""<<Engine::library
    <<"\",\"version\":\""<<Engine::version<<"\",\"strategy\":\""<<options.strategy
    <<"\",\"phase\":\""<<options.phase<<"\",\"events\":"<<options.events
    <<",\"producers\":"<<options.producers<<",\"warmup_events\":"<<options.warmup
    <<",\"accepted\":"<<accepted<<",\"written\":"<<accepted<<",\"drop\":0,\"final_pending\":0"
    <<",\"producer_wall_ns\":"<<produced-begin<<",\"flush_ns\":"<<flushed-produced
    <<",\"shutdown_ns\":"<<end-flushed<<",\"total_ns\":"<<cleaned-begin
    <<",\"cleanup_ns\":"<<cleaned-end<<",\"init_ns\":"<<initialized-lifecycle_begin
    <<",\"preparation_ns\":"<<begin-initialized<<",\"lifecycle_ns\":"<<cleaned-lifecycle_begin
    <<",\"lifecycle_records_per_sec\":"<<double(options.events+options.warmup)*1e9/double(cleaned-lifecycle_begin)
    <<",\"metadata\":\""<<options.metadata<<"\",\"written_bytes\":"<<bytes-warmup_bytes<<",\"artifact_bytes\":"<<bytes
    <<",\"written_records_per_sec\":"<<double(accepted)*1e9/double(cleaned-begin)
    <<",\"sample_count\":"<<combined.size()<<",\"p50_ns\":";
  if(combined.empty()) std::cout<<"null"; else std::cout<<percentile(combined,500);
  std::cout<<",\"p99_ns\":"; if(combined.empty()) std::cout<<"null"; else std::cout<<percentile(combined,990);
  std::cout<<",\"p999_ns\":"; if(combined.empty()) std::cout<<"null"; else std::cout<<percentile(combined,999);
  std::cout<<",\"noop_clock_pair_p50_ns\":"<<percentile(noop,500)
    <<",\"noop_clock_pair_p99_ns\":"<<percentile(noop,990)
    <<",\"queue_policy\":\"block\",\"queue_slots\":"<<options.queue_slots
    <<",\"blocking_notifications\":"<<blocking_notifications
    <<",\"spdlog_slot_bytes\":"<<slot_bytes
    <<",\"quill_per_thread_queue_bytes\":";
#if defined(LIB_QUILL)
  std::cout<<QUILL_REFERENCE_QUEUE_BYTES;
#else
  std::cout<<0;
#endif
  std::cout<<",\"quill_transit_hard_limit_per_thread_records\":256"
    <<",\"file_buffer_bytes\":65536,\"process_max_rss_kib\":"<<usage.ru_maxrss
    <<",\"storage\":\""<<options.storage<<"\",\"has_process_crash_recovery\":";
#if defined(LIB_FOUNDATION)
  std::cout<<(options.storage=="mmap"?"true":"false")<<",\"foundation_queue_capacity_bytes\":"<<options.queue_slots*512
    <<",\"foundation_mmap_slot_bytes\":576,\"foundation_mmap_capacity_bytes\":"<<4096+options.queue_slots*576
    <<",\"foundation_submitted_records\":"<<foundation_stats.submitted_records
    <<",\"foundation_written_records\":"<<foundation_stats.written_records
    <<",\"foundation_written_bytes\":"<<foundation_stats.written_bytes;
#else
  std::cout<<"false";
#endif
  std::cout<<",\"event_clock\":\"system\"}\n";
}
} // namespace
int main(int argc,char** argv) {
  try { run(parse(argc,argv)); return 0; }
  catch(std::exception const& error) { std::cerr<<"cpp-reference: "<<error.what()<<"\n"; return 2; }
}
