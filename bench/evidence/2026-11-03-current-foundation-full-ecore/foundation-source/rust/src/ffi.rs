mod config;
mod crash;

pub use crash::{
    foundation_log_failure_signal_handler_installed, foundation_log_install_failure_signal_handler,
    foundation_log_uninstall_failure_signal_handler, FoundationFailureSignalConfig,
    FOUNDATION_LOG_FAILURE_SIGNAL_API_VERSION,
};

use std::cell::RefCell;
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;

use crate::{Backend, Error, Settings, Stats};

pub const FOUNDATION_LOG_OK: i32 = 0;
pub const FOUNDATION_LOG_INVALID_ARGUMENT: i32 = 1;
pub const FOUNDATION_LOG_IO_ERROR: i32 = 2;
pub const FOUNDATION_LOG_CLOSED: i32 = 3;
pub const FOUNDATION_LOG_QUEUE_FULL: i32 = 4;
pub const FOUNDATION_LOG_BACKGROUND_ERROR: i32 = 5;
pub const FOUNDATION_LOG_PANIC: i32 = 6;
pub const FOUNDATION_LOG_RECORD_TOO_LARGE: i32 = 7;
pub const FOUNDATION_LOG_MODE_MEMORY: u32 = 0;
pub const FOUNDATION_LOG_MODE_MMAP: u32 = 1;
pub const FOUNDATION_LOG_PRIORITY_NORMAL: u32 = 0;
pub const FOUNDATION_LOG_PRIORITY_CRITICAL: u32 = 1;

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::new("no error").unwrap());
}

#[repr(C)]
pub struct FoundationLogConfig {
    pub struct_size: u32,
    pub api_version: u32,
    pub log_directory: *const c_char,
    pub log_file_name: *const c_char,
    pub max_file_bytes: u64,
    pub max_files: u32,
    pub queue_capacity: u32,
    pub write_buffer_bytes: u32,
    pub block_when_full: u8,
    pub mode: u32,
    pub mmap_spool_path: *const c_char,
    pub mmap_capacity_bytes: u64,
    pub mmap_slot_bytes: u32,
    pub reserved_mmap_lanes: u32,
    pub extension_version: u32,
    pub reserved_mmap_spsc_lanes: u32,
    pub extension_version_v4: u32,
    pub reserved_output_mode: u32,
    pub reserved_io_uring_entries: u32,
    pub extension_version_v5: u32,
    pub queue_capacity_bytes: u64,
    pub extension_version_v6: u32,
    pub reserved_v6: u32,
    pub critical_reserve_records: u32,
    pub extension_version_v7: u32,
    pub critical_reserve_bytes: u64,
}

#[repr(C)]
#[derive(Default)]
pub struct FoundationLogStats {
    pub submitted_records: u64,
    pub submitted_bytes: u64,
    pub written_records: u64,
    pub written_bytes: u64,
    pub queue_full_count: u64,
    pub write_error_count: u64,
}

#[repr(C)]
#[derive(Default)]
pub struct FoundationLogStatsV2 {
    pub struct_size: u32,
    pub reserved: u32,
    pub submitted_records: u64,
    pub submitted_bytes: u64,
    pub written_records: u64,
    pub written_bytes: u64,
    pub recovered_records: u64,
    pub queue_full_count: u64,
    pub write_error_count: u64,
}

pub struct FoundationLogHandle {
    backend: Backend,
}

#[no_mangle]
/// Opens a logging backend through the stable C ABI.
///
/// # Safety
/// `config` and `output` must point to valid objects for the duration of this
/// call. Every C string in `config` must be NUL terminated.
pub unsafe extern "C" fn foundation_log_open(
    config: *const FoundationLogConfig,
    output: *mut *mut FoundationLogHandle,
) -> i32 {
    ffi_status(|| {
        if config.is_null() || output.is_null() {
            return Err(Error::InvalidInput(
                "config and output must not be null".to_owned(),
            ));
        }
        *output = std::ptr::null_mut();
        let settings = config::parse(config)?;
        let backend = Backend::open(settings)?;
        *output = Box::into_raw(Box::new(FoundationLogHandle { backend }));
        Ok(())
    })
}

