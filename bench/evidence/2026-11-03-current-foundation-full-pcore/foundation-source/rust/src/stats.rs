use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Stats {
    pub submitted_records: u64,
    pub submitted_bytes: u64,
    pub written_records: u64,
    pub written_bytes: u64,
    pub recovered_records: u64,
    pub queue_full_count: u64,
    pub write_error_count: u64,
}

#[derive(Default)]
pub(crate) struct AtomicStats {
    recovered_records: AtomicU64,
    queue_full_count: AtomicU64,
    write_error_count: AtomicU64,
}

impl AtomicStats {
    pub(crate) fn recovered(&self, records: usize) {
        self.recovered_records
            .fetch_add(records as u64, Ordering::Relaxed);
    }

    pub(crate) fn queue_full(&self) {
        self.queue_full_count.fetch_add(1, Ordering::Relaxed);
    }

    pub(crate) fn write_error(&self) {
        self.write_error_count.fetch_add(1, Ordering::Relaxed);
    }

    pub(crate) fn snapshot(&self) -> Stats {
        Stats {
            submitted_records: 0,
            submitted_bytes: 0,
            written_records: 0,
            written_bytes: 0,
            recovered_records: self.recovered_records.load(Ordering::Relaxed),
            queue_full_count: self.queue_full_count.load(Ordering::Relaxed),
            write_error_count: self.write_error_count.load(Ordering::Relaxed),
        }
    }
}
