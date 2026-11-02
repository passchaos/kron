use std::sync::Arc;

use crate::memory::MemoryBackend;
use crate::mmap::MmapBackend;
use crate::stats::Stats;
use crate::{Error, Result, Settings};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Priority {
    Normal,
    Critical,
}

// Native log calls have no acceptance result. A full nonblocking queue drops
// the new record; the raw Backend/C API retains QueueFull and its statistics.
pub(crate) fn discard_if_full(result: Result<()>) -> Result<()> {
    match result {
        Err(Error::QueueFull) => Ok(()),
        result => result,
    }
}

pub(crate) trait BackendImpl: Send + Sync {
    fn submit_with_priority(&self, record: &[u8], priority: Priority) -> Result<()>;
    fn maximum_record_bytes(&self) -> usize;
    #[cfg(test)]
    fn submit(&self, record: &[u8]) -> Result<()> {
        self.submit_with_priority(record, Priority::Normal)
    }
    fn flush(&self, durable: bool) -> Result<()>;
    fn stats(&self) -> Stats;
}

#[derive(Clone)]
enum BackendInner {
    Memory(Arc<MemoryBackend>),
    Mmap(Arc<MmapBackend>),
}

impl BackendInner {
    fn submit_with_priority(&self, record: &[u8], priority: Priority) -> Result<()> {
        match self {
            Self::Memory(backend) => backend.submit_with_priority(record, priority),
            Self::Mmap(backend) => backend.submit_with_priority(record, priority),
        }
    }

    fn maximum_record_bytes(&self) -> usize {
        match self {
            Self::Memory(backend) => backend.maximum_record_bytes(),
            Self::Mmap(backend) => backend.maximum_record_bytes(),
        }
    }

    fn flush(&self, durable: bool) -> Result<()> {
        match self {
            Self::Memory(backend) => backend.flush(durable),
            Self::Mmap(backend) => backend.flush(durable),
        }
    }

    fn stats(&self) -> Stats {
        match self {
            Self::Memory(backend) => backend.stats(),
            Self::Mmap(backend) => backend.stats(),
        }
    }
}

#[derive(Clone)]
pub struct Backend {
    inner: BackendInner,
    maximum_record_bytes: usize,
}

impl Backend {
    pub fn open(settings: Settings) -> Result<Self> {
        settings.validate()?;
        let inner = match &settings.mode {
            crate::BackendMode::Memory => {
                BackendInner::Memory(Arc::new(MemoryBackend::open(&settings)?))
            }
            crate::BackendMode::Mmap { .. } => {
                BackendInner::Mmap(Arc::new(MmapBackend::open(&settings)?))
            }
        };
        let maximum_record_bytes = inner.maximum_record_bytes();
        Ok(Self {
            inner,
            maximum_record_bytes,
        })
    }

    pub fn submit(&self, record: &[u8]) -> Result<()> {
        self.submit_with_priority(record, Priority::Normal)
    }

    pub fn submit_with_priority(&self, record: &[u8], priority: Priority) -> Result<()> {
        self.inner.submit_with_priority(record, priority)
    }

    pub fn submit_critical(&self, record: &[u8]) -> Result<()> {
        self.submit_with_priority(record, Priority::Critical)
    }

    /// Native adapters preserve a bounded prefix and append an explicit marker
    /// when a formatted record cannot fit the backend.
    pub fn submit_native(&self, record: &[u8], priority: Priority) -> Result<()> {
        let maximum = self.maximum_record_bytes;
        if record.len() <= maximum {
            return self.inner.submit_with_priority(record, priority);
        }
        self.inner
            .submit_with_priority(&truncate_record(record, maximum), priority)
    }

    pub fn flush(&self) -> Result<()> {
        self.inner.flush(false)
    }

    pub fn flush_durable(&self) -> Result<()> {
        self.inner.flush(true)
    }

    pub fn stats(&self) -> Stats {
        self.inner.stats()
    }
}

fn truncate_record(record: &[u8], maximum: usize) -> Vec<u8> {
    let marker = format!(
        "...[foundation-log truncated original_bytes={}]\n",
        record.len()
    );
    if marker.len() <= maximum {
        let prefix = maximum - marker.len();
        let mut truncated = Vec::with_capacity(maximum);
        truncated.extend_from_slice(&record[..prefix]);
        truncated.extend_from_slice(marker.as_bytes());
        return truncated;
    }
    if maximum >= 4 {
        return b"...\n".to_vec();
    }
    let mut truncated = vec![b'.'; maximum];
    if let Some(last) = truncated.last_mut() {
        *last = b'\n';
    }
    truncated
}

#[cfg(test)]
mod tests {
    use super::truncate_record;

    #[test]
    fn truncation_preserves_bound_and_reports_original_size() {
        let record = vec![b'x'; 1024];
        let truncated = truncate_record(&record, 128);
        assert_eq!(truncated.len(), 128);
        assert!(truncated.ends_with(b"[foundation-log truncated original_bytes=1024]\n"));
    }
}