#[no_mangle]
/// Submits one complete byte record through the stable C ABI.
///
/// # Safety
/// `handle` must come from `foundation_log_open` and remain open. When `size`
/// is nonzero, `data` must be readable for `size` bytes during this call.
pub unsafe extern "C" fn foundation_log_submit(
    handle: *mut FoundationLogHandle,
    data: *const c_void,
    size: usize,
) -> i32 {
    ffi_status(|| {
        let handle = required_handle(handle)?;
        if data.is_null() && size != 0 {
            return Err(Error::InvalidInput("data must not be null".to_owned()));
        }
        let record = if size == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(data.cast::<u8>(), size)
        };
        handle.backend.submit(record)
    })
}

#[no_mangle]
/// Submits one complete record while allowing Critical records to consume the
/// configured reserve. The legacy submit entry point always uses Normal.
///
/// # Safety
/// The handle and data requirements match `foundation_log_submit`.
pub unsafe extern "C" fn foundation_log_submit_with_priority(
    handle: *mut FoundationLogHandle,
    data: *const c_void,
    size: usize,
    priority: u32,
) -> i32 {
    ffi_status(|| {
        let handle = required_handle(handle)?;
        if data.is_null() && size != 0 {
            return Err(Error::InvalidInput("data must not be null".to_owned()));
        }
        let priority = match priority {
            FOUNDATION_LOG_PRIORITY_NORMAL => crate::Priority::Normal,
            FOUNDATION_LOG_PRIORITY_CRITICAL => crate::Priority::Critical,
            _ => return Err(Error::InvalidInput("unsupported log priority".to_owned())),
        };
        let record = if size == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(data.cast::<u8>(), size)
        };
        handle.backend.submit_with_priority(record, priority)
    })
}

#[no_mangle]
/// Native-adapter submission with Critical reserve and bounded oversized-record
/// truncation. Raw callers that require rejection use the legacy/priority APIs.
///
/// # Safety
/// The handle and data requirements match `foundation_log_submit`.
pub unsafe extern "C" fn foundation_log_submit_native(
    handle: *mut FoundationLogHandle,
    data: *const c_void,
    size: usize,
    priority: u32,
) -> i32 {
    ffi_status(|| {
        let handle = required_handle(handle)?;
        if data.is_null() && size != 0 {
            return Err(Error::InvalidInput("data must not be null".to_owned()));
        }
        let priority = match priority {
            FOUNDATION_LOG_PRIORITY_NORMAL => crate::Priority::Normal,
            FOUNDATION_LOG_PRIORITY_CRITICAL => crate::Priority::Critical,
            _ => return Err(Error::InvalidInput("unsupported log priority".to_owned())),
        };
        let record = if size == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(data.cast::<u8>(), size)
        };
        handle.backend.submit_native(record, priority)
    })
}

#[no_mangle]
/// Waits for records accepted before this call to reach the output file.
///
/// # Safety
/// `handle` must come from `foundation_log_open` and remain open.
pub unsafe extern "C" fn foundation_log_flush(
    handle: *mut FoundationLogHandle,
    durable: u8,
) -> i32 {
    ffi_status(|| {
        let handle = required_handle(handle)?;
        if durable != 0 {
            handle.backend.flush_durable()
        } else {
            handle.backend.flush()
        }
    })
}

#[no_mangle]
/// Copies a statistics snapshot to caller-owned memory.
///
/// # Safety
/// `handle` must remain open and `output` must be writable for one complete
/// `FoundationLogStats` value.
pub unsafe extern "C" fn foundation_log_get_stats(
    handle: *mut FoundationLogHandle,
    output: *mut FoundationLogStats,
) -> i32 {
    ffi_status(|| {
        let handle = required_handle(handle)?;
        if output.is_null() {
            return Err(Error::InvalidInput(
                "stats output must not be null".to_owned(),
            ));
        }
        *output = handle.backend.stats().into();
        Ok(())
    })
}

