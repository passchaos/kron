mod spool;

use std::collections::VecDeque;
use std::sync::Arc;
use std::thread::{self, JoinHandle};

use parking_lot::{Condvar, Mutex};

use crate::backend::BackendImpl;
use crate::config::BackendMode;
use crate::rotation::RotatingFile;
use crate::stats::{AtomicStats, Stats};
use crate::Priority;
use crate::{Error, Result, Settings};
use spool::{record_crc, MmapSpool};

pub(crate) use spool::{HEADER_BYTES, MIN_SLOT_BYTES};

const BATCH_BYTES: usize = 256 * 1024;

struct FlushRequest {
    target_sequence: u64,
    durable: bool,
    reply: std::sync::mpsc::Sender<Result<()>>,
}

struct MmapState {
    spool: MmapSpool,
    submitted_records: u64,
    submitted_bytes: u64,
    written_records: u64,
    written_bytes: u64,
    // Registration and notification share this mutex with slot completion.
    waiting_producers: usize,
    flush_requests: VecDeque<FlushRequest>,
    shutdown: bool,
    background_error: Option<String>,
}

struct Shared {
    state: Mutex<MmapState>,
    work: Condvar,
    progress: Condvar,
    stats: Arc<AtomicStats>,
    block_when_full: bool,
    normal_slot_capacity: usize,
    maximum_record_bytes: usize,
}

pub(crate) struct MmapBackend {
    shared: Arc<Shared>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

impl MmapBackend {
    pub(crate) fn open(settings: &Settings) -> Result<Self> {
        let BackendMode::Mmap {
            spool_path,
            capacity_bytes,
            slot_bytes,
        } = &settings.mode
        else {
            return Err(Error::InvalidInput("mmap settings are required".to_owned()));
        };
        let spool = MmapSpool::open(spool_path.clone(), *capacity_bytes, *slot_bytes)?;
        let normal_slot_capacity =
            spool.slot_count() - settings.effective_critical_reserve_records(spool.slot_count());
        let maximum_record_bytes = spool.payload_capacity();
        let recovered_records = spool.pending.len();
        let stats = Arc::new(AtomicStats::default());
        stats.recovered(recovered_records);
        let shared = Arc::new(Shared {
            state: Mutex::new(MmapState {
                spool,
                submitted_records: 0,
                submitted_bytes: 0,
                written_records: 0,
                written_bytes: 0,
                waiting_producers: 0,
                flush_requests: VecDeque::new(),
                shutdown: false,
                background_error: None,
            }),
            work: Condvar::new(),
            progress: Condvar::new(),
            stats,
            block_when_full: settings.block_when_full,
            normal_slot_capacity,
            maximum_record_bytes,
        });
        let worker_shared = Arc::clone(&shared);
        let mut file = RotatingFile::from_settings(settings)?;
        let worker = thread::Builder::new()
            .name("foundation-mmap-log-writer".to_owned())
            .spawn(move || mmap_worker(&worker_shared, &mut file))?;
        shared.work.notify_one();
        Ok(Self {
            shared,
            worker: Mutex::new(Some(worker)),
        })
    }
}

impl BackendImpl for MmapBackend {
    fn submit_with_priority(&self, record: &[u8], priority: Priority) -> Result<()> {
        let checksum = record_crc(record);
        let mut state = self.shared.state.lock();
        loop {
            if let Some(error) = &state.background_error {
                return Err(Error::Background(error.clone()));
            }
            let wake_writer = state.spool.pending.is_empty();
            let maximum_pending = match priority {
                Priority::Normal => self.shared.normal_slot_capacity,
                Priority::Critical => state.spool.slot_count(),
            };
            match state
                .spool
                .commit_with_crc_limit(record, checksum, maximum_pending)
            {
                Ok(_) => {
                    state.submitted_records = state.submitted_records.saturating_add(1);
                    state.submitted_bytes =
                        state.submitted_bytes.saturating_add(record.len() as u64);
                    if wake_writer {
                        self.shared.work.notify_one();
                    }
                    return Ok(());
                }
                Err(Error::QueueFull) if self.shared.block_when_full => {
                    self.shared.stats.queue_full();
                    state.waiting_producers += 1;
                    self.shared.progress.wait(&mut state);
                    state.waiting_producers -= 1;
                }
                Err(Error::QueueFull) => {
                    self.shared.stats.queue_full();
                    return Err(Error::QueueFull);
                }
                Err(error) => return Err(error),
            }
        }
    }

