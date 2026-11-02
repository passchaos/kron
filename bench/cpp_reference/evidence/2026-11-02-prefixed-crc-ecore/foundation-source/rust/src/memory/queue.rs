use std::collections::VecDeque;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use parking_lot::{Condvar, Mutex, MutexGuard};

use crate::{Error, Priority, Result};

const MAX_BATCH_DELAY: Duration = Duration::from_millis(10);
pub(super) struct RecordBatch {
    bytes: Vec<u8>,
    ends: Vec<usize>,
}

impl RecordBatch {
    pub(super) fn with_capacity(records: usize, bytes: usize) -> Self {
        Self {
            bytes: Vec::with_capacity(bytes),
            ends: Vec::with_capacity(records),
        }
    }

    pub(super) fn push(&mut self, record: &[u8]) {
        self.bytes.extend_from_slice(record);
        self.ends.push(self.bytes.len());
    }

    pub(super) fn len(&self) -> usize {
        self.ends.len()
    }

    pub(super) fn is_empty(&self) -> bool {
        self.ends.is_empty()
    }

    pub(super) fn byte_len(&self) -> usize {
        self.bytes.len()
    }

    pub(super) fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub(super) fn ends(&self) -> &[usize] {
        &self.ends
    }

    pub(super) fn clear(&mut self) {
        self.bytes.clear();
        self.ends.clear();
    }
}

pub(super) struct FlushRequest {
    pub(super) durable: bool,
    pub(super) reply: mpsc::Sender<Result<()>>,
    target: u64,
}

pub(super) enum Work {
    Records,
    PeriodicFlush,
    Flush(FlushRequest),
    Shutdown,
}

struct QueueState {
    pending: RecordBatch,
    in_flight_records: usize,
    in_flight_bytes: usize,
    // These counters share the queue critical section so submit does not pay
    // for two additional atomic read-modify-write operations per record.
    accepted_records: u64,
    accepted_bytes: u64,
    completed_records: u64,
    completed_bytes: u64,
    flush_requests: VecDeque<FlushRequest>,
    open: bool,
    error: Option<String>,
}

pub(super) struct QueueStats {
    pub(super) submitted_records: u64,
    pub(super) submitted_bytes: u64,
    pub(super) written_records: u64,
    pub(super) written_bytes: u64,
}

pub(super) struct BoundedQueue {
    capacity_records: usize,
    capacity_bytes: usize,
    critical_reserve_records: usize,
    critical_reserve_bytes: usize,
    batch_records: usize,
    batch_bytes: usize,
    state: Mutex<QueueState>,
    ready: Condvar,
    space: Condvar,
}

impl BoundedQueue {
    pub(super) fn new(
        capacity_records: usize,
        capacity_bytes: usize,
        critical_reserve_records: usize,
        critical_reserve_bytes: usize,
        batch_records: usize,
        batch_bytes: usize,
    ) -> Self {
        Self {
            capacity_records,
            capacity_bytes,
            critical_reserve_records,
            critical_reserve_bytes,
            batch_records,
            batch_bytes,
            state: Mutex::new(QueueState {
                pending: RecordBatch::with_capacity(batch_records, batch_bytes),
                in_flight_records: 0,
                in_flight_bytes: 0,
                accepted_records: 0,
                accepted_bytes: 0,
                completed_records: 0,
                completed_bytes: 0,
                flush_requests: VecDeque::new(),
                open: true,
                error: None,
            }),
            ready: Condvar::new(),
            space: Condvar::new(),
        }
    }

    pub(super) fn submit(
        &self,
        record: &[u8],
        block_when_full: bool,
        priority: Priority,
    ) -> Result<()> {
        if record.len() > self.capacity_bytes {
            return Err(Error::RecordTooLarge {
                size: record.len(),
                maximum: self.capacity_bytes,
            });
        }
        let mut state = self.lock_state();
        loop {
            if !state.open {
                return Err(state_error(&state));
            }
            let record_capacity = match priority {
                Priority::Normal => self.capacity_records - self.critical_reserve_records,
                Priority::Critical => self.capacity_records,
            };
            let byte_capacity = match priority {
                Priority::Normal => self.capacity_bytes - self.critical_reserve_bytes,
                Priority::Critical => self.capacity_bytes,
            };
            let records_fit =
                state.pending.len().saturating_add(state.in_flight_records) < record_capacity;
            let bytes_fit = record.len() <= byte_capacity
                && state
                    .pending
                    .byte_len()
                    .saturating_add(state.in_flight_bytes)
                    <= byte_capacity - record.len();
            if records_fit && bytes_fit {
                let wake_writer = state.pending.is_empty()
                    || state.pending.len() + 1 >= self.batch_records
                    || state.pending.byte_len().saturating_add(record.len()) >= self.batch_bytes;
                state.pending.push(record);
                state.accepted_records = state.accepted_records.saturating_add(1);
                state.accepted_bytes = state.accepted_bytes.saturating_add(record.len() as u64);
                drop(state);
                if wake_writer {
                    self.ready.notify_one();
                }
                return Ok(());
            }
            if !block_when_full {
                return Err(Error::QueueFull);
            }
            self.space.wait(&mut state);
        }
    }

