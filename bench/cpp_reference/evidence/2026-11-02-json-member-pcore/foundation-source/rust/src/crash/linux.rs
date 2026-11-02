mod report;

use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::unix::fs::OpenOptionsExt;
use std::ptr;
use std::sync::atomic::{AtomicI32, AtomicPtr, AtomicUsize, Ordering};
use std::sync::Mutex;

use super::FailureSignalOptions;
use crate::{Error, Result};
use report::ReportState;

const FAILURE_SIGNALS: [libc::c_int; 5] = [
    libc::SIGSEGV,
    libc::SIGABRT,
    libc::SIGBUS,
    libc::SIGILL,
    libc::SIGFPE,
];

// The handler never locks INSTALLED. REPORT points to immutable, preallocated
// state. SeqCst ordering with ACTIVE prevents freeing state acquired by a
// concurrently entering handler during teardown.
static INSTALLED: Mutex<Option<Installation>> = Mutex::new(None);
static REPORT: AtomicPtr<ReportState> = AtomicPtr::new(ptr::null_mut());
static ACTIVE: AtomicUsize = AtomicUsize::new(0);
static FIRST_SIGNAL: AtomicI32 = AtomicI32::new(0);

struct Installation {
    options: FailureSignalOptions,
    _report: Box<ReportState>,
    previous: Vec<(libc::c_int, libc::sigaction)>,
}

