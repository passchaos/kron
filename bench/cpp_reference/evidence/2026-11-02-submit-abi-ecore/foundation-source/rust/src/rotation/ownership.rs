use std::ffi::OsString;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub(super) struct FileOwnership {
    _file: Option<File>,
}

impl FileOwnership {
    pub(super) fn acquire(active_path: &Path) -> io::Result<Self> {
        if fs::metadata(active_path).is_ok_and(|metadata| !metadata.file_type().is_file()) {
            return Ok(Self { _file: None });
        }
        let lock_path = lock_path(active_path);
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .mode(0o644)
            .open(&lock_path)?;
        loop {
            if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0 {
                break;
            }
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            if matches!(error.kind(), io::ErrorKind::WouldBlock) {
                let owner = owner_text(&mut file);
                return Err(io::Error::new(
                    io::ErrorKind::WouldBlock,
                    format!(
                        "active log {} is already owned{}",
                        active_path.display(),
                        owner
                            .filter(|value| !value.is_empty())
                            .map(|value| format!(" by {value}"))
                            .unwrap_or_default()
                    ),
                ));
            }
            return Err(error);
        }
        file.set_len(0)?;
        file.seek(SeekFrom::Start(0))?;
        writeln!(file, "pid={}", std::process::id())?;
        file.flush()?;
        Ok(Self { _file: Some(file) })
    }
}

fn owner_text(file: &mut File) -> Option<String> {
    file.seek(SeekFrom::Start(0)).ok()?;
    let mut owner = String::new();
    file.take(128).read_to_string(&mut owner).ok()?;
    Some(owner.trim().to_owned())
}

fn lock_path(active_path: &Path) -> PathBuf {
    let mut path: OsString = active_path.as_os_str().to_owned();
    path.push(".lock");
    PathBuf::from(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn ownership_is_exclusive_and_released_on_drop() {
        let sequence = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
        let directory = std::env::temp_dir().join(format!(
            "foundation-log-owner-{}-{sequence}",
            std::process::id()
        ));
        fs::create_dir_all(&directory).unwrap();
        let active = directory.join("service.log");
        let first = FileOwnership::acquire(&active).unwrap();
        let error = FileOwnership::acquire(&active).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::WouldBlock);
        assert!(error.to_string().contains("pid="));
        drop(first);
        let second = FileOwnership::acquire(&active).unwrap();
        drop(second);
        fs::remove_dir_all(directory).unwrap();
    }
}
