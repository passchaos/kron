mod queue;
#[cfg(test)]
mod tests;

use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use queue::{BoundedQueue, RecordBatch, Work};

use crate::backend::BackendImpl;
use crate::rotation::RotatingFile;
use crate::stats::{AtomicStats, Stats};
use crate::Priority;
use crate::{Error, Result, Settings};

const MAX_WRITE_BATCH_RECORDS: usize = 4 * 1024;
const MIN_WRITE_BATCH_BYTES: usize = 1024 * 1024;
const BUFFER_FLUSH_INTERVAL: Duration = Duration::from_secs(1);

pub(crate) struct MemoryBackend {
    queue: Arc<BoundedQueue>,
    worker: Mutex<Option<JoinHandle<()>>>,
    stats: Arc<AtomicStats>,
    block_when_full: bool,
}

impl MemoryBackend {
    pub(crate) fn open(settings: &Settings) -> Result<Self> {
        let batch_records = settings.queue_capacity.min(MAX_WRITE_BATCH_RECORDS);
        let batch_bytes = settings
            .write_buffer_bytes
            .max(MIN_WRITE_BATCH_BYTES)
            .min(settings.queue_capacity_bytes);
        let queue = Arc::new(BoundedQueue::new(
            settings.queue_capacity,
            settings.queue_capacity_bytes,
            settings.effective_critical_reserve_records(settings.queue_capacity),
            settings.effective_critical_reserve_bytes(settings.queue_capacity_bytes),
            batch_records,
            batch_bytes,
        ));
        let worker_queue = Arc::clone(&queue);
        let stats = Arc::new(AtomicStats::default());
        let worker_stats = Arc::clone(&stats);
        let file = RotatingFile::from_settings(settings)?;
        let worker = thread::Builder::new()
            .name("foundation-log-writer".to_owned())
            .spawn(move || {
                run_writer(worker_queue, worker_stats, file, batch_records, batch_bytes);
            })?;
        Ok(Self {
            queue,
            worker: Mutex::new(Some(worker)),
            stats,
            block_when_full: settings.block_when_full,
        })
    }
}

impl BackendImpl for MemoryBackend {
    fn submit_with_priority(&self, record: &[u8], priority: Priority) -> Result<()> {
        self.submit_record(record, priority)
    }

    fn flush(&self, durable: bool) -> Result<()> {
        let result = self.queue.request_flush(durable)?;
        result.recv().map_err(|_| self.queue.closed_error())?
    }

    fn maximum_record_bytes(&self) -> usize {
        self.queue.maximum_record_bytes()
    }

    fn stats(&self) -> Stats {
        let mut stats = self.stats.snapshot();
        let queue_stats = self.queue.stats();
        stats.submitted_records = queue_stats.submitted_records;
        stats.submitted_bytes = queue_stats.submitted_bytes;
        stats.written_records = queue_stats.written_records;
        stats.written_bytes = queue_stats.written_bytes;
        stats
    }
}

impl MemoryBackend {
    fn submit_record(&self, record: &[u8], priority: Priority) -> Result<()> {
        match self.queue.submit(record, self.block_when_full, priority) {
            Ok(()) => Ok(()),
            Err(Error::QueueFull) => {
                self.stats.queue_full();
                Err(Error::QueueFull)
            }
            Err(error) => Err(error),
        }
    }
}

fn run_writer(
    queue: Arc<BoundedQueue>,
    stats: Arc<AtomicStats>,
    mut file: RotatingFile,
    batch_records: usize,
    batch_bytes: usize,
) {
    let mut batch = RecordBatch::with_capacity(batch_records, batch_bytes);
    let mut flush_deadline = None;
    loop {
        match queue.take_work(&mut batch, flush_deadline) {
            Work::Records => {
                let records = batch.len();
                let write_result = file
                    .write_records(batch.bytes(), batch.ends())
                    .map(|()| batch.byte_len())
                    .map_err(Error::from);
                let bytes = match write_result {
                    Ok(bytes) => bytes,
                    Err(error) => {
                        stats.write_error();
                        queue.fail(error.to_string());
                        batch.clear();
                        queue.finish_batch(0, 0);
                        break;
                    }
                };
                // Further batches must not postpone the oldest buffered bytes.
                flush_deadline.get_or_insert_with(|| Instant::now() + BUFFER_FLUSH_INTERVAL);
                batch.clear();
                queue.finish_batch(records, bytes);
            }
            Work::PeriodicFlush => {
                if let Err(error) = file.flush() {
                    stats.write_error();
                    queue.fail(error.to_string());
                    break;
                }
                // With no new writes the worker can sleep without a timer.
                flush_deadline = None;
            }
            Work::Flush(request) => {
                let result = if request.durable {
                    file.sync_data()
                } else {
                    file.flush()
                }
                .map_err(Error::from);
                if let Err(error) = &result {
                    stats.write_error();
                    queue.fail(error.to_string());
                }
                let failed = result.is_err();
                let _ = request.reply.send(result);
                if failed {
                    break;
                }
                flush_deadline = None;
            }
            Work::Shutdown => {
                if let Err(error) = file.flush() {
                    stats.write_error();
                    queue.fail(error.to_string());
                }
                break;
            }
        }
    }
}

impl Drop for MemoryBackend {
    fn drop(&mut self) {
        self.queue.close();
        if let Ok(worker) = self.worker.get_mut() {
            if let Some(worker) = worker.take() {
                let _ = worker.join();
            }
        }
    }
}