    fn flush(&self, durable: bool) -> Result<()> {
        let (reply_sender, reply_receiver) = std::sync::mpsc::channel();
        let mut state = self.shared.state.lock();
        if let Some(error) = &state.background_error {
            return Err(Error::Background(error.clone()));
        }
        let target_sequence = state.spool.last_submitted();
        state.flush_requests.push_back(FlushRequest {
            target_sequence,
            durable,
            reply: reply_sender,
        });
        self.shared.work.notify_one();
        drop(state);
        reply_receiver.recv().map_err(|_| Error::Closed)?
    }

    fn maximum_record_bytes(&self) -> usize {
        self.shared.maximum_record_bytes
    }

    fn stats(&self) -> Stats {
        let mut stats = self.shared.stats.snapshot();
        let state = self.shared.state.lock();
        stats.submitted_records = state.submitted_records;
        stats.submitted_bytes = state.submitted_bytes;
        stats.written_records = state.written_records;
        stats.written_bytes = state.written_bytes;
        stats
    }
}

impl Drop for MmapBackend {
    fn drop(&mut self) {
        {
            let mut state = self.shared.state.lock();
            state.shutdown = true;
            self.shared.work.notify_one();
        }
        if let Some(worker) = self.worker.get_mut().take() {
            let _ = worker.join();
        }
    }
}

fn mmap_worker(shared: &Shared, file: &mut RotatingFile) {
    let mut batch = Vec::new();
    loop {
        enum Work {
            Batch,
            Flush(Vec<FlushRequest>),
            Shutdown,
        }

        let work = {
            let mut state = shared.state.lock();
            loop {
                let ready_to_flush = state
                    .flush_requests
                    .front()
                    .is_some_and(|request| request.target_sequence <= state.spool.last_completed);
                if ready_to_flush {
                    let mut requests = Vec::new();
                    while state.flush_requests.front().is_some_and(|request| {
                        request.target_sequence <= state.spool.last_completed
                    }) {
                        requests.push(state.flush_requests.pop_front().unwrap());
                    }
                    break Work::Flush(requests);
                }
                if !state.spool.pending.is_empty() {
                    state.spool.peek_batch_into(BATCH_BYTES, &mut batch);
                    break Work::Batch;
                }
                if state.shutdown {
                    break Work::Shutdown;
                }
                shared.work.wait(&mut state);
            }
        };

        let result = match &work {
            Work::Batch => {
                let write_result = batch
                    .iter()
                    .try_for_each(|record| file.write_record(record.bytes()));
                write_result.and_then(|()| file.flush())
            }
            Work::Flush(requests) => {
                if requests.iter().any(|request| request.durable) {
                    file.sync_data()
                } else {
                    file.flush()
                }
            }
            Work::Shutdown => file.flush(),
        };

        if let Err(error) = result {
            shared.stats.write_error();
            let message = error.to_string();
            let mut state = shared.state.lock();
            state.background_error = Some(message.clone());
            for request in state.flush_requests.drain(..) {
                let _ = request.reply.send(Err(Error::Background(message.clone())));
            }
            shared.progress.notify_all();
            break;
        }

        match work {
            Work::Batch => {
                let mut state = shared.state.lock();
                let (records, bytes) = state.spool.complete_batch(&batch);
                state.written_records = state.written_records.saturating_add(records as u64);
                state.written_bytes = state.written_bytes.saturating_add(bytes as u64);
                if state.waiting_producers != 0 {
                    shared.progress.notify_all();
                }
                batch.clear();
                // Only this writer waits on work; it will check pending again.
            }
            Work::Flush(requests) => {
                for request in requests {
                    let _ = request.reply.send(Ok(()));
                }
            }
            Work::Shutdown => break,
        }
    }
}

#[cfg(test)]
mod tests;
