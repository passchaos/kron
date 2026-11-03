use std::collections::VecDeque;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Seek, SeekFrom, Write};
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::ptr::NonNull;
use std::sync::atomic::{AtomicU32, Ordering};

use crate::{Error, Result};

pub(crate) const HEADER_BYTES: usize = 4096;
pub(crate) const MIN_SLOT_BYTES: usize = 256;
pub(super) const SLOT_HEADER_BYTES: usize = 24;
pub(super) const MAGIC: &[u8; 8] = b"FLOGMM01";
pub(super) const FORMAT_VERSION: u32 = 1;
pub(super) const SLOT_FREE: u32 = 0;
pub(super) const SLOT_WRITING: u32 = 1;
pub(super) const SLOT_COMMITTED: u32 = 2;

#[derive(Debug)]
pub(super) struct PendingRecord {
    pub(super) index: usize,
    pub(super) sequence: u64,
    pub(super) payload: NonNull<u8>,
    pub(super) length: usize,
}

impl PendingRecord {
    pub(super) fn bytes(&self) -> &[u8] {
        // A committed slot is immutable until complete_batch marks it free.
        unsafe { std::slice::from_raw_parts(self.payload.as_ptr(), self.length) }
    }
}

pub(super) struct MappedFile {
    file: File,
    pub(super) pointer: NonNull<u8>,
    pub(super) length: usize,
}

// The mapping is protected by the owning backend's mutex. No pointer escapes.
unsafe impl Send for MappedFile {}

impl MappedFile {
    pub(super) fn open(path: &Path, length: usize) -> io::Result<(Self, bool)> {
        if let Some(directory) = path.parent() {
            fs::create_dir_all(directory)?;
        }
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(path)?;
        let lock_result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
        if lock_result != 0 {
            return Err(io::Error::last_os_error());
        }
        let existing_length = usize::try_from(file.metadata()?.len()).unwrap_or(usize::MAX);
        let is_new = existing_length == 0;
        if is_new {
            allocate_zeroed(&mut file, length)?;
        } else if existing_length != length {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("mmap spool size is {existing_length}, expected configured size {length}"),
            ));
        }
        #[cfg(target_os = "linux")]
        let map_flags = libc::MAP_SHARED | libc::MAP_POPULATE;
        #[cfg(not(target_os = "linux"))]
        let map_flags = libc::MAP_SHARED;
        let raw = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                length,
                libc::PROT_READ | libc::PROT_WRITE,
                map_flags,
                file.as_raw_fd(),
                0,
            )
        };
        if raw == libc::MAP_FAILED {
            return Err(io::Error::last_os_error());
        }
        Ok((
            Self {
                file,
                pointer: NonNull::new(raw.cast()).expect("mmap returned a null pointer"),
                length,
            },
            is_new,
        ))
    }

    pub(super) fn sync_header(&self) -> io::Result<()> {
        let result =
            unsafe { libc::msync(self.pointer.as_ptr().cast(), HEADER_BYTES, libc::MS_SYNC) };
        if result != 0 {
            return Err(io::Error::last_os_error());
        }
        self.file.sync_all()
    }
}

fn allocate_zeroed(file: &mut File, length: usize) -> io::Result<()> {
    let offset = libc::off_t::try_from(length)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "mmap spool is too large"))?;
    let result = loop {
        let result = unsafe { libc::posix_fallocate(file.as_raw_fd(), 0, offset) };
        if result != libc::EINTR {
            break result;
        }
    };
    if result == 0 {
        return Ok(());
    }
    if !matches!(result, libc::EOPNOTSUPP | libc::ENOSYS | libc::EINVAL) {
        let _ = file.set_len(0);
        return Err(io::Error::from_raw_os_error(result));
    }

    // Some filesystems do not implement fallocate. Sequential writes retain
    // the important property that ENOSPC is returned before the file is
    // mapped, instead of surfacing later as an uncatchable SIGBUS.
    allocate_zeroed_by_writing(file, length)
}

fn allocate_zeroed_by_writing(file: &mut File, length: usize) -> io::Result<()> {
    file.set_len(0)?;
    file.seek(SeekFrom::Start(0))?;
    let zeroes = [0u8; 1024 * 1024];
    let mut remaining = length;
    while remaining > 0 {
        let bytes = remaining.min(zeroes.len());
        if let Err(error) = file.write_all(&zeroes[..bytes]) {
            let _ = file.set_len(0);
            return Err(error);
        }
        remaining -= bytes;
    }
    file.sync_all()
}

