//! Explicit, process-wide native failure signal reporting.
//!
//! Install before starting application workers and uninstall after joining them,
//! before unloading a library containing this core. Logger/Backend lifetimes do
//! not install or remove handlers. Replacing an existing handler requires an
//! explicit option. Reports bypass all logging queues and locks.
//!
//! Linux GNU x86_64/AArch64 are supported. Native stack unwinding is best effort;
//! the signal, fault PC and other basic fields are written before unwinding.

use std::path::PathBuf;

use crate::{Error, Result};

#[cfg(all(
    target_os = "linux",
    target_env = "gnu",
    any(target_arch = "x86_64", target_arch = "aarch64")
))]
mod linux;

/// Configuration belongs to the process, not to any individual logger.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FailureSignalOptions {
    pub service_name: String,
    pub report_path: PathBuf,
    pub also_stderr: bool,
    /// SIGTERM normally belongs to the application's orderly shutdown path.
    pub include_sigterm: bool,
    /// Opt in only when the application owns the existing handlers, including
    /// Rust std's stack overflow handlers. Previous actions are saved/restored.
    pub replace_existing: bool,
}

impl FailureSignalOptions {
    pub fn new(service_name: impl Into<String>, report_path: impl Into<PathBuf>) -> Self {
        Self {
            service_name: service_name.into(),
            report_path: report_path.into(),
            also_stderr: true,
            include_sigterm: false,
            replace_existing: false,
        }
    }

    fn validate(&self) -> Result<()> {
        if self.service_name.is_empty()
            || self.service_name.len() > 256
            || self
                .service_name
                .bytes()
                .any(|byte| byte.is_ascii_control())
        {
            return Err(Error::InvalidInput(
                "failure service name must contain 1-256 bytes without control characters".into(),
            ));
        }
        if self.report_path.as_os_str().is_empty() {
            return Err(Error::InvalidInput(
                "failure report path must not be empty".into(),
            ));
        }
        Ok(())
    }
}

/// Repeated installation with identical options is idempotent. Different
/// options produce an error. Existing handlers (including SIG_IGN) produce an
/// error unless replacement was explicitly requested.
pub fn install_failure_signal_handler(options: FailureSignalOptions) -> Result<()> {
    options.validate()?;
    #[cfg(all(
        target_os = "linux",
        target_env = "gnu",
        any(target_arch = "x86_64", target_arch = "aarch64")
    ))]
    return linux::install(options);

    #[cfg(not(all(
        target_os = "linux",
        target_env = "gnu",
        any(target_arch = "x86_64", target_arch = "aarch64")
    )))]
    Err(Error::InvalidInput(
        "failure signals require Linux GNU x86_64/AArch64".into(),
    ))
}

/// Restores only handlers still owned by this installation, preserving changes
/// made by the application afterwards. Uninstalling an absent handler succeeds.
pub fn uninstall_failure_signal_handler() -> Result<()> {
    #[cfg(all(
        target_os = "linux",
        target_env = "gnu",
        any(target_arch = "x86_64", target_arch = "aarch64")
    ))]
    return linux::uninstall();

    #[cfg(not(all(
        target_os = "linux",
        target_env = "gnu",
        any(target_arch = "x86_64", target_arch = "aarch64")
    )))]
    Ok(())
}

/// True only when all selected signal handlers still belong to this core.
pub fn is_failure_signal_handler_installed() -> bool {
    #[cfg(all(
        target_os = "linux",
        target_env = "gnu",
        any(target_arch = "x86_64", target_arch = "aarch64")
    ))]
    return linux::is_installed();

    #[cfg(not(all(
        target_os = "linux",
        target_env = "gnu",
        any(target_arch = "x86_64", target_arch = "aarch64")
    )))]
    false
}
