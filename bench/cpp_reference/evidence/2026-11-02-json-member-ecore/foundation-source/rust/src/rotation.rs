mod ownership;

use std::fs::{self, File, OpenOptions};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};

const BUFFERED_RECORD_WRITE_MIN_BYTES: usize = 1024;

pub(crate) struct RotatingFile {
    _ownership: ownership::FileOwnership,
    active_path: PathBuf,
    writer: Option<BufWriter<File>>,
    bytes_written: u64,
    max_bytes: u64,
    max_files: usize,
    buffer_bytes: usize,
}

impl RotatingFile {
    pub(crate) fn from_settings(settings: &crate::Settings) -> io::Result<Self> {
        Self::open(
            settings.active_path(),
            settings.max_file_bytes,
            settings.max_files,
            settings.write_buffer_bytes,
        )
    }

    pub(crate) fn open(
        active_path: PathBuf,
        max_bytes: u64,
        max_files: usize,
        buffer_bytes: usize,
    ) -> io::Result<Self> {
        if let Some(directory) = active_path.parent() {
            fs::create_dir_all(directory)?;
        }
        let ownership = ownership::FileOwnership::acquire(&active_path)?;
        prune_excess_archives(&active_path, max_files)?;
        let file = open_active_file(&active_path)?;
        let bytes_written = file.metadata()?.len();
        Ok(Self {
            _ownership: ownership,
            active_path,
            writer: Some(BufWriter::with_capacity(buffer_bytes, file)),
            bytes_written,
            max_bytes,
            max_files,
            buffer_bytes,
        })
    }

    pub(crate) fn write_record(&mut self, record: &[u8]) -> io::Result<()> {
        let record_bytes = u64::try_from(record.len()).unwrap_or(u64::MAX);
        if self.bytes_written > 0
            && (self.bytes_written >= self.max_bytes
                || self.bytes_written.saturating_add(record_bytes) > self.max_bytes)
        {
            self.rotate()?;
        }
        self.writer_mut()?.write_all(record)?;
        self.bytes_written = self.bytes_written.saturating_add(record_bytes);
        Ok(())
    }

    pub(crate) fn write_records(&mut self, bytes: &[u8], ends: &[usize]) -> io::Result<()> {
        let batch_bytes = u64::try_from(bytes.len()).unwrap_or(u64::MAX);
        if !ends.is_empty()
            && !bytes.is_empty()
            && self.bytes_written < self.max_bytes
            && self.bytes_written.saturating_add(batch_bytes) <= self.max_bytes
        {
            self.writer_mut()?.write_all(bytes)?;
            self.bytes_written = self.bytes_written.saturating_add(batch_bytes);
            return Ok(());
        }

        // Large records already amortize the call overhead. Feeding them to
        // BufWriter individually preserves its configured write granularity;
        // one multi-megabyte slice would bypass that buffer and regresses the
        // 1-4 KiB workload on the target filesystem.
        if !ends.is_empty() && bytes.len() / ends.len() >= BUFFERED_RECORD_WRITE_MIN_BYTES {
            let mut start = 0usize;
            for &end in ends {
                self.write_record(&bytes[start..end])?;
                start = end;
            }
            return Ok(());
        }

        let mut start = 0usize;
        let mut record_index = 0usize;
        while record_index < ends.len() {
            let first_end = ends[record_index];
            let first_bytes = u64::try_from(first_end.saturating_sub(start)).unwrap_or(u64::MAX);
            if self.bytes_written > 0
                && (self.bytes_written >= self.max_bytes
                    || self.bytes_written.saturating_add(first_bytes) > self.max_bytes)
            {
                self.rotate()?;
            }

            let group_start = start;
            let mut group_end = first_end;
            let mut projected_bytes = self.bytes_written.saturating_add(first_bytes);
            record_index += 1;
            while record_index < ends.len() {
                let next_end = ends[record_index];
                let next_bytes =
                    u64::try_from(next_end.saturating_sub(group_end)).unwrap_or(u64::MAX);
                if projected_bytes >= self.max_bytes
                    || projected_bytes.saturating_add(next_bytes) > self.max_bytes
                {
                    break;
                }
                group_end = next_end;
                projected_bytes = projected_bytes.saturating_add(next_bytes);
                record_index += 1;
            }

            self.writer_mut()?
                .write_all(&bytes[group_start..group_end])?;
            self.bytes_written = projected_bytes;
            start = group_end;
        }
        Ok(())
    }

    pub(crate) fn flush(&mut self) -> io::Result<()> {
        self.writer_mut()?.flush()
    }

    pub(crate) fn sync_data(&mut self) -> io::Result<()> {
        self.flush()?;
        self.writer_mut()?.get_ref().sync_data()
    }

    fn rotate(&mut self) -> io::Result<()> {
        if let Some(mut writer) = self.writer.take() {
            writer.flush()?;
        }
        if self.max_files == 1 {
            remove_if_present(&self.active_path)?;
        } else {
            remove_if_present(&archive_path(&self.active_path, self.max_files - 1))?;
            for index in (1..self.max_files - 1).rev() {
                let source = archive_path(&self.active_path, index);
                if source.exists() {
                    fs::rename(source, archive_path(&self.active_path, index + 1))?;
                }
            }
            if self.active_path.exists() {
                fs::rename(&self.active_path, archive_path(&self.active_path, 1))?;
            }
        }
        let file = open_active_file(&self.active_path)?;
        self.writer = Some(BufWriter::with_capacity(self.buffer_bytes, file));
        self.bytes_written = 0;
        Ok(())
    }