fn action(signal: libc::c_int) -> io::Result<libc::sigaction> {
    let mut current = unsafe { std::mem::zeroed() };
    if unsafe { libc::sigaction(signal, ptr::null(), &mut current) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(current)
}

fn is_ours(action: &libc::sigaction) -> bool {
    action.sa_flags & libc::SA_SIGINFO != 0
        && action.sa_sigaction == failure_handler as *const () as usize
}

fn restore(signal: libc::c_int, previous: &libc::sigaction) -> io::Result<()> {
    if is_ours(&action(signal)?)
        && unsafe { libc::sigaction(signal, previous, ptr::null_mut()) } != 0
    {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

pub(super) fn install(options: FailureSignalOptions) -> Result<()> {
    let mut installed = INSTALLED.lock().unwrap_or_else(|p| p.into_inner());
    if let Some(existing) = installed.as_ref() {
        if existing.options == options
            && existing
                .previous
                .iter()
                .all(|(signal, _)| action(*signal).is_ok_and(|current| is_ours(&current)))
        {
            return Ok(());
        }
        return Err(Error::InvalidInput(
            "failure signal installation already exists; uninstall before changing it".into(),
        ));
    }
    let mut signals = FAILURE_SIGNALS.to_vec();
    if options.include_sigterm {
        signals.push(libc::SIGTERM);
    }
    // Check every signal before modifying any of them, including handlers from
    // glog, faulthandler or another statically linked copy of the Rust core.
    for &signal in &signals {
        if action(signal)?.sa_sigaction != libc::SIG_DFL && !options.replace_existing {
            return Err(Error::InvalidInput(format!(
                "{} already has a signal handler",
                report::signal_name(signal)
            )));
        }
    }
    if let Some(parent) = options
        .report_path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
    {
        fs::create_dir_all(parent)?;
    }
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o644)
        .custom_flags(libc::O_CLOEXEC | libc::O_NONBLOCK)
        .open(&options.report_path)?;
    if !file.metadata()?.is_file() {
        return Err(Error::InvalidInput(
            "failure report must be a regular file".into(),
        ));
    }
    let mut frames = [ptr::null_mut(); 16];
    let null = File::options().write(true).open("/dev/null")?;
    use std::os::fd::AsRawFd;
    unsafe {
        // Resolve lazy unwinder/symbol output dependencies while ordinary code
        // can still allocate and acquire loader locks.
        let depth = libc::backtrace(frames.as_mut_ptr(), frames.len() as libc::c_int);
        libc::backtrace_symbols_fd(frames.as_ptr(), depth, null.as_raw_fd());
    }
    let mut registration = Installation {
        _report: Box::new(ReportState::new(file, &options)),
        options,
        previous: Vec::with_capacity(signals.len()),
    };
    ACTIVE.store(0, Ordering::SeqCst);
    FIRST_SIGNAL.store(0, Ordering::SeqCst);
    REPORT.store(&mut *registration._report, Ordering::SeqCst);
    let mut handler: libc::sigaction = unsafe { std::mem::zeroed() };
    handler.sa_sigaction = failure_handler as *const () as usize;
    handler.sa_flags = libc::SA_SIGINFO | libc::SA_ONSTACK | libc::SA_NODEFER;
    unsafe {
        libc::sigemptyset(&mut handler.sa_mask);
        // Writing to a closed stderr pipe must not replace the failure signal
        // with SIGPIPE. The process will terminate with the original signal.
        libc::sigaddset(&mut handler.sa_mask, libc::SIGPIPE);
    }
    for signal in signals {
        let mut previous = unsafe { std::mem::zeroed() };
        let error = if unsafe { libc::sigaction(signal, &handler, &mut previous) } != 0 {
            Some(Error::Io(io::Error::last_os_error()))
        } else {
            registration.previous.push((signal, previous));
            (previous.sa_sigaction != libc::SIG_DFL && !registration.options.replace_existing)
                .then(|| Error::InvalidInput("signal handler changed during installation".into()))
        };
        if let Some(error) = error {
            let mut rollback_ok = true;
            for (signal, previous) in registration.previous.iter().rev() {
                rollback_ok &= restore(*signal, previous).is_ok();
            }
            if rollback_ok {
                REPORT.store(ptr::null_mut(), Ordering::SeqCst);
            }
            if !rollback_ok || ACTIVE.load(Ordering::SeqCst) != 0 {
                // Keep descriptors and immutable state alive if rollback was
                // incomplete or a fatal handler already acquired them.
                *installed = Some(registration);
            }
            return Err(error);
        }
    }
    *installed = Some(registration);
    Ok(())
}

pub(super) fn uninstall() -> Result<()> {
    let mut installed = INSTALLED.lock().unwrap_or_else(|p| p.into_inner());
    let Some(registration) = installed.as_ref() else {
        return Ok(());
    };
    if ACTIVE.load(Ordering::SeqCst) != 0 {
        return Err(Error::InvalidInput(
            "failure signal handler is executing".into(),
        ));
    }
    let mut error = None;
    for (signal, previous) in registration.previous.iter().rev() {
        if let Err(failure) = restore(*signal, previous) {
            error = Some(failure);
        }
    }
    if let Some(error) = error {
        return Err(Error::Io(error));
    }
    REPORT.store(ptr::null_mut(), Ordering::SeqCst);
    if ACTIVE.load(Ordering::SeqCst) != 0 {
        return Err(Error::InvalidInput(
            "failure signal handler is executing".into(),
        ));
    }
    *installed = None;
    Ok(())
}

pub(super) fn is_installed() -> bool {
    let installed = INSTALLED.lock().unwrap_or_else(|p| p.into_inner());
    installed.as_ref().is_some_and(|registration| {
        registration
            .previous
            .iter()
            .all(|(signal, _)| action(*signal).is_ok_and(|current| is_ours(&current)))
    })
}

unsafe extern "C" fn failure_handler(
    signal: libc::c_int,
    info: *mut libc::siginfo_t,
    context: *mut libc::c_void,
) {
    ACTIVE.fetch_add(1, Ordering::SeqCst);
    if let Err(first) = FIRST_SIGNAL.compare_exchange(0, signal, Ordering::SeqCst, Ordering::SeqCst)
    {
        // A fault in the reporter itself must not change the original failure
        // signal or recursively attempt logging/unwinding.
        terminate(first);
    }
    let report = REPORT.load(Ordering::SeqCst);
    if !report.is_null() {
        (*report).dump(signal, info, context);
    }
    terminate(signal);
}

unsafe fn terminate(signal: libc::c_int) -> ! {
    let mut default: libc::sigaction = std::mem::zeroed();
    libc::sigemptyset(&mut default.sa_mask);
    default.sa_sigaction = libc::SIG_DFL;
    libc::sigaction(signal, &default, ptr::null_mut());
    let mut unblocked: libc::sigset_t = std::mem::zeroed();
    libc::sigemptyset(&mut unblocked);
    libc::sigaddset(&mut unblocked, signal);
    libc::sigprocmask(libc::SIG_UNBLOCK, &unblocked, ptr::null_mut());
    // Re-deliver to this thread, preserving WTERMSIG and the core dump policy.
    libc::syscall(
        libc::SYS_tgkill,
        libc::getpid(),
        libc::syscall(libc::SYS_gettid),
        signal,
    );
    libc::_exit(128 + signal);
}
