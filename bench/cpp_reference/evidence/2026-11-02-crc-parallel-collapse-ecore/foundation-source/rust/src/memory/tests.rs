use super::*;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

struct TestDirectory(PathBuf);

impl TestDirectory {
    fn new(name: &str) -> Self {
        let path =
            std::env::temp_dir().join(format!("foundation-memory-{name}-{}", std::process::id()));
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }
}

impl Drop for TestDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn wait_until(mut ready: impl FnMut() -> bool) -> bool {
    let deadline = Instant::now() + Duration::from_secs(3);
    while !ready() {
        if Instant::now() >= deadline {
            return false;
        }
        thread::sleep(Duration::from_millis(10));
    }
    true
}

#[test]
fn sparse_records_become_visible_without_explicit_flush() {
    let directory = TestDirectory::new("sparse");
    let backend = MemoryBackend::open(&Settings::new(&directory.0, "sparse.log")).unwrap();
    let output = directory.0.join("sparse.log");
    let mut expected = Vec::new();

    // Leave the backend open and idle after each small record. Neither the
    // queue threshold nor the file buffer capacity can make these visible.
    for record in [b"first\n".as_slice(), b"second\n".as_slice()] {
        backend.submit(record).unwrap();
        expected.extend_from_slice(record);
        assert!(
            wait_until(|| fs::read(&output).unwrap() == expected),
            "sparse log stayed in the output buffer"
        );
    }
}

#[test]
fn continuing_records_do_not_postpone_buffer_flush() {
    let directory = TestDirectory::new("continuing");
    let backend =
        Arc::new(MemoryBackend::open(&Settings::new(&directory.0, "continuing.log")).unwrap());
    let output = directory.0.join("continuing.log");
    let stop = Arc::new(AtomicBool::new(false));
    let producer_backend = Arc::clone(&backend);
    let producer_stop = Arc::clone(&stop);
    let producer = thread::spawn(move || {
        while !producer_stop.load(Ordering::Relaxed) {
            producer_backend.submit(b"record\n").unwrap();
            thread::sleep(Duration::from_millis(5));
        }
    });
    let visible = wait_until(|| !fs::read(&output).unwrap().is_empty());
    stop.store(true, Ordering::Relaxed);
    producer.join().unwrap();

    assert!(visible, "new records kept postponing the flush deadline");
}

#[cfg(target_os = "linux")]
#[test]
fn periodic_flush_failure_is_reported_to_later_calls() {
    let mut settings = Settings::new("/dev", "full");
    settings.max_files = 1;
    let backend = MemoryBackend::open(&settings).unwrap();
    backend.submit(b"cannot be persisted\n").unwrap();

    assert!(wait_until(|| backend.stats().write_error_count == 1));
    assert!(matches!(backend.flush(false), Err(Error::Background(_))));
    assert!(matches!(
        backend.submit(b"later\n"),
        Err(Error::Background(_))
    ));
}
