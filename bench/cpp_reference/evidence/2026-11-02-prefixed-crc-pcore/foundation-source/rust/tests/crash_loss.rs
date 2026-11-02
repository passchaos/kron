#![cfg(target_os = "linux")]

use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Read};
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

#[test]
fn sigkill_with_stalled_output_recovers_only_mmap_queue() {
    const RECORDS: usize = 6000;
    for mmap in [false, true] {
        let mode = if mmap { "mmap" } else { "memory" };
        let root = std::env::temp_dir().join(format!(
            "foundation-crash-integration-{}-{mode}",
            std::process::id()
        ));
        fs::create_dir_all(&root).unwrap();
        let output = root.join("app.log");
        let fifo = std::ffi::CString::new(output.as_os_str().as_encoded_bytes()).unwrap();
        assert_eq!(unsafe { libc::mkfifo(fifo.as_ptr(), 0o600) }, 0);
        let mut proxy = OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(&output)
            .unwrap();
        assert!(unsafe { libc::fcntl(proxy.as_raw_fd(), libc::F_SETPIPE_SZ, 4096) } >= 4096);
        let mut child = Command::new(env!("CARGO_BIN_EXE_crash_probe"))
            .args(["core", root.to_str().unwrap(), mode, "6000", "kill"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let mut ready = String::new();
        BufReader::new(child.stdout.take().unwrap())
            .read_line(&mut ready)
            .unwrap();
        assert!(ready.starts_with("READY 6000 "), "{ready}");
        let deadline = Instant::now() + Duration::from_secs(5);
        let mut previous = 0;
        let mut last_change = Instant::now();
        loop {
            let mut queued: libc::c_int = 0;
            assert_eq!(
                unsafe { libc::ioctl(proxy.as_raw_fd(), libc::FIONREAD, &mut queued) },
                0
            );
            if queued != previous {
                previous = queued;
                last_change = Instant::now();
            }
            if queued >= 3072 && last_change.elapsed() >= Duration::from_millis(10) {
                break;
            }
            if Instant::now() >= deadline {
                child.kill().unwrap();
                child.wait().unwrap();
                panic!("output proxy never filled");
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        child.kill().unwrap();
        assert_eq!(child.wait().unwrap().signal(), Some(libc::SIGKILL));
        let mut bytes = Vec::new();
        match proxy.read_to_end(&mut bytes) {
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {}
            Err(error) => panic!("{error}"),
        }
        assert!((3072..=4096).contains(&bytes.len()));
        assert_eq!(bytes.len() % 128, 0);
        drop(proxy);
        fs::remove_file(&output).unwrap();
        fs::write(&output, &bytes).unwrap();
        let status = Command::new(env!("CARGO_BIN_EXE_crash_probe"))
            .args(["recover", root.to_str().unwrap(), mode, "0", "normal"])
            .status()
            .unwrap();
        assert!(status.success());
        let content = fs::read_to_string(&output).unwrap();
        let mut seen = [false; RECORDS];
        for line in content.lines() {
            assert_eq!(line.len(), 127);
            assert!(line.starts_with("BEGIN id="));
            let sequence: usize = line[9..17].parse().unwrap();
            assert!(sequence < RECORDS);
            assert!(line.ends_with(&format!("END id={sequence:08}")));
            seen[sequence] = true;
        }
        let present = seen.into_iter().filter(|seen| *seen).count();
        assert_eq!(present, if mmap { RECORDS } else { 32 });
        fs::remove_dir_all(root).unwrap();
    }
}
