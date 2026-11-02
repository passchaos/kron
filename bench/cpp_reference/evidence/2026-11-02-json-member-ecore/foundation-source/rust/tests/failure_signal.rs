#![cfg(all(
    target_os = "linux",
    target_env = "gnu",
    any(target_arch = "aarch64", target_arch = "x86_64")
))]

use std::fs::{self, File, OpenOptions};
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};
use std::time::{Duration, Instant};

use foundation_logging_core::crash::{
    install_failure_signal_handler, is_failure_signal_handler_installed,
    uninstall_failure_signal_handler, FailureSignalOptions,
};
use foundation_logging_core::{Backend, Settings};

fn child_case(case: &str) -> (ExitStatus, String, String) {
    let root = std::env::temp_dir().join(format!(
        "foundation-failure-signal-{}-{case}",
        std::process::id()
    ));
    fs::create_dir_all(&root).unwrap();
    let stderr = File::create(root.join("stderr.log")).unwrap();
    let mut child = Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "failure_signal_child", "--nocapture"])
        .env("FOUNDATION_FAILURE_CASE", case)
        .env("FOUNDATION_FAILURE_ROOT", &root)
        .stderr(Stdio::from(stderr))
        .stdout(Stdio::null())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(8);
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status;
        }
        if Instant::now() >= deadline {
            child.kill().unwrap();
            child.wait().unwrap();
            panic!("{case}: failure handler hung");
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let report = fs::read_to_string(root.join("failure.log")).unwrap_or_default();
    let stderr = fs::read_to_string(root.join("stderr.log")).unwrap();
    fs::remove_dir_all(root).unwrap();
    (status, report, stderr)
}

#[test]
fn fatal_signals_report_and_keep_the_original_exit_signal() {
    for (case, signal, name) in [
        ("abort", libc::SIGABRT, "SIGABRT"),
        ("segv", libc::SIGSEGV, "SIGSEGV"),
        ("bus", libc::SIGBUS, "SIGBUS"),
        ("ill", libc::SIGILL, "SIGILL"),
        ("fpe", libc::SIGFPE, "SIGFPE"),
        ("term", libc::SIGTERM, "SIGTERM"),
        ("worker", libc::SIGABRT, "SIGABRT"),
        ("closed-stderr", libc::SIGABRT, "SIGABRT"),
        ("blocked-output", libc::SIGABRT, "SIGABRT"),
    ] {
        let (status, report, stderr) = child_case(case);
        assert_eq!(status.signal(), Some(signal), "{case}: {status}");
        assert!(report.contains(name), "{case}: {report}");
        assert!(report.contains("service=rust-failure unix_time="));
        assert!(report.contains(" pid=") && report.contains(" tid="));
        assert!(report.contains(" pc=0x") && !report.contains(" pc=0x0\n"));
        assert!(report.contains("stack trace:\n") && report.lines().count() > 5);
        assert!(report.ends_with("*** End Foundation failure report ***\n"));
        if case != "closed-stderr" {
            assert_eq!(report, stderr, "{case}");
        }
        if case == "worker" {
            let header = report.lines().nth(1).unwrap();
            let pid = header
                .split("pid=")
                .nth(1)
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap();
            let tid = header
                .split("tid=")
                .nth(1)
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap();
            assert_ne!(pid, tid, "worker report used the main thread ID");
        }
    }
}

#[test]
fn process_registration_has_an_independent_and_reversible_lifetime() {
    let (status, _, stderr) = child_case("lifecycle");
    assert!(status.success(), "{stderr}");
}

unsafe fn action(signal: libc::c_int) -> libc::sigaction {
    let mut action = std::mem::zeroed();
    assert_eq!(libc::sigaction(signal, std::ptr::null(), &mut action), 0);
    action
}

extern "C" fn first_handler(_: libc::c_int) {}
extern "C" fn later_handler(_: libc::c_int) {}

