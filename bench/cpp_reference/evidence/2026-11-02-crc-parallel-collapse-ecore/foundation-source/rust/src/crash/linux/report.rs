use std::fs::File;
use std::os::fd::AsRawFd;
use std::ptr;

use super::super::FailureSignalOptions;

pub(super) struct ReportState {
    file: File,
    service: [u8; 256],
    service_len: usize,
    also_stderr: bool,
}

impl ReportState {
    pub(super) fn new(file: File, options: &FailureSignalOptions) -> Self {
        let mut service = [0; 256];
        service[..options.service_name.len()].copy_from_slice(options.service_name.as_bytes());
        Self {
            file,
            service,
            service_len: options.service_name.len(),
            also_stderr: options.also_stderr,
        }
    }

    pub(super) unsafe fn dump(
        &self,
        signal: libc::c_int,
        info: *mut libc::siginfo_t,
        context: *mut libc::c_void,
    ) {
        let mut time: libc::timespec = std::mem::zeroed();
        libc::clock_gettime(libc::CLOCK_REALTIME, &mut time);
        let mut buffer = Buffer::new();
        buffer.bytes(b"*** Foundation failure signal: ");
        buffer.bytes(signal_name(signal).as_bytes());
        buffer.bytes(b" ***\nservice=");
        buffer.bytes(&self.service[..self.service_len]);
        buffer.bytes(b" unix_time=");
        buffer.number(time.tv_sec as u64, 10);
        buffer.bytes(b" pid=");
        buffer.number(libc::getpid() as u64, 10);
        buffer.bytes(b" tid=");
        buffer.number(libc::syscall(libc::SYS_gettid) as u64, 10);
        buffer.bytes(b" signal_code=");
        let code = if info.is_null() { 0 } else { (*info).si_code };
        if code < 0 {
            buffer.bytes(b"-");
        }
        buffer.number(code.unsigned_abs() as u64, 10);
        buffer.bytes(b"\nfault_address=0x");
        let fault =
            if !info.is_null() && code > 0 && signal != libc::SIGABRT && signal != libc::SIGTERM {
                (*info).si_addr() as usize
            } else {
                0
            };
        buffer.number(fault as u64, 16);
        buffer.bytes(b" pc=0x");
        let fault_pc = program_counter(context);
        buffer.number(fault_pc as u64, 16);
        buffer.bytes(b"\nstack trace:\n");
        self.write(buffer.as_bytes());

        // Best effort only: libc unwinding/symbolization is not guaranteed
        // async-signal-safe even after initialization-time warmup. No Rust
        // Backtrace, formatting, allocation or logger is used here.
        let mut frames = [ptr::null_mut(); 64];
        let depth = libc::backtrace(frames.as_mut_ptr(), frames.len() as libc::c_int);
        if depth > 0 && depth <= frames.len() as libc::c_int {
            // Return addresses point after the call. At the end of an optimized
            // noreturn function this can fall outside its ELF symbol, so resolve
            // the preceding byte as glog does. Keep the faulting PC exact.
            for frame in &mut frames[..depth as usize] {
                if !frame.is_null() && *frame as usize != fault_pc {
                    *frame = (*frame as usize - 1) as *mut libc::c_void;
                }
            }
            libc::backtrace_symbols_fd(frames.as_ptr(), depth, self.file.as_raw_fd());
            if self.also_stderr {
                libc::backtrace_symbols_fd(frames.as_ptr(), depth, libc::STDERR_FILENO);
            }
        } else {
            self.write(b"(native stack unavailable)\n");
        }
        self.write(b"*** End Foundation failure report ***\n");
    }

    unsafe fn write(&self, bytes: &[u8]) {
        write_fd(self.file.as_raw_fd(), bytes);
        if self.also_stderr {
            write_fd(libc::STDERR_FILENO, bytes);
        }
    }
}

unsafe fn write_fd(fd: libc::c_int, bytes: &[u8]) {
    let mut offset = 0;
    while offset < bytes.len() {
        let count = libc::write(fd, bytes.as_ptr().add(offset).cast(), bytes.len() - offset);
        if count > 0 {
            offset += count as usize;
        } else if count < 0 && *libc::__errno_location() == libc::EINTR {
            continue;
        } else {
            break;
        }
    }
}

unsafe fn program_counter(context: *mut libc::c_void) -> usize {
    if context.is_null() {
        return 0;
    }
    let context = &*context.cast::<libc::ucontext_t>();
    #[cfg(target_arch = "aarch64")]
    return context.uc_mcontext.pc as usize;
    #[cfg(target_arch = "x86_64")]
    return context.uc_mcontext.gregs[libc::REG_RIP as usize] as usize;
}

pub(super) fn signal_name(signal: libc::c_int) -> &'static str {
    match signal {
        libc::SIGSEGV => "SIGSEGV",
        libc::SIGABRT => "SIGABRT",
        libc::SIGBUS => "SIGBUS",
        libc::SIGILL => "SIGILL",
        libc::SIGFPE => "SIGFPE",
        libc::SIGTERM => "SIGTERM",
        _ => "unknown signal",
    }
}

struct Buffer {
    bytes: [u8; 768],
    len: usize,
}

impl Buffer {
    fn new() -> Self {
        Self {
            bytes: [0; 768],
            len: 0,
        }
    }
    fn bytes(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            if self.len == self.bytes.len() {
                break;
            }
            self.bytes[self.len] = byte;
            self.len += 1;
        }
    }
    fn number(&mut self, mut number: u64, radix: u64) {
        let mut digits = [0; 20];
        let mut len = 0;
        loop {
            digits[len] = b"0123456789abcdef"[(number % radix) as usize];
            len += 1;
            number /= radix;
            if number == 0 {
                break;
            }
        }
        for index in (0..len).rev() {
            self.bytes(&digits[index..index + 1]);
        }
    }
    fn as_bytes(&self) -> &[u8] {
        &self.bytes[..self.len]
    }
}
