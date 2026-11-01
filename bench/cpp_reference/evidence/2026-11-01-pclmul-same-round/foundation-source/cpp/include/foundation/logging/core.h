#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
  FOUNDATION_LOG_API_VERSION = 1,
  FOUNDATION_LOG_OK = 0,
  FOUNDATION_LOG_INVALID_ARGUMENT = 1,
  FOUNDATION_LOG_IO_ERROR = 2,
  FOUNDATION_LOG_CLOSED = 3,
  FOUNDATION_LOG_QUEUE_FULL = 4,
  FOUNDATION_LOG_BACKGROUND_ERROR = 5,
  FOUNDATION_LOG_PANIC = 6,
  FOUNDATION_LOG_RECORD_TOO_LARGE = 7,
};

enum {
  FOUNDATION_LOG_MODE_MEMORY = 0,
  FOUNDATION_LOG_MODE_MMAP = 1,
};

enum {
  FOUNDATION_LOG_PRIORITY_NORMAL = 0,
  FOUNDATION_LOG_PRIORITY_CRITICAL = 1,
};

typedef struct foundation_log_handle foundation_log_handle;

typedef struct foundation_log_config {
  uint32_t struct_size;
  uint32_t api_version;
  const char* log_directory;
  const char* log_file_name;
  uint64_t max_file_bytes;
  uint32_t max_files;
  uint32_t queue_capacity;
  uint32_t write_buffer_bytes;
  // 1 waits for capacity; 0 rejects the new record with FOUNDATION_LOG_QUEUE_FULL.
  uint8_t block_when_full;
  uint32_t mode;
  const char* mmap_spool_path;
  uint64_t mmap_capacity_bytes;
  uint32_t mmap_slot_bytes;
  /* Reserved legacy option slots retain config layout; initialize to zero. */
  uint32_t reserved_mmap_lanes;
  uint32_t extension_version;
  uint32_t reserved_mmap_spsc_lanes;
  uint32_t extension_version_v4;
  uint32_t reserved_output_mode;
  uint32_t reserved_io_uring_entries;
  uint32_t extension_version_v5;
  uint64_t queue_capacity_bytes;
  uint32_t extension_version_v6;
  uint32_t reserved_v6;
  uint32_t critical_reserve_records;
  uint32_t extension_version_v7;
  uint64_t critical_reserve_bytes;
} foundation_log_config;

/* Configure a full foundation_log_config before open(). Spool path, capacity,
 * slot size and extension markers must already be initialized for mmap.
 * This helper adds no ABI fields and does not switch an open handle. */
static inline void foundation_log_config_set_mmap_enabled(
    foundation_log_config* config, uint8_t enabled) {
  config->mode = enabled ? FOUNDATION_LOG_MODE_MMAP : FOUNDATION_LOG_MODE_MEMORY;
}

typedef struct foundation_log_stats {
  uint64_t submitted_records;
  uint64_t submitted_bytes;
  uint64_t written_records;
  uint64_t written_bytes;
  uint64_t queue_full_count;
  uint64_t write_error_count;
} foundation_log_stats;

typedef struct foundation_log_stats_v2 {
  uint32_t struct_size;
  uint32_t reserved;
  uint64_t submitted_records;
  uint64_t submitted_bytes;
  uint64_t written_records;
  uint64_t written_bytes;
  uint64_t recovered_records;
  uint64_t queue_full_count;
  uint64_t write_error_count;
} foundation_log_stats_v2;

int32_t foundation_log_open(const foundation_log_config* config,
                            foundation_log_handle** output);
int32_t foundation_log_submit(foundation_log_handle* handle, const void* data,
                              size_t size);
int32_t foundation_log_submit_with_priority(foundation_log_handle* handle,
                                            const void* data, size_t size,
                                            uint32_t priority);
int32_t foundation_log_submit_native(foundation_log_handle* handle,
                                     const void* data, size_t size,
                                     uint32_t priority);
int32_t foundation_log_flush(foundation_log_handle* handle, uint8_t durable);
int32_t foundation_log_get_stats(foundation_log_handle* handle,
                                 foundation_log_stats* output);
int32_t foundation_log_get_stats_v2(foundation_log_handle* handle,
                                    foundation_log_stats_v2* output);
void foundation_log_close(foundation_log_handle* handle);
const char* foundation_log_last_error_message(void);

enum { FOUNDATION_LOG_FAILURE_SIGNAL_API_VERSION = 1 };

/* Process-wide configuration, independent of foundation_log_config/handles.
 * Zero-initialize reserved fields. Installation is idempotent for identical
 * options. Existing handlers require explicit replace_existing authorization. */
typedef struct foundation_log_failure_signal_config {
  uint32_t struct_size;
  uint32_t api_version;
  const char* service_name;
  const char* report_path;
  uint8_t also_stderr;
  uint8_t include_sigterm;
  uint8_t replace_existing;
  uint8_t reserved[5];
} foundation_log_failure_signal_config;

/* Install before starting workers; uninstall after joining workers and before
 * unloading the core library. Reports bypass logging queues. Native stack
 * unwinding is best effort. Supported on Linux GNU x86_64/AArch64. */
int32_t foundation_log_install_failure_signal_handler(
    const foundation_log_failure_signal_config* config);
int32_t foundation_log_uninstall_failure_signal_handler(void);
uint8_t foundation_log_failure_signal_handler_installed(void);
#ifdef __cplusplus
}
#endif