    fn writer_mut(&mut self) -> io::Result<&mut BufWriter<File>> {
        self.writer
            .as_mut()
            .ok_or_else(|| io::Error::other("log writer is not open"))
    }
}

fn open_active_file(path: &Path) -> io::Result<File> {
    OpenOptions::new().create(true).append(true).open(path)
}

fn archive_path(active_path: &Path, index: usize) -> PathBuf {
    let mut archive = active_path.as_os_str().to_owned();
    archive.push(format!(".{index}"));
    PathBuf::from(archive)
}

fn remove_if_present(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn prune_excess_archives(active_path: &Path, max_files: usize) -> io::Result<()> {
    let Some(directory) = active_path.parent() else {
        return Ok(());
    };
    let Some(active_name) = active_path.file_name().and_then(|name| name.to_str()) else {
        return Ok(());
    };
    let archive_prefix = format!("{active_name}.");
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        if !entry.file_type()?.is_file() {
            continue;
        }
        let Some(file_name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        let Some(index) = file_name
            .strip_prefix(&archive_prefix)
            .and_then(|suffix| suffix.parse::<usize>().ok())
        else {
            continue;
        };
        if index >= max_files {
            fs::remove_file(entry.path())?;
        }
    }
    Ok(())
}

#[cfg(test)]
pub(crate) fn archive_for_test(active_path: &Path, index: usize) -> PathBuf {
    archive_path(active_path, index)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn startup_removes_archives_beyond_the_total_file_limit() {
        let directory =
            std::env::temp_dir().join(format!("foundation-rotation-prune-{}", std::process::id()));
        let _ = fs::remove_dir_all(&directory);
        fs::create_dir_all(&directory).unwrap();
        let active = directory.join("service.log");
        fs::write(&active, b"active").unwrap();
        fs::write(archive_path(&active, 2), b"keep").unwrap();
        fs::write(archive_path(&active, 3), b"remove").unwrap();

        let _file = RotatingFile::open(active.clone(), 64, 3, 64).unwrap();

        assert!(archive_path(&active, 2).exists());
        assert!(!archive_path(&active, 3).exists());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn one_total_file_keeps_only_the_newest_record() {
        let directory =
            std::env::temp_dir().join(format!("foundation-rotation-single-{}", std::process::id()));
        let _ = fs::remove_dir_all(&directory);
        fs::create_dir_all(&directory).unwrap();
        let active = directory.join("service.log");
        let mut file = RotatingFile::open(active.clone(), 8, 1, 64).unwrap();

        file.write_record(b"first").unwrap();
        file.write_record(b"second").unwrap();
        file.flush().unwrap();

        assert_eq!(fs::read(&active).unwrap(), b"second");
        assert!(!archive_path(&active, 1).exists());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn batch_write_rotates_only_between_records() {
        let directory =
            std::env::temp_dir().join(format!("foundation-rotation-batch-{}", std::process::id()));
        let _ = fs::remove_dir_all(&directory);
        fs::create_dir_all(&directory).unwrap();
        let active = directory.join("service.log");
        let mut file = RotatingFile::open(active.clone(), 8, 3, 64).unwrap();

        file.write_records(b"aaaabbbbcccc", &[4, 8, 12]).unwrap();
        file.flush().unwrap();

        assert_eq!(fs::read(&active).unwrap(), b"cccc");
        assert_eq!(fs::read(archive_path(&active, 1)).unwrap(), b"aaaabbbb");
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn whole_batch_fast_path_preserves_exact_rotation_boundary() {
        let directory = std::env::temp_dir().join(format!(
            "foundation-rotation-whole-batch-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&directory);
        fs::create_dir_all(&directory).unwrap();
        let active = directory.join("service.log");
        let mut file = RotatingFile::open(active.clone(), 6, 3, 64).unwrap();

        file.write_record(b"aa").unwrap();
        file.write_records(b"bbcc", &[2, 4]).unwrap();
        file.write_records(b"dd", &[2]).unwrap();
        file.flush().unwrap();

        assert_eq!(fs::read(&active).unwrap(), b"dd");
        assert_eq!(fs::read(archive_path(&active, 1)).unwrap(), b"aabbcc");
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn large_batch_fallback_rotates_only_between_records() {
        let directory = std::env::temp_dir().join(format!(
            "foundation-rotation-large-batch-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&directory);
        fs::create_dir_all(&directory).unwrap();
        let active = directory.join("service.log");
        let mut file = RotatingFile::open(active.clone(), 1024, 2, 256).unwrap();
        let mut bytes = vec![b'a'; 1024];
        bytes.extend(std::iter::repeat_n(b'b', 1024));

        file.write_records(&bytes, &[1024, 2048]).unwrap();
        file.flush().unwrap();

        assert_eq!(fs::read(&active).unwrap(), vec![b'b'; 1024]);
        assert_eq!(
            fs::read(archive_path(&active, 1)).unwrap(),
            vec![b'a'; 1024]
        );
        fs::remove_dir_all(directory).unwrap();
    }
}