fn lifecycle(root: &Path, mut options: FailureSignalOptions) {
    unsafe {
        libc::signal(libc::SIGABRT, first_handler as *const () as usize);
    }
    let original_segv = unsafe { action(libc::SIGSEGV) };
    options.replace_existing = false;
    assert!(install_failure_signal_handler(options.clone()).is_err());
    assert!(!is_failure_signal_handler_installed());
    assert_eq!(
        unsafe { action(libc::SIGSEGV) }.sa_sigaction,
        original_segv.sa_sigaction
    );
    assert!(!root.join("failure.log").exists());

    let descriptors = fs::read_dir("/proc/self/fd").unwrap().count();
    options.replace_existing = true;
    let term = unsafe { action(libc::SIGTERM) };
    install_failure_signal_handler(options.clone()).unwrap();
    assert!(is_failure_signal_handler_installed());
    assert_eq!(
        unsafe { action(libc::SIGTERM) }.sa_sigaction,
        term.sa_sigaction
    );
    install_failure_signal_handler(options.clone()).unwrap();
    let mut different = options.clone();
    different.service_name = "different".into();
    assert!(install_failure_signal_handler(different).is_err());
    let backend = Backend::open(Settings::new(root, "normal.log")).unwrap();
    backend.submit(b"normal log\n").unwrap();
    drop(backend);
    assert!(is_failure_signal_handler_installed());
    unsafe {
        libc::signal(libc::SIGABRT, later_handler as *const () as usize);
    }
    assert!(!is_failure_signal_handler_installed());
    uninstall_failure_signal_handler().unwrap();
    assert_eq!(
        unsafe { action(libc::SIGABRT) }.sa_sigaction,
        later_handler as *const () as usize
    );
    assert_eq!(
        unsafe { action(libc::SIGSEGV) }.sa_sigaction,
        original_segv.sa_sigaction
    );
    uninstall_failure_signal_handler().unwrap();
    assert_eq!(fs::read_dir("/proc/self/fd").unwrap().count(), descriptors);

    install_failure_signal_handler(options).unwrap();
    uninstall_failure_signal_handler().unwrap();
    assert_eq!(
        unsafe { action(libc::SIGABRT) }.sa_sigaction,
        later_handler as *const () as usize
    );
}

#[test]
fn failure_signal_child() {
    let Ok(case) = std::env::var("FOUNDATION_FAILURE_CASE") else {
        return;
    };
    let root = std::path::PathBuf::from(std::env::var_os("FOUNDATION_FAILURE_ROOT").unwrap());
    unsafe {
        let limit = libc::rlimit {
            rlim_cur: 0,
            rlim_max: 0,
        };
        assert_eq!(libc::setrlimit(libc::RLIMIT_CORE, &limit), 0);
    }
    let mut options = FailureSignalOptions::new("rust-failure", root.join("failure.log"));
    // Rust std installs its own SIGSEGV/SIGBUS stack-overflow handlers. This
    // isolated executable deliberately delegates fatal signals to Foundation.
    options.replace_existing = true;
    options.include_sigterm = case == "term";
    if case == "lifecycle" {
        lifecycle(&root, options);
        return;
    }
    install_failure_signal_handler(options).unwrap();
    match case.as_str() {
        "segv" => unsafe {
            let memory = libc::mmap(
                std::ptr::null_mut(),
                4096,
                libc::PROT_NONE,
                libc::MAP_PRIVATE | libc::MAP_ANONYMOUS,
                -1,
                0,
            );
            assert_ne!(memory, libc::MAP_FAILED);
            std::ptr::write_volatile(memory.cast::<u8>(), 1);
        },
        "worker" => {
            std::thread::spawn(|| std::process::abort()).join().unwrap();
        }
        "closed-stderr" => unsafe {
            let mut pipe = [0; 2];
            assert_eq!(libc::pipe(pipe.as_mut_ptr()), 0);
            libc::close(pipe[0]);
            assert_eq!(
                libc::dup2(pipe[1], libc::STDERR_FILENO),
                libc::STDERR_FILENO
            );
            libc::close(pipe[1]);
            std::process::abort();
        },
        "blocked-output" => {
            let output = root.join("output.log");
            let name = std::ffi::CString::new(output.as_os_str().as_encoded_bytes()).unwrap();
            assert_eq!(unsafe { libc::mkfifo(name.as_ptr(), 0o600) }, 0);
            let proxy = OpenOptions::new()
                .read(true)
                .write(true)
                .custom_flags(libc::O_NONBLOCK)
                .open(&output)
                .unwrap();
            assert_eq!(
                unsafe { libc::fcntl(proxy.as_raw_fd(), libc::F_SETPIPE_SZ, 4096) },
                4096
            );
            let backend = Backend::open(Settings::new(&root, "output.log")).unwrap();
            for _ in 0..6000 {
                backend.submit(&[b'x'; 128]).unwrap();
            }
            let deadline = Instant::now() + Duration::from_secs(3);
            loop {
                let mut queued: libc::c_int = 0;
                assert_eq!(
                    unsafe { libc::ioctl(proxy.as_raw_fd(), libc::FIONREAD, &mut queued) },
                    0
                );
                if queued == 4096 {
                    break;
                }
                assert!(Instant::now() < deadline, "normal output never stalled");
                std::thread::sleep(Duration::from_millis(1));
            }
            std::process::abort();
        }
        _ => {
            let signal = match case.as_str() {
                "bus" => libc::SIGBUS,
                "ill" => libc::SIGILL,
                "fpe" => libc::SIGFPE,
                "term" => libc::SIGTERM,
                "abort" => libc::SIGABRT,
                _ => panic!("unknown case"),
            };
            unsafe {
                libc::raise(signal);
            }
        }
    }
    panic!("fatal signal returned");
}