    pub(super) fn request_flush(&self, durable: bool) -> Result<mpsc::Receiver<Result<()>>> {
        let (reply, result) = mpsc::channel();
        let mut state = self.lock_state();
        if !state.open {
            return Err(state_error(&state));
        }
        let target = state.accepted_records;
        state.flush_requests.push_back(FlushRequest {
            durable,
            reply,
            target,
        });
        drop(state);
        self.ready.notify_one();
        Ok(result)
    }

    pub(super) fn maximum_record_bytes(&self) -> usize {
        self.capacity_bytes
    }

    pub(super) fn take_work(
        &self,
        batch: &mut RecordBatch,
        flush_deadline: Option<Instant>,
    ) -> Work {
        debug_assert!(batch.is_empty());
        let mut state = self.lock_state();
        loop {
            let completed_records = state.completed_records;
            if let Some(request) = state
                .flush_requests
                .pop_front_if(|request| request.target <= completed_records)
            {
                return Work::Flush(request);
            }
            let flush_delay =
                flush_deadline.map(|deadline| deadline.saturating_duration_since(Instant::now()));
            if flush_delay.is_some_and(|delay| delay.is_zero()) {
                return Work::PeriodicFlush;
            }
            if !state.pending.is_empty() {
                if !state.open
                    || state.pending.len() >= self.batch_records
                    || state.pending.byte_len() >= self.batch_bytes
                    || !state.flush_requests.is_empty()
                {
                    break;
                }
                let timeout = self.ready.wait_for(
                    &mut state,
                    flush_delay.map_or(MAX_BATCH_DELAY, |delay| delay.min(MAX_BATCH_DELAY)),
                );
                if timeout.timed_out() {
                    break;
                }
                continue;
            }
            if !state.open {
                return Work::Shutdown;
            }
            state = if let Some(delay) = flush_delay {
                self.ready.wait_for(&mut state, delay);
                state
            } else {
                self.ready.wait(&mut state);
                state
            };
        }

        debug_assert_eq!(state.in_flight_records, 0);
        debug_assert_eq!(state.in_flight_bytes, 0);
        std::mem::swap(batch, &mut state.pending);
        state.in_flight_records = batch.len();
        state.in_flight_bytes = batch.byte_len();
        Work::Records
    }

    pub(super) fn finish_batch(&self, completed_records: usize, completed_bytes: usize) {
        let mut state = self.lock_state();
        state.in_flight_records = 0;
        state.in_flight_bytes = 0;
        state.completed_records = state
            .completed_records
            .saturating_add(completed_records as u64);
        state.completed_bytes = state.completed_bytes.saturating_add(completed_bytes as u64);
        drop(state);
        self.ready.notify_one();
        self.space.notify_all();
    }

    pub(super) fn close(&self) {
        let mut state = self.lock_state();
        state.open = false;
        drop(state);
        self.ready.notify_all();
        self.space.notify_all();
    }

    pub(super) fn fail(&self, message: String) {
        let mut state = self.lock_state();
        state.open = false;
        state.error = Some(message);
        state.pending.clear();
        state.flush_requests.clear();
        drop(state);
        self.ready.notify_all();
        self.space.notify_all();
    }

    pub(super) fn closed_error(&self) -> Error {
        state_error(&self.lock_state())
    }

    pub(super) fn stats(&self) -> QueueStats {
        let state = self.lock_state();
        QueueStats {
            submitted_records: state.accepted_records,
            submitted_bytes: state.accepted_bytes,
            written_records: state.completed_records,
            written_bytes: state.completed_bytes,
        }
    }

    fn lock_state(&self) -> MutexGuard<'_, QueueState> {
        self.state.lock()
    }
}

