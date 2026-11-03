use super::*;
use crate::{Backend, BackendMode, Settings};
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(0);

fn test_directory(name: &str) -> PathBuf {
    let sequence = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
    let path = std::env::temp_dir().join(format!(
        "foundation-mmap-backend-{name}-{}-{sequence}",
        std::process::id()
    ));
    fs::create_dir_all(&path).unwrap();
    path
}

#[test]
fn backend_writes_committed_records() {
    let directory = test_directory("write");
    let mut settings = Settings::new(&directory, "mmap.log");
    settings.mode = BackendMode::Mmap {
        spool_path: directory.join("mmap.spool"),
        capacity_bytes: HEADER_BYTES + 8 * 512,
        slot_bytes: 512,
    };
    let backend = Backend::open(settings).unwrap();
    backend.submit(b"persistent record\n").unwrap();
    backend.flush().unwrap();
    assert_eq!(
        fs::read(directory.join("mmap.log")).unwrap(),
        b"persistent record\n"
    );
    let stats = backend.stats();
    assert_eq!(stats.submitted_records, 1);
    assert_eq!(stats.submitted_bytes, 18);
    assert_eq!(stats.written_records, 1);
    assert_eq!(stats.written_bytes, 18);
    drop(backend);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn committed_record_survives_abrupt_process_exit() {
    let directory = test_directory("process-crash");
    let spool_path = directory.join("spool.bin");
    let output_path = directory.join("recovered.log");
    let status = Command::new(std::env::current_exe().unwrap())
        .arg("--exact")
        .arg("mmap::tests::crash_writer_child")
        .arg("--nocapture")
        .env("FOUNDATION_LOG_CRASH_SPOOL", &spool_path)
        .status()
        .unwrap();
    assert_eq!(status.code(), Some(23));

    let mut settings = Settings::new(&directory, "recovered.log");
    settings.mode = BackendMode::Mmap {
        spool_path,
        capacity_bytes: HEADER_BYTES + 4 * 512,
        slot_bytes: 512,
    };
    let backend = Backend::open(settings).unwrap();
    backend.flush().unwrap();
    assert_eq!(backend.stats().recovered_records, 1);
    assert_eq!(backend.stats().submitted_records, 0);
    assert_eq!(backend.stats().written_records, 1);
    drop(backend);

    assert_eq!(fs::read(output_path).unwrap(), b"survives crash\n");
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn crash_writer_child() {
    let Some(path) = std::env::var_os("FOUNDATION_LOG_CRASH_SPOOL") else {
        return;
    };
    let mut spool = MmapSpool::open(PathBuf::from(path), HEADER_BYTES + 4 * 512, 512).unwrap();
    spool.commit(b"survives crash\n").unwrap();
    unsafe { libc::_exit(23) }
}

#[test]
fn output_failure_keeps_the_record_recoverable() {
    if !PathBuf::from("/dev/full").exists() {
        return;
    }
    let directory = test_directory("output-failure");
    let spool_path = directory.join("spool.bin");
    let mut failing = Settings::new("/dev", "full");
    failing.max_files = 1;
    failing.mode = BackendMode::Mmap {
        spool_path: spool_path.clone(),
        capacity_bytes: HEADER_BYTES + 4 * 512,
        slot_bytes: 512,
    };
    let backend = Backend::open(failing).unwrap();
    backend.submit(b"retry after failure\n").unwrap();
    assert!(matches!(backend.flush(), Err(Error::Background(_))));
    assert_eq!(backend.stats().write_error_count, 1);
    drop(backend);

    let mut recovery = Settings::new(&directory, "recovered.log");
    recovery.mode = BackendMode::Mmap {
        spool_path,
        capacity_bytes: HEADER_BYTES + 4 * 512,
        slot_bytes: 512,
    };
    let recovered = Backend::open(recovery).unwrap();
    assert_eq!(recovered.stats().recovered_records, 1);
    recovered.flush().unwrap();
    drop(recovered);
    assert_eq!(
        fs::read(directory.join("recovered.log")).unwrap(),
        b"retry after failure\n"
    );
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn sparse_submissions_wake_writer_without_flush() {
    let directory = test_directory("sparse-wake");
    let mut settings = Settings::new(&directory, "records.log");
    settings.mode = BackendMode::Mmap {
        spool_path: directory.join("records.spool"),
        capacity_bytes: HEADER_BYTES + 2 * 512,
        slot_bytes: 512,
    };
    let backend = Backend::open(settings).unwrap();
    let mut expected = String::new();
    for sequence in 0..100u64 {
        let record = format!("{sequence}\n");
        expected.push_str(&record);
        backend.submit(record.as_bytes()).unwrap();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        while backend.stats().written_records <= sequence {
            assert!(
                std::time::Instant::now() < deadline,
                "writer missed an empty-to-nonempty notification"
            );
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }
    backend.flush_durable().unwrap();
    assert_eq!(
        fs::read_to_string(directory.join("records.log")).unwrap(),
        expected
    );
    drop(backend);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn concurrent_producers_make_progress_with_two_slots() {
    let directory = test_directory("two-slot-backpressure");
    let mut settings = Settings::new(&directory, "records.log");
    settings.mode = BackendMode::Mmap {
        spool_path: directory.join("records.spool"),
        capacity_bytes: HEADER_BYTES + 2 * 512,
        slot_bytes: 512,
    };
    let backend = MmapBackend::open(&settings).unwrap();
    std::thread::scope(|scope| {
        for producer in 0..4 {
            let backend = &backend;
            scope.spawn(move || {
                for sequence in 0..500 {
                    backend
                        .submit(format!("{producer}:{sequence}\n").as_bytes())
                        .unwrap();
                }
            });
        }
    });
    backend.flush(false).unwrap();
    let contents = fs::read_to_string(directory.join("records.log")).unwrap();
    let mut next_sequence = [0; 4];
    for line in contents.lines() {
        let (producer, sequence) = line.split_once(':').unwrap();
        let producer = producer.parse::<usize>().unwrap();
        assert_eq!(sequence.parse::<usize>().unwrap(), next_sequence[producer]);
        next_sequence[producer] += 1;
    }
    assert_eq!(next_sequence, [500; 4]);
    assert_eq!(backend.stats().submitted_records, 2000);
    assert_eq!(backend.stats().written_records, 2000);
    assert_eq!(backend.stats().written_bytes, contents.len() as u64);
    assert_eq!(backend.shared.state.lock().waiting_producers, 0);
    drop(backend);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn output_failure_releases_capacity_waiters() {
    if !PathBuf::from("/dev/full").exists() {
        return;
    }
    let directory = test_directory("capacity-waiter-error");
    let mut settings = Settings::new("/dev", "full");
    settings.max_files = 1;
    settings.mode = BackendMode::Mmap {
        spool_path: directory.join("records.spool"),
        capacity_bytes: HEADER_BYTES + 512,
        slot_bytes: 512,
    };
    let backend = MmapBackend::open(&settings).unwrap();
    let results = std::thread::scope(|scope| {
        let producers = (0..16)
            .map(|_| scope.spawn(|| backend.submit(b"must remain recoverable\n")))
            .collect::<Vec<_>>();
        producers
            .into_iter()
            .map(|thread| thread.join().unwrap())
            .collect::<Vec<_>>()
    });
    assert_eq!(results.iter().filter(|result| result.is_ok()).count(), 1);
    assert!(results
        .iter()
        .filter(|result| result.is_err())
        .all(|result| { matches!(result, Err(Error::Background(_))) }));
    assert!(matches!(backend.flush(false), Err(Error::Background(_))));
    assert_eq!(backend.stats().write_error_count, 1);
    assert_eq!(backend.stats().written_records, 0);
    let state = backend.shared.state.lock();
    assert_eq!(state.waiting_producers, 0);
    assert_eq!(state.spool.pending.len(), 1);
    drop(state);
    drop(backend);
    fs::remove_dir_all(directory).unwrap();
}
