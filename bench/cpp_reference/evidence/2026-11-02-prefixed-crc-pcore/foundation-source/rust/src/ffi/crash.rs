use std::ffi::{c_char, CStr};

use crate::crash::{self, FailureSignalOptions};
use crate::{Error, Result};

pub const FOUNDATION_LOG_FAILURE_SIGNAL_API_VERSION: u32 = 1;

#[repr(C)]
pub struct FoundationFailureSignalConfig {
    pub struct_size: u32,
    pub api_version: u32,
    pub service_name: *const c_char,
    pub report_path: *const c_char,
    pub also_stderr: u8,
    pub include_sigterm: u8,
    pub replace_existing: u8,
    pub reserved: [u8; 5],
}

#[no_mangle]
/// Installs a process-wide handler independently of any logging handle.
///
/// # Safety
/// `config` must be readable for its advertised struct size and its strings
/// must be valid NUL-terminated UTF-8. Call before starting application workers.
pub unsafe extern "C" fn foundation_log_install_failure_signal_handler(
    config: *const FoundationFailureSignalConfig,
) -> i32 {
    super::ffi_status(|| crash::install_failure_signal_handler(parse(config)?))
}

unsafe fn parse(config: *const FoundationFailureSignalConfig) -> Result<FailureSignalOptions> {
    if config.is_null()
        || (*config).struct_size < std::mem::size_of::<FoundationFailureSignalConfig>() as u32
    {
        return Err(Error::InvalidInput(
            "failure signal config is null or too small".into(),
        ));
    }
    let config = &*config;
    if config.api_version != FOUNDATION_LOG_FAILURE_SIGNAL_API_VERSION
        || config.also_stderr > 1
        || config.include_sigterm > 1
        || config.replace_existing > 1
        || config.reserved != [0; 5]
        || config.service_name.is_null()
        || config.report_path.is_null()
    {
        return Err(Error::InvalidInput("invalid failure signal config".into()));
    }
    let service = CStr::from_ptr(config.service_name)
        .to_str()
        .map_err(|_| Error::InvalidInput("failure service name must be UTF-8".into()))?;
    let path = CStr::from_ptr(config.report_path)
        .to_str()
        .map_err(|_| Error::InvalidInput("failure report path must be UTF-8".into()))?;
    let mut options = FailureSignalOptions::new(service, path);
    options.also_stderr = config.also_stderr != 0;
    options.include_sigterm = config.include_sigterm != 0;
    options.replace_existing = config.replace_existing != 0;
    Ok(options)
}

#[no_mangle]
/// Call after joining workers and before unloading a library containing core.
pub extern "C" fn foundation_log_uninstall_failure_signal_handler() -> i32 {
    super::ffi_status(crash::uninstall_failure_signal_handler)
}

#[no_mangle]
pub extern "C" fn foundation_log_failure_signal_handler_installed() -> u8 {
    u8::from(crash::is_failure_signal_handler_installed())
}