fn state_error(state: &QueueState) -> Error {
    state
        .error
        .clone()
        .map(Error::Background)
        .unwrap_or(Error::Closed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn capacity_counts_the_batch_owned_by_the_writer() {
        let queue = BoundedQueue::new(1, 16, 0, 0, 1, 16);
        queue.submit(b"one", false, Priority::Normal).unwrap();
        let stats = queue.stats();
        assert_eq!(stats.submitted_records, 1);
        assert_eq!(stats.submitted_bytes, 3);
        assert_eq!(stats.written_records, 0);
        let mut batch = RecordBatch::with_capacity(1, 16);
        assert!(matches!(queue.take_work(&mut batch, None), Work::Records));
        assert!(matches!(
            queue.submit(b"two", false, Priority::Normal),
            Err(Error::QueueFull)
        ));
        batch.clear();
        queue.finish_batch(1, 3);
        queue.submit(b"three", false, Priority::Normal).unwrap();
        let stats = queue.stats();
        assert_eq!(stats.submitted_records, 2);
        assert_eq!(stats.submitted_bytes, 8);
        assert_eq!(stats.written_records, 1);
        assert_eq!(stats.written_bytes, 3);
    }

    #[test]
    fn critical_records_can_use_reserved_capacity() {
        let queue = BoundedQueue::new(2, 16, 1, 8, 2, 16);
        queue.submit(b"normal", false, Priority::Normal).unwrap();
        assert!(matches!(
            queue.submit(b"blocked", false, Priority::Normal),
            Err(Error::QueueFull)
        ));
        queue
            .submit(b"critical", false, Priority::Critical)
            .unwrap();
        assert!(matches!(
            queue.submit(b"full", false, Priority::Critical),
            Err(Error::QueueFull)
        ));
    }

    #[test]
    fn one_normal_record_cannot_consume_reserved_bytes() {
        let queue = BoundedQueue::new(8, 16, 0, 4, 8, 16);
        assert!(matches!(
            queue.submit(b"thirteen-byte", false, Priority::Normal),
            Err(Error::QueueFull)
        ));
        queue
            .submit(b"thirteen-byte", false, Priority::Critical)
            .unwrap();
    }

    #[test]
    fn flush_waits_for_accepted_records() {
        let queue = BoundedQueue::new(4, 64, 0, 0, 4, 64);
        queue.submit(b"one", false, Priority::Normal).unwrap();
        let result = queue.request_flush(true).unwrap();
        let mut batch = RecordBatch::with_capacity(4, 64);
        assert!(matches!(queue.take_work(&mut batch, None), Work::Records));
        batch.clear();
        queue.finish_batch(1, 3);
        let Work::Flush(request) = queue.take_work(&mut batch, None) else {
            panic!("flush became ready before its records");
        };
        assert!(request.durable);
        request.reply.send(Ok(())).unwrap();
        assert!(result.recv().unwrap().is_ok());
    }

    #[test]
    fn failure_is_reported_to_later_producers() {
        let queue = BoundedQueue::new(1, 16, 0, 0, 1, 16);
        queue.fail("writer failed".to_owned());
        assert!(matches!(
            queue.submit(b"record", false, Priority::Normal),
            Err(Error::Background(message)) if message == "writer failed"
        ));
    }

    #[test]
    fn byte_capacity_counts_pending_and_writer_owned_payloads() {
        let queue = BoundedQueue::new(8, 6, 0, 0, 8, 6);
        queue.submit(b"one", false, Priority::Normal).unwrap();
        queue.submit(b"two", false, Priority::Normal).unwrap();
        assert!(matches!(
            queue.submit(b"x", false, Priority::Normal),
            Err(Error::QueueFull)
        ));

        let mut batch = RecordBatch::with_capacity(8, 6);
        assert!(matches!(queue.take_work(&mut batch, None), Work::Records));
        assert!(matches!(
            queue.submit(b"x", false, Priority::Normal),
            Err(Error::QueueFull)
        ));
        batch.clear();
        queue.finish_batch(2, 6);
        queue.submit(b"three", false, Priority::Normal).unwrap();
    }

    #[test]
    fn record_larger_than_byte_capacity_is_rejected_without_waiting() {
        let queue = BoundedQueue::new(8, 4, 0, 0, 8, 4);
        assert!(matches!(
            queue.submit(b"oversized", true, Priority::Normal),
            Err(Error::RecordTooLarge {
                size: 9,
                maximum: 4
            })
        ));
    }

    #[test]
    fn blocking_submit_resumes_after_in_flight_bytes_are_released() {
        let queue = Arc::new(BoundedQueue::new(8, 6, 0, 0, 8, 6));
        queue.submit(b"onetwo", true, Priority::Normal).unwrap();
        let mut batch = RecordBatch::with_capacity(8, 6);
        assert!(matches!(queue.take_work(&mut batch, None), Work::Records));

        let (started_tx, started_rx) = mpsc::channel();
        let (done_tx, done_rx) = mpsc::channel();
        let producer_queue = Arc::clone(&queue);
        let producer = std::thread::spawn(move || {
            started_tx.send(()).unwrap();
            producer_queue.submit(b"x", true, Priority::Normal).unwrap();
            done_tx.send(()).unwrap();
        });
        started_rx.recv().unwrap();
        assert!(matches!(done_rx.try_recv(), Err(mpsc::TryRecvError::Empty)));

        batch.clear();
        queue.finish_batch(1, 6);
        done_rx.recv().unwrap();
        producer.join().unwrap();
    }
}
