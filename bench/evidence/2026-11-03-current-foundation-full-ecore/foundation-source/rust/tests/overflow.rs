#![cfg(target_os = "linux")]

use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::process::Command;
use std::time::{Duration, Instant};

use foundation_logging_core::{
    build_tracing, BackendMode, Error, Settings, TracingMakeWriter, TracingOptions,
};
use tracing_subscriber::fmt::MakeWriter;

#[test]
fn nonblocking_frontends_drop_only_new_records() {
    for mode in ["memory", "mmap"] {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "nonblocking_overflow_child", "--nocapture"])
            .env("FOUNDATION_OVERFLOW_CASE", mode)
            .spawn()
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            if let Some(status) = child.try_wait().unwrap() {
                assert!(status.success(), "{mode}: {status}");
                break;
            }
            if Instant::now() >= deadline {
                child.kill().unwrap();
                child.wait().unwrap();
                panic!("{mode}: overflow child blocked");
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }
}

fn read_record(proxy: &mut fs::File) -> Vec<u8> {
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut bytes = Vec::new();
    let mut buffer = [0; 4096];
    while !bytes.contains(&b'\n') {
        match proxy.read(&mut buffer) {
            Ok(count) => bytes.extend_from_slice(&buffer[..count]),
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                assert!(Instant::now() < deadline, "writer did not complete record");
                std::thread::sleep(Duration::from_millis(1));
            }
            result => panic!("{result:?}"),
        }
    }
    bytes
}

#[test]
fn nonblocking_overflow_child() {
    let Ok(mode) = std::env::var("FOUNDATION_OVERFLOW_CASE") else {
        return;
    };
    let root =
        std::env::temp_dir().join(format!("foundation-overflow-{}-{mode}", std::process::id()));
    fs::create_dir_all(&root).unwrap();
    let output = root.join("app.log");
    let path = std::ffi::CString::new(output.as_os_str().as_encoded_bytes()).unwrap();
    assert_eq!(unsafe { libc::mkfifo(path.as_ptr(), 0o600) }, 0);
    let mut proxy = OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(&output)
        .unwrap();
    assert_eq!(
        unsafe { libc::fcntl(proxy.as_raw_fd(), libc::F_SETPIPE_SZ, 4096) },
        4096
    );
    let mut settings = Settings::new(&root, "app.log");
    settings.queue_capacity = 1;
    settings.queue_capacity_bytes = 32 * 1024;
    settings.write_buffer_bytes = 1;
    settings.block_when_full = false;
    let spool_path = root.join("app.spool");
    let capacity_bytes = 4096 + 16 * 1024;
    let slot_bytes = 16 * 1024;
    settings.mode = match mode.as_str() {
        "memory" => BackendMode::Memory,
        "mmap" => BackendMode::Mmap {
            spool_path,
            capacity_bytes,
            slot_bytes,
        },
        _ => unreachable!(),
    };
    let (dispatch, guard) = build_tracing(
        settings,
        TracingOptions {
            console: false,
            default_filter: "info",
            ..TracingOptions::default()
        },
    )
    .unwrap();
    let backend = guard.backend().clone();
    let mut retained = vec![b'a'; 8192];
    retained.push(b'\n');
    backend.submit(&retained).unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let mut queued: libc::c_int = 0;
        assert_eq!(
            unsafe { libc::ioctl(proxy.as_raw_fd(), libc::FIONREAD, &mut queued) },
            0
        );
        if queued == 4096 {
            break;
        }
        assert!(Instant::now() < deadline, "writer did not fill proxy");
        std::thread::sleep(Duration::from_millis(1));
    }
    tracing::dispatcher::with_default(&dispatch, || {
        for _ in 0..3 {
            tracing::info!("discard-me");
        }
    });
    let maker = TracingMakeWriter::new(backend.clone());
    let mut writer = maker.make_writer();
    writer.write_all(b"discard-public\n").unwrap();
    writer.flush().unwrap();
    assert!(matches!(
        backend.submit(b"discard-raw\n"),
        Err(Error::QueueFull)
    ));
    let stats = backend.stats();
    assert_eq!(stats.submitted_records, 1);
    assert_eq!(stats.written_records, 0);
    assert_eq!(stats.queue_full_count, 5);
    assert_eq!(stats.write_error_count, 0);
    assert_eq!(read_record(&mut proxy), retained);
    backend.flush().unwrap();
    tracing::dispatcher::with_default(&dispatch, || tracing::info!("resumed"));
    backend.flush().unwrap();
    let resumed = String::from_utf8(read_record(&mut proxy)).unwrap();
    assert!(resumed.contains("resumed"));
    assert!(!resumed.contains("discard"));
    assert_eq!(backend.stats().submitted_records, 2);
    assert_eq!(backend.stats().written_records, 2);
    drop(writer);
    drop(maker);
    drop(dispatch);
    drop(guard);
    drop(backend);
    drop(proxy);
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn native_oversized_record_is_marked_but_raw_submit_remains_strict() {
    let root =
        std::env::temp_dir().join(format!("foundation-overflow-error-{}", std::process::id()));
    let mut settings = Settings::new(&root, "app.log");
    settings.block_when_full = false;
    settings.queue_capacity_bytes = 4;
    let backend = foundation_logging_core::Backend::open(settings).unwrap();
    let maker = TracingMakeWriter::new(backend.clone());
    let mut writer = maker.make_writer();
    writer.write_all(b"oversized\n").unwrap();
    writer.flush().unwrap();
    assert!(matches!(
        backend.submit(b"oversized\n"),
        Err(Error::RecordTooLarge { .. })
    ));
    backend.flush().unwrap();
    assert_eq!(fs::read(root.join("app.log")).unwrap(), b"...\n");
    assert_eq!(backend.stats().submitted_records, 1);
    assert_eq!(backend.stats().queue_full_count, 0);
    drop(writer);
    drop(maker);
    drop(backend);
    fs::remove_dir_all(root).unwrap();
}