impl Drop for MappedFile {
    fn drop(&mut self) {
        unsafe {
            libc::munmap(self.pointer.as_ptr().cast(), self.length);
        }
    }
}

pub(super) struct MmapSpool {
    mapping: MappedFile,
    slot_bytes: usize,
    slot_count: usize,
    head_index: usize,
    next_sequence: u64,
    pub(super) last_completed: u64,
    pub(super) pending: VecDeque<(usize, u64)>,
}

impl MmapSpool {
    pub(super) fn open(
        path: PathBuf,
        capacity_bytes: usize,
        slot_bytes: usize,
    ) -> io::Result<Self> {
        if slot_bytes < MIN_SLOT_BYTES || !slot_bytes.is_multiple_of(8) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "mmap slot size must be at least 256 bytes and aligned to 8 bytes",
            ));
        }
        if capacity_bytes < HEADER_BYTES + slot_bytes {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "mmap capacity must contain at least one slot",
            ));
        }
        let slot_count = (capacity_bytes - HEADER_BYTES) / slot_bytes;
        if slot_count > u32::MAX as usize || slot_bytes > u32::MAX as usize {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "mmap spool dimensions exceed the on-disk format",
            ));
        }
        let mapped_bytes = HEADER_BYTES + slot_count * slot_bytes;
        let (mapping, is_new) = MappedFile::open(&path, mapped_bytes)?;
        let mut spool = Self {
            mapping,
            slot_bytes,
            slot_count,
            head_index: 0,
            next_sequence: 1,
            last_completed: 0,
            pending: VecDeque::new(),
        };
        if is_new {
            spool.initialize_header()?;
        } else {
            spool.validate_header()?;
        }
        spool.recover();
        Ok(spool)
    }

    fn initialize_header(&mut self) -> io::Result<()> {
        unsafe {
            std::ptr::copy_nonoverlapping(
                MAGIC.as_ptr(),
                self.mapping.pointer.as_ptr(),
                MAGIC.len(),
            );
            write_u32(self.mapping.pointer.as_ptr().add(8), FORMAT_VERSION);
            write_u32(
                self.mapping.pointer.as_ptr().add(12),
                self.slot_bytes as u32,
            );
            write_u32(
                self.mapping.pointer.as_ptr().add(16),
                self.slot_count as u32,
            );
        }
        self.mapping.sync_header()
    }

    fn validate_header(&self) -> io::Result<()> {
        let header_magic = unsafe { std::slice::from_raw_parts(self.mapping.pointer.as_ptr(), 8) };
        let version = unsafe { read_u32(self.mapping.pointer.as_ptr().add(8)) };
        let slot_bytes = unsafe { read_u32(self.mapping.pointer.as_ptr().add(12)) as usize };
        let slot_count = unsafe { read_u32(self.mapping.pointer.as_ptr().add(16)) as usize };
        if header_magic != MAGIC
            || version != FORMAT_VERSION
            || slot_bytes != self.slot_bytes
            || slot_count != self.slot_count
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "mmap spool header does not match the configured format",
            ));
        }
        Ok(())
    }

    fn recover(&mut self) {
        let mut recovered = Vec::new();
        for index in 0..self.slot_count {
            match self.slot_state(index).load(Ordering::Acquire) {
                SLOT_COMMITTED => {
                    if let Some(sequence) = self.validate_slot(index) {
                        recovered.push((sequence, index));
                    } else {
                        self.slot_state(index).store(SLOT_FREE, Ordering::Release);
                    }
                }
                SLOT_FREE => {}
                _ => self.slot_state(index).store(SLOT_FREE, Ordering::Release),
            }
        }
        recovered.sort_unstable_by_key(|(sequence, _)| *sequence);
        if let Some((first_sequence, _)) = recovered.first() {
            self.last_completed = first_sequence.saturating_sub(1);
        }
        if let Some((last_sequence, last_index)) = recovered.last() {
            self.next_sequence = last_sequence.saturating_add(1);
            self.head_index = (last_index + 1) % self.slot_count;
        }
        self.pending = recovered
            .into_iter()
            .map(|(sequence, index)| (index, sequence))
            .collect();
    }

    pub(super) fn payload_capacity(&self) -> usize {
        self.slot_bytes - SLOT_HEADER_BYTES
    }

    #[cfg(test)]
    pub(super) fn commit(&mut self, record: &[u8]) -> Result<u64> {
        self.commit_with_crc_limit(record, record_crc(record), self.slot_count)
    }

    pub(super) fn commit_with_crc_limit(
        &mut self,
        record: &[u8],
        checksum: u32,
        maximum_pending: usize,
    ) -> Result<u64> {
        if record.len() > self.payload_capacity() {
            return Err(Error::RecordTooLarge {
                size: record.len(),
                maximum: self.payload_capacity(),
            });
        }
        // Pending includes the batch currently owned by the writer. No slot
        // becomes available before complete_batch has released it.
        if self.pending.len() >= maximum_pending.min(self.slot_count) {
            return Err(Error::QueueFull);
        }
        let mut index = self.head_index;
        while self.slot_state(index).load(Ordering::Acquire) != SLOT_FREE {
            index += 1;
            if index == self.slot_count {
                index = 0;
            }
            if index == self.head_index {
                return Err(Error::QueueFull);
            }
        }
        let sequence = self.next_sequence;
        self.next_sequence = self.next_sequence.saturating_add(1);
        let base = self.slot_pointer(index);
        self.slot_state(index)
            .store(SLOT_WRITING, Ordering::Relaxed);
        unsafe {
            write_u32(base.add(4), record.len() as u32);
            write_u64(base.add(8), sequence);
            write_u32(base.add(16), checksum);
            write_u32(base.add(20), 0);
            std::ptr::copy_nonoverlapping(
                record.as_ptr(),
                base.add(SLOT_HEADER_BYTES),
                record.len(),
            );
        }
        // The Release store publishes every preceding metadata and payload
        // write; a separate Release fence here would be redundant.
        self.slot_state(index)
            .store(SLOT_COMMITTED, Ordering::Release);
        self.pending.push_back((index, sequence));
        self.head_index = index + 1;
        if self.head_index == self.slot_count {
            self.head_index = 0;
        }
        Ok(sequence)
    }

    pub(super) fn peek_batch_into(&self, maximum_bytes: usize, batch: &mut Vec<PendingRecord>) {
        batch.clear();
        let mut bytes = 0;
        for (index, sequence) in &self.pending {
            let Some((stored_sequence, payload, length)) = self.slot_descriptor(*index) else {
                break;
            };
            if stored_sequence != *sequence {
                break;
            }
            if !batch.is_empty() && bytes + length > maximum_bytes {
                break;
            }
            bytes += length;
            batch.push(PendingRecord {
                index: *index,
                sequence: *sequence,
                payload,
                length,
            });
        }
    }

    pub(super) fn complete_batch(&mut self, batch: &[PendingRecord]) -> (usize, usize) {
        let mut records = 0usize;
        let mut bytes = 0usize;
        for record in batch {
            let Some((index, sequence)) = self.pending.pop_front() else {
                break;
            };
            debug_assert_eq!(index, record.index);
            debug_assert_eq!(sequence, record.sequence);
            self.slot_state(index).store(SLOT_FREE, Ordering::Release);
            self.last_completed = sequence;
            records += 1;
            bytes = bytes.saturating_add(record.length);
        }
        (records, bytes)
    }

    pub(super) fn last_submitted(&self) -> u64 {
        self.next_sequence.saturating_sub(1)
    }

    pub(super) fn slot_count(&self) -> usize {
        self.slot_count
    }

    fn slot_pointer(&self, index: usize) -> *mut u8 {
        unsafe {
            self.mapping
                .pointer
                .as_ptr()
                .add(HEADER_BYTES + index * self.slot_bytes)
        }
    }

    fn slot_state(&self, index: usize) -> &AtomicU32 {
        unsafe { &*self.slot_pointer(index).cast::<AtomicU32>() }
    }

    fn validate_slot(&self, index: usize) -> Option<u64> {
        let base = self.slot_pointer(index);
        let length = unsafe { read_u32(base.add(4)) as usize };
        if length > self.payload_capacity() {
            return None;
        }
        let sequence = unsafe { read_u64(base.add(8)) };
        let expected_crc = unsafe { read_u32(base.add(16)) };
        let bytes = unsafe { std::slice::from_raw_parts(base.add(SLOT_HEADER_BYTES), length) };
        if crc32(bytes) != expected_crc {
            return None;
        }
        Some(sequence)
    }

    fn slot_descriptor(&self, index: usize) -> Option<(u64, NonNull<u8>, usize)> {
        let base = self.slot_pointer(index);
        let length = unsafe { read_u32(base.add(4)) as usize };
        if length > self.payload_capacity() {
            return None;
        }
        let sequence = unsafe { read_u64(base.add(8)) };
        let payload = NonNull::new(unsafe { base.add(SLOT_HEADER_BYTES) })?;
        Some((sequence, payload, length))
    }
}

