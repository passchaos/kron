use std::path::{Path, PathBuf};

use crate::{Error, Result};

pub const DEFAULT_LOG_DIRECTORY: &str = "/nav_env/log";
pub const DEFAULT_MAX_FILE_BYTES: u64 = 100 * 1024 * 1024;
pub const DEFAULT_MAX_FILES: usize = 10;
pub const DEFAULT_QUEUE_CAPACITY: usize = 8192;
pub const DEFAULT_QUEUE_CAPACITY_BYTES: usize = 100 * 1024 * 1024;
pub const DEFAULT_CRITICAL_RESERVE_RECORDS: usize = 32;
pub const DEFAULT_CRITICAL_RESERVE_BYTES: usize = 256 * 1024;
pub const DEFAULT_WRITE_BUFFER_BYTES: usize = 256 * 1024;
pub const DEFAULT_MMAP_CAPACITY_BYTES: usize = 64 * 1024 * 1024;
pub const DEFAULT_MMAP_SLOT_BYTES: usize = 8 * 1024;

#[derive(Debug, Clone)]
pub enum BackendMode {
    Memory,
    Mmap {
        spool_path: PathBuf,
        capacity_bytes: usize,
        slot_bytes: usize,
    },
}

#[derive(Debug, Clone)]
pub struct Settings {
    pub log_directory: PathBuf,
    pub log_file_name: String,
    pub max_file_bytes: u64,
    pub max_files: usize,
    pub queue_capacity: usize,
    pub queue_capacity_bytes: usize,
    /// Capacity unavailable to normal records but available to Error/Critical
    /// records. Effective reserves are capped at one eighth of total capacity.
    pub critical_reserve_records: usize,
    pub critical_reserve_bytes: usize,
    pub write_buffer_bytes: usize,
    /// Waits for capacity when true. When false, raw submissions return QueueFull
    /// and native logging adapters discard the new record without an error report.
    pub block_when_full: bool,
    pub mode: BackendMode,
}

impl Settings {
    pub fn new(log_directory: impl AsRef<Path>, log_file_name: impl Into<String>) -> Self {
        Self {
            log_directory: log_directory.as_ref().to_path_buf(),
            log_file_name: log_file_name.into(),
            max_file_bytes: DEFAULT_MAX_FILE_BYTES,
            max_files: DEFAULT_MAX_FILES,
            queue_capacity: DEFAULT_QUEUE_CAPACITY,
            queue_capacity_bytes: DEFAULT_QUEUE_CAPACITY_BYTES,
            critical_reserve_records: DEFAULT_CRITICAL_RESERVE_RECORDS,
            critical_reserve_bytes: DEFAULT_CRITICAL_RESERVE_BYTES,
            write_buffer_bytes: DEFAULT_WRITE_BUFFER_BYTES,
            block_when_full: true,
            mode: BackendMode::Memory,
        }
    }

    /// Selects the backend before opening a logger. Enabling from Memory uses
    /// the globally ordered single spool and the default mmap dimensions.
    /// Existing explicit mmap configurations are preserved when enabled.
    pub fn set_mmap_enabled(&mut self, enabled: bool) {
        if !enabled {
            self.mode = BackendMode::Memory;
        } else if !self.is_mmap_enabled() {
            self.mode = BackendMode::Mmap {
                spool_path: self
                    .log_directory
                    .join(format!("{}.spool", self.log_file_name)),
                capacity_bytes: DEFAULT_MMAP_CAPACITY_BYTES,
                slot_bytes: DEFAULT_MMAP_SLOT_BYTES,
            };
        }
    }

    pub fn with_mmap_enabled(mut self, enabled: bool) -> Self {
        self.set_mmap_enabled(enabled);
        self
    }

    pub fn is_mmap_enabled(&self) -> bool {
        !matches!(self.mode, BackendMode::Memory)
    }

    pub(crate) fn validate(&self) -> Result<()> {
        if self.log_directory.as_os_str().is_empty() {
            return Err(invalid("log_directory must not be empty"));
        }
        if self.log_file_name.is_empty() {
            return Err(invalid("log_file_name must not be empty"));
        }
        if self.max_file_bytes == 0 {
            return Err(invalid("max_file_bytes must be greater than zero"));
        }
        if self.max_files == 0 {
            return Err(invalid("max_files must be greater than zero"));
        }
        if self.queue_capacity == 0 {
            return Err(invalid("queue_capacity must be greater than zero"));
        }
        if self.queue_capacity_bytes == 0 {
            return Err(invalid("queue_capacity_bytes must be greater than zero"));
        }
        if self.write_buffer_bytes == 0 {
            return Err(invalid("write_buffer_bytes must be greater than zero"));
        }
        if let BackendMode::Mmap {
            spool_path,
            capacity_bytes,
            slot_bytes,
        } = &self.mode
        {
            if spool_path.as_os_str().is_empty() {
                return Err(invalid("mmap spool_path must not be empty"));
            }
            if *slot_bytes < crate::mmap::MIN_SLOT_BYTES || !slot_bytes.is_multiple_of(8) {
                return Err(invalid(
                    "mmap slot_bytes must be at least 256 and aligned to 8 bytes",
                ));
            }
            let minimum = crate::mmap::HEADER_BYTES
                .checked_add(*slot_bytes)
                .ok_or_else(|| invalid("mmap dimensions exceed addressable memory"))?;
            if *capacity_bytes < minimum {
                return Err(invalid("mmap capacity must contain at least one slot"));
            }
        }
        Ok(())
    }

    pub(crate) fn active_path(&self) -> PathBuf {
        self.log_directory.join(&self.log_file_name)
    }

    pub(crate) fn effective_critical_reserve_records(&self, capacity: usize) -> usize {
        self.critical_reserve_records.min(capacity / 8)
    }

    pub(crate) fn effective_critical_reserve_bytes(&self, capacity: usize) -> usize {
        self.critical_reserve_bytes.min(capacity / 8)
    }
}

fn invalid(message: &str) -> Error {
    Error::InvalidInput(message.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enabling_mmap_preserves_an_explicit_configuration() {
        let mut settings = Settings::new("/tmp", "service.log");
        settings.mode = BackendMode::Mmap {
            spool_path: "/tmp/explicit.spool".into(),
            capacity_bytes: 4096 + 8 * 512,
            slot_bytes: 512,
        };
        settings.set_mmap_enabled(true);
        assert!(settings.is_mmap_enabled());
        assert!(matches!(
            settings.mode,
            BackendMode::Mmap {
                slot_bytes: 512,
                ..
            }
        ));
        settings.set_mmap_enabled(false);
        assert!(!settings.is_mmap_enabled());
        assert!(settings.validate().is_ok());
    }

    #[test]
    fn queue_byte_capacity_must_be_nonzero() {
        let mut settings = Settings::new("/tmp", "queue.log");
        settings.queue_capacity_bytes = 0;
        assert!(matches!(settings.validate(), Err(Error::InvalidInput(_))));
    }

    #[test]
    fn oversized_mmap_dimensions_return_an_error() {
        let mut settings = Settings::new("/tmp", "oversized.log");
        settings.mode = BackendMode::Mmap {
            spool_path: "/tmp/oversized.spool".into(),
            capacity_bytes: usize::MAX,
            slot_bytes: usize::MAX - 7,
        };
        assert!(matches!(settings.validate(), Err(Error::InvalidInput(_))));
    }
}