#[no_mangle]
/// Copies the extended statistics snapshot, including mmap recovery count.
///
/// # Safety
/// `handle` must remain open and `output` must be writable for one complete
/// `FoundationLogStatsV2` value with `struct_size` initialized by the caller.
pub unsafe extern "C" fn foundation_log_get_stats_v2(
    handle: *mut FoundationLogHandle,
    output: *mut FoundationLogStatsV2,
) -> i32 {
    ffi_status(|| {
        let handle = required_handle(handle)?;
        if output.is_null()
            || (*output).struct_size < std::mem::size_of::<FoundationLogStatsV2>() as u32
        {
            return Err(Error::InvalidInput(
                "stats v2 output is null or too small".to_owned(),
            ));
        }
        *output = handle.backend.stats().into();
        Ok(())
    })
}

#[no_mangle]
/// Closes a handle created by `foundation_log_open`.
///
/// # Safety
/// The handle must not have been closed already, and no other thread may be
/// using it when this function is called.
pub unsafe extern "C" fn foundation_log_close(handle: *mut FoundationLogHandle) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(handle))));
}

#[no_mangle]
pub extern "C" fn foundation_log_last_error_message() -> *const c_char {
    LAST_ERROR.with(|message| message.borrow().as_ptr())
}

fn ffi_status(operation: impl FnOnce() -> crate::Result<()>) -> i32 {
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(Ok(())) => FOUNDATION_LOG_OK,
        Ok(Err(error)) => {
            set_last_error(&error.to_string());
            error_code(&error)
        }
        Err(_) => {
            set_last_error("panic inside the Rust logging core");
            FOUNDATION_LOG_PANIC
        }
    }
}

fn error_code(error: &Error) -> i32 {
    match error {
        Error::InvalidInput(_) => FOUNDATION_LOG_INVALID_ARGUMENT,
        Error::Io(_) => FOUNDATION_LOG_IO_ERROR,
        Error::Closed => FOUNDATION_LOG_CLOSED,
        Error::QueueFull => FOUNDATION_LOG_QUEUE_FULL,
        Error::Background(_) => FOUNDATION_LOG_BACKGROUND_ERROR,
        Error::RecordTooLarge { .. } => FOUNDATION_LOG_RECORD_TOO_LARGE,
    }
}

fn set_last_error(message: &str) {
    let sanitized = message.replace('\0', " ");
    LAST_ERROR.with(|last| {
        *last.borrow_mut() = CString::new(sanitized).unwrap();
    });
}

unsafe fn required_handle<'a>(
    handle: *mut FoundationLogHandle,
) -> crate::Result<&'a FoundationLogHandle> {
    handle
        .as_ref()
        .ok_or_else(|| Error::InvalidInput("logging handle must not be null".to_owned()))
}

unsafe fn required_string(pointer: *const c_char, name: &str) -> crate::Result<String> {
    if pointer.is_null() {
        return Err(Error::InvalidInput(format!("{name} must not be null")));
    }
    CStr::from_ptr(pointer)
        .to_str()
        .map(str::to_owned)
        .map_err(|_| Error::InvalidInput(format!("{name} must be valid UTF-8")))
}

unsafe fn required_path(pointer: *const c_char, name: &str) -> crate::Result<PathBuf> {
    required_string(pointer, name).map(PathBuf::from)
}

impl From<Stats> for FoundationLogStats {
    fn from(stats: Stats) -> Self {
        Self {
            submitted_records: stats.submitted_records,
            submitted_bytes: stats.submitted_bytes,
            written_records: stats.written_records,
            written_bytes: stats.written_bytes,
            queue_full_count: stats.queue_full_count,
            write_error_count: stats.write_error_count,
        }
    }
}

impl From<Stats> for FoundationLogStatsV2 {
    fn from(stats: Stats) -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            reserved: 0,
            submitted_records: stats.submitted_records,
            submitted_bytes: stats.submitted_bytes,
            written_records: stats.written_records,
            written_bytes: stats.written_bytes,
            recovered_records: stats.recovered_records,
            queue_full_count: stats.queue_full_count,
            write_error_count: stats.write_error_count,
        }
    }
}

#[cfg(test)]
mod tests;
