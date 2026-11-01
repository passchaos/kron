//! Shared logging persistence core for C++ spdlog, Rust tracing, and Python logging.

mod backend;
mod config;
pub mod crash;
mod decimal;
mod error;
pub mod ffi;
mod memory;
mod mmap;
mod rotation;
mod stats;
mod tracing_adapter;

pub use backend::{Backend, Priority};
pub use config::{
    BackendMode, Settings, DEFAULT_CRITICAL_RESERVE_BYTES, DEFAULT_CRITICAL_RESERVE_RECORDS,
    DEFAULT_LOG_DIRECTORY, DEFAULT_MAX_FILES, DEFAULT_MAX_FILE_BYTES, DEFAULT_MMAP_CAPACITY_BYTES,
    DEFAULT_MMAP_SLOT_BYTES, DEFAULT_QUEUE_CAPACITY, DEFAULT_QUEUE_CAPACITY_BYTES,
    DEFAULT_WRITE_BUFFER_BYTES,
};
pub use error::{Error, Result};
pub use stats::Stats;
pub use tracing_adapter::{
    build_tracing, init_tracing, TracingGuard, TracingMakeWriter, TracingOptions,
};

pub type BoxError = Box<dyn std::error::Error + Send + Sync>;

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(0);

    struct TestDirectory(PathBuf);

    impl TestDirectory {
        fn new(name: &str) -> Self {
            let sequence = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "foundation-logging-core-{name}-{}-{sequence}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn mmap_switch_selects_single_spool_and_memory_backends() {
        let directory = TestDirectory::new("mmap-switch");
        let settings = Settings::new(&directory.0, "enabled.log").with_mmap_enabled(true);
        let spool_path = directory.0.join("enabled.log.spool");
        assert!(matches!(&settings.mode, BackendMode::Mmap {
            spool_path: path, capacity_bytes: DEFAULT_MMAP_CAPACITY_BYTES,
            slot_bytes: DEFAULT_MMAP_SLOT_BYTES,
        } if path == &spool_path));
        let backend = Backend::open(settings).unwrap();
        backend.submit(b"enabled\n").unwrap();
        backend.flush().unwrap();
        assert!(spool_path.exists());
        assert_eq!(backend.stats().written_records, 1);
        drop(backend);
        assert_eq!(
            fs::read(directory.0.join("enabled.log")).unwrap(),
            b"enabled\n"
        );

        let settings = Settings::new(&directory.0, "disabled.log")
            .with_mmap_enabled(true)
            .with_mmap_enabled(false);
        let backend = Backend::open(settings).unwrap();
        backend.submit(b"disabled\n").unwrap();
        backend.flush().unwrap();
        drop(backend);
        assert!(!directory.0.join("disabled.log.spool").exists());
        assert_eq!(
            fs::read(directory.0.join("disabled.log")).unwrap(),
            b"disabled\n"
        );
    }

    #[test]
    fn memory_backend_drains_and_rotates_by_size() {
        let directory = TestDirectory::new("memory");
        let mut settings = Settings::new(&directory.0, "service.log");
        settings.max_file_bytes = 64;
        settings.max_files = 3;
        settings.queue_capacity = 2;
        let backend = Backend::open(settings).unwrap();
        for marker in b'a'..=b'e' {
            let mut record = vec![marker; 80];
            record.push(b'\n');
            backend.submit(&record).unwrap();
        }
        backend.flush().unwrap();

        let active = directory.0.join("service.log");
        assert!(fs::read(&active).unwrap().contains(&b'e'));
        assert!(fs::read(crate::rotation::archive_for_test(&active, 1))
            .unwrap()
            .contains(&b'd'));
        assert!(crate::rotation::archive_for_test(&active, 2).exists());
        assert!(!crate::rotation::archive_for_test(&active, 3).exists());
        assert_eq!(backend.stats().submitted_records, 5);
        assert_eq!(backend.stats().submitted_bytes, 405);
        assert_eq!(backend.stats().written_records, 5);
        assert_eq!(backend.stats().written_bytes, 405);
    }

    #[test]
    fn memory_backend_close_drains_a_partial_batch() {
        let directory = TestDirectory::new("memory-close");
        {
            let settings = Settings::new(&directory.0, "close.log");
            let backend = Backend::open(settings).unwrap();
            backend.submit(b"drain on close\n").unwrap();
        }

        assert_eq!(
            fs::read(directory.0.join("close.log")).unwrap(),
            b"drain on close\n"
        );
    }

    #[test]
    fn tracing_adapter_submits_without_an_intermediate_queue() {
        let directory = TestDirectory::new("tracing");
        let settings = Settings::new(&directory.0, "tracing.log");
        let options = TracingOptions {
            console: false,
            ..TracingOptions::default()
        };
        let (dispatch, guard) = build_tracing(settings, options).unwrap();

        tracing::dispatcher::with_default(&dispatch, || {
            tracing::info!(event = "adapter_test", answer = 42, "tracing record");
        });
        guard.flush().unwrap();

        assert!(fs::read_to_string(directory.0.join("tracing.log"))
            .unwrap()
            .contains("tracing record"));
    }

    #[test]
    fn concurrent_producers_are_drained_without_loss() {
        let directory = TestDirectory::new("concurrent");
        let mut settings = Settings::new(&directory.0, "concurrent.log");
        settings.queue_capacity = 16;
        let backend = Backend::open(settings).unwrap();
        let mut producers = Vec::new();
        for producer in 0..8 {
            let backend = backend.clone();
            producers.push(std::thread::spawn(move || {
                for sequence in 0..200 {
                    let record = format!("producer={producer} sequence={sequence}\n");
                    backend.submit(record.as_bytes()).unwrap();
                }
            }));
        }
        for producer in producers {
            producer.join().unwrap();
        }
        backend.flush().unwrap();

        let contents = fs::read_to_string(directory.0.join("concurrent.log")).unwrap();
        assert_eq!(contents.lines().count(), 1600);
        assert_eq!(backend.stats().submitted_records, 1600);
        assert_eq!(backend.stats().written_records, 1600);
    }

    #[test]
    fn background_write_failure_is_reported() {
        if !PathBuf::from("/dev/full").exists() {
            return;
        }
        let mut settings = Settings::new("/dev", "full");
        settings.max_files = 1;
        let backend = Backend::open(settings).unwrap();
        backend.submit(b"cannot be persisted\n").unwrap();

        assert!(matches!(backend.flush(), Err(Error::Io(_))));
        assert_eq!(backend.stats().write_error_count, 1);
        assert!(matches!(
            backend.submit(b"later\n"),
            Err(Error::Background(_))
        ));
    }

    #[test]
    fn active_output_has_one_writer_owner() {
        let directory = TestDirectory::new("single-writer");
        let settings = Settings::new(&directory.0, "owned.log");
        let first = Backend::open(settings.clone()).unwrap();
        let error = match Backend::open(settings.clone()) {
            Ok(_) => panic!("second writer unexpectedly acquired the active log"),
            Err(error) => error,
        };
        assert!(matches!(
            error,
            Error::Io(ref io_error) if io_error.kind() == std::io::ErrorKind::WouldBlock
        ));
        drop(first);
        let second = Backend::open(settings).unwrap();
        second.submit(b"new owner\n").unwrap();
        second.flush().unwrap();
    }
}