pub(super) unsafe fn write_u32(pointer: *mut u8, value: u32) {
    std::ptr::write_unaligned(pointer.cast::<u32>(), value.to_le());
}

pub(super) unsafe fn write_u64(pointer: *mut u8, value: u64) {
    std::ptr::write_unaligned(pointer.cast::<u64>(), value.to_le());
}

pub(super) unsafe fn read_u32(pointer: *const u8) -> u32 {
    u32::from_le(std::ptr::read_unaligned(pointer.cast::<u32>()))
}

pub(super) unsafe fn read_u64(pointer: *const u8) -> u64 {
    u64::from_le(std::ptr::read_unaligned(pointer.cast::<u64>()))
}

fn crc32(bytes: &[u8]) -> u32 {
    record_crc(bytes)
}

pub(super) fn record_crc(bytes: &[u8]) -> u32 {
    crc32fast::hash(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::Instant;

    static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(0);

    fn test_directory(name: &str) -> PathBuf {
        let sequence = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "foundation-mmap-{name}-{}-{sequence}",
            std::process::id()
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn committed_records_are_recovered_after_reopen() {
        let directory = test_directory("recover");
        let path = directory.join("spool.bin");
        {
            let mut spool = MmapSpool::open(path.clone(), HEADER_BYTES + 4 * 512, 512).unwrap();
            spool.commit(b"first\n").unwrap();
            spool.commit(b"second\n").unwrap();
        }
        let spool = MmapSpool::open(path, HEADER_BYTES + 4 * 512, 512).unwrap();
        let mut batch = Vec::new();
        spool.peek_batch_into(4096, &mut batch);
        assert_eq!(batch.len(), 2);
        assert_eq!(batch[0].bytes(), b"first\n");
        assert_eq!(batch[1].bytes(), b"second\n");
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn pending_limit_reserves_slots_for_critical_records() {
        let directory = test_directory("priority-reserve");
        let path = directory.join("spool.bin");
        let mut spool = MmapSpool::open(path, HEADER_BYTES + 2 * 512, 512).unwrap();
        spool
            .commit_with_crc_limit(b"normal\n", record_crc(b"normal\n"), 1)
            .unwrap();
        assert!(matches!(
            spool.commit_with_crc_limit(b"blocked\n", record_crc(b"blocked\n"), 1),
            Err(Error::QueueFull)
        ));
        spool
            .commit_with_crc_limit(b"critical\n", record_crc(b"critical\n"), 2)
            .unwrap();
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn incomplete_and_corrupt_records_are_ignored() {
        let directory = test_directory("corrupt");
        let path = directory.join("spool.bin");
        {
            let mut spool = MmapSpool::open(path.clone(), HEADER_BYTES + 2 * 512, 512).unwrap();
            spool.commit(b"valid\n").unwrap();
            spool.slot_state(1).store(SLOT_WRITING, Ordering::Release);
        }
        let spool = MmapSpool::open(path, HEADER_BYTES + 2 * 512, 512).unwrap();
        assert_eq!(spool.pending.len(), 1);
        assert_eq!(spool.slot_state(1).load(Ordering::Acquire), SLOT_FREE);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn full_spool_and_oversized_record_are_reported() {
        let directory = test_directory("limits");
        let path = directory.join("spool.bin");
        let mut spool = MmapSpool::open(path, HEADER_BYTES + 512, 512).unwrap();
        spool.commit(b"first").unwrap();

        assert!(matches!(spool.commit(b"second"), Err(Error::QueueFull)));
        assert!(matches!(
            spool.commit(&vec![b'x'; spool.payload_capacity() + 1]),
            Err(Error::RecordTooLarge { .. })
        ));
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn a_spool_has_one_process_owner() {
        let directory = test_directory("exclusive");
        let path = directory.join("spool.bin");
        let owner = MmapSpool::open(path.clone(), HEADER_BYTES + 512, 512).unwrap();
        assert!(MmapSpool::open(path, HEADER_BYTES + 512, 512).is_err());
        drop(owner);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn recovered_holes_wrap_and_full_batch_preserve_sequence() {
        let directory = test_directory("holes-and-wrap");
        let path = directory.join("spool.bin");
        {
            let mut spool = MmapSpool::open(path.clone(), HEADER_BYTES + 3 * 512, 512).unwrap();
            for record in [b"one\n".as_slice(), b"two\n", b"three\n"] {
                spool.commit(record).unwrap();
            }
            // Recovery must exclude the corrupt middle slot and still find
            // that hole when head points at an earlier committed record.
            unsafe { write_u32(spool.slot_pointer(1).add(16), 0) };
        }
        let mut spool = MmapSpool::open(path, HEADER_BYTES + 3 * 512, 512).unwrap();
        assert_eq!(spool.commit(b"four\n").unwrap(), 4);
        assert!(matches!(spool.commit(b"full\n"), Err(Error::QueueFull)));
        let mut batch = Vec::new();
        spool.peek_batch_into(4096, &mut batch);
        assert_eq!(
            batch
                .iter()
                .map(|record| record.sequence)
                .collect::<Vec<_>>(),
            [1, 3, 4]
        );
        assert_eq!(
            batch
                .iter()
                .map(|record| record.bytes())
                .collect::<Vec<_>>(),
            [b"one\n".as_slice(), b"three\n", b"four\n"]
        );
        assert_eq!(spool.complete_batch(&batch), (3, 15));
        for sequence in 5..20 {
            let record = format!("{sequence}\n");
            assert_eq!(spool.commit(record.as_bytes()).unwrap(), sequence);
            spool.peek_batch_into(4096, &mut batch);
            assert_eq!(batch[0].bytes(), record.as_bytes());
            spool.complete_batch(&batch);
        }
        drop(spool);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn allocation_fallback_zeroes_the_complete_file() {
        let directory = test_directory("allocation-fallback");
        let path = directory.join("spool.bin");
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .read(true)
            .write(true)
            .open(&path)
            .unwrap();
        let length = 1024 * 1024 + 37;
        allocate_zeroed_by_writing(&mut file, length).unwrap();
        file.seek(SeekFrom::Start(0)).unwrap();
        let mut bytes = Vec::new();
        file.read_to_end(&mut bytes).unwrap();
        assert_eq!(bytes.len(), length);
        assert!(bytes.iter().all(|byte| *byte == 0));
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn allocation_error_is_returned_before_mapping() {
        let directory = test_directory("allocation-error");
        let path = directory.join("spool.bin");
        fs::write(&path, b"").unwrap();
        let mut read_only = File::open(&path).unwrap();
        assert!(allocate_zeroed(&mut read_only, HEADER_BYTES + 512).is_err());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn benchmark_recovery_scan_when_requested() {
        if std::env::var_os("FOUNDATION_LOG_RUN_RECOVERY_BENCH").is_none() {
            return;
        }
        const SLOT_BYTES: usize = 1024;
        const SLOT_COUNT: usize = 65_536;
        let payload = vec![b'x'; 128];
        for percent in [0usize, 25, 50, 100] {
            let mut samples = Vec::new();
            for repetition in 0..5 {
                let directory = test_directory(&format!("recovery-{percent}-{repetition}"));
                let path = directory.join("spool.bin");
                {
                    let mut spool = MmapSpool::open(
                        path.clone(),
                        HEADER_BYTES + SLOT_COUNT * SLOT_BYTES,
                        SLOT_BYTES,
                    )
                    .unwrap();
                    for _ in 0..(SLOT_COUNT * percent / 100) {
                        spool.commit(&payload).unwrap();
                    }
                }
                let started = Instant::now();
                let recovered =
                    MmapSpool::open(path, HEADER_BYTES + SLOT_COUNT * SLOT_BYTES, SLOT_BYTES)
                        .unwrap();
                let elapsed = started.elapsed().as_secs_f64() * 1000.0;
                assert_eq!(recovered.pending.len(), SLOT_COUNT * percent / 100);
                samples.push(elapsed);
                drop(recovered);
                fs::remove_dir_all(directory).unwrap();
            }
            samples.sort_by(f64::total_cmp);
            println!(
                "{{\"occupancy_percent\":{percent},\"records\":{},\"scan_ms_median\":{}}}",
                SLOT_COUNT * percent / 100,
                samples[samples.len() / 2]
            );
        }
    }
}
