//! Real tracing Subscriber/fmt + Foundation public writer, or native build_tracing.
//! Compiled as an extra benchmark bin in a frozen copy of the owning Rust crate.
use foundation_logging_core::{
    build_tracing, Backend, BackendMode, Settings, TracingMakeWriter, TracingOptions,
};
use std::fmt;
use std::fmt::Write as _;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};
use tracing::{
    field::{Field, Visit},
    Dispatch, Event, Subscriber,
};
use tracing_subscriber::{
    fmt::{format::Writer, FmtContext, FormatEvent, FormatFields},
    layer::SubscriberExt,
    registry::LookupSpan,
    EnvFilter, Layer,
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

struct Options {
    output: String,
    storage: String,
    metadata: String,
    phase: String,
    events: usize,
    warmup: usize,
    producers: usize,
    queue_slots: usize,
}
impl Options {
    fn parse() -> Result<Self> {
        let mut result = Self {
            output: String::new(),
            storage: "memory".into(),
            metadata: "full".into(),
            phase: "batch".into(),
            events: 10000,
            warmup: 1000,
            producers: 1,
            queue_slots: 256,
        };
        for argument in std::env::args().skip(1) {
            let (key, value) = argument.split_once('=').ok_or("expected key=value")?;
            match key {
                "--output" => result.output = value.into(),
                "--storage" => result.storage = value.into(),
                "--metadata" => result.metadata = value.into(),
                "--phase" => result.phase = value.into(),
                "--events" => result.events = value.parse()?,
                "--warmup" => result.warmup = value.parse()?,
                "--producers" => result.producers = value.parse()?,
                "--queue-slots" => result.queue_slots = value.parse()?,
                "--strategy" if value == "producer_format" => {}
                _ => return Err("unknown or unsupported option".into()),
            }
        }
        if result.output.is_empty()
            || !(1..=1000000).contains(&result.events)
            || result.warmup > 1000000
            || ![1, 4].contains(&result.producers)
            || result.queue_slots == 0
            || result.queue_slots > 65536
            || !["memory", "mmap"].contains(&result.storage.as_str())
            || !["full", "native_tracing"].contains(&result.metadata.as_str())
            || !["sampled", "batch"].contains(&result.phase.as_str())
        {
            return Err("invalid bounded options".into());
        }
        Ok(result)
    }
}

#[derive(Default)]
struct NumericFields {
    values: [u64; 5],
    mask: u8,
    invalid: bool,
}
impl Visit for NumericFields {
    fn record_u64(&mut self, field: &Field, value: u64) {
        let index = match field.name() {
            "field0" => 0,
            "field1" => 1,
            "field2" => 2,
            "field3" => 3,
            "field4" => 4,
            _ => {
                self.invalid = true;
                return;
            }
        };
        if self.mask & (1 << index) != 0 {
            self.invalid = true;
        }
        self.mask |= 1 << index;
        self.values[index] = value;
    }
    fn record_debug(&mut self, field: &Field, _: &dyn fmt::Debug) {
        if field.name() != "message" {
            self.invalid = true;
        }
    }
}
struct JsonEvent;
impl<S, N> FormatEvent<S, N> for JsonEvent
where
    S: Subscriber + for<'lookup> LookupSpan<'lookup>,
    N: for<'writer> FormatFields<'writer> + 'static,
{
    fn format_event(
        &self,
        _: &FmtContext<'_, S, N>,
        mut writer: Writer<'_>,
        event: &Event<'_>,
    ) -> fmt::Result {
        let mut fields = NumericFields::default();
        event.record(&mut fields);
        if fields.invalid || fields.mask != 31 {
            return Err(fmt::Error);
        }
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| fmt::Error)?
            .as_nanos();
        write!(writer, "{{\"timestamp_ns\":\"{timestamp}\",\"severity\":\"info\",\"scope\":\"reference\",\"message\":\"event\",\"session\":\"18446744073709551615\",\"channel\":0,\"sequence\":{},\"route_mask\":1,\"config_generation\":1,\"trace_flags\":0,\"attributes\":{{\"field0\":{},\"field1\":{},\"field2\":{},\"field3\":{},\"field4\":{}}}}}\n",
            fields.values[0]+1, fields.values[0], fields.values[1], fields.values[2], fields.values[3], fields.values[4])
    }
}

fn awake() -> u64 {
    let mut now = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    if unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut now) } != 0 {
        panic!("clock_gettime failed");
    }
    now.tv_sec as u64 * 1000000000 + now.tv_nsec as u64
}
fn emit(value: usize) {
    let n = value as u64;
    tracing::info!(target: "reference", field0 = n, field1 = n + 1, field2 = n + 2, field3 = n + 3, field4 = n + 4, "event");
}
fn share(total: usize, producers: usize, id: usize) -> usize {
    total / producers + usize::from(id < total % producers)
}
fn quantile(samples: &[u64], thousandths: usize) -> String {
    if samples.is_empty() {
        "null".into()
    } else {
        samples[(samples.len() * thousandths).div_ceil(1000) - 1].to_string()
    }
}

fn run(options: Options) -> Result<()> {
    let lifecycle = awake();
    let output = std::path::Path::new(&options.output);
    let mut settings = Settings::new(
        output.parent().ok_or("output parent")?,
        output
            .file_name()
            .ok_or("output filename")?
            .to_string_lossy(),
    );
    settings.queue_capacity = options.queue_slots;
    settings.queue_capacity_bytes = options.queue_slots * 512;
    settings.critical_reserve_records = 0;
    settings.critical_reserve_bytes = 0;
    settings.write_buffer_bytes = 65536;
    settings.max_file_bytes = 1 << 30;
    settings.max_files = 2;
    settings.block_when_full = true;
    if options.storage == "mmap" {
        settings.mode = BackendMode::Mmap {
            spool_path: format!("{}.spool", options.output).into(),
            capacity_bytes: 4096 + options.queue_slots * 576,
            slot_bytes: 576,
        };
    }
    let (dispatch, backend, guard) = if options.metadata == "native_tracing" {
        let (dispatch, guard) = build_tracing(
            settings,
            TracingOptions {
                default_filter: "info",
                primary_filter_env: None,
                console: false,
            },
        )?;
        let backend = guard.backend().clone();
        (dispatch, backend, Some(guard))
    } else {
        let backend = Backend::open(settings)?;
        let layer = tracing_subscriber::fmt::layer()
            .with_ansi(false)
            .event_format(JsonEvent)
            .with_writer(TracingMakeWriter::new(backend.clone()))
            .with_filter(EnvFilter::new("info"));
        (
            Dispatch::new(tracing_subscriber::registry().with(layer)),
            backend,
            None,
        )
    };
    let initialized = awake();
    let gate = Arc::new((Mutex::new((0usize, false)), Condvar::new()));
    let mut threads = Vec::with_capacity(options.producers);
    for id in 0..options.producers {
        let dispatch = dispatch.clone();
        let gate = gate.clone();
        let (events, warmup, producers, sampled) = (
            options.events,
            options.warmup,
            options.producers,
            options.phase == "sampled",
        );
        threads.push(std::thread::spawn(move || {
            tracing::dispatcher::with_default(&dispatch, || {
                let mut samples = Vec::with_capacity(if sampled {
                    share(events, producers, id)
                } else {
                    0
                });
                for index in 0..share(warmup, producers, id) {
                    emit(events + index * producers + id);
                }
                let (mutex, condition) = &*gate;
                let mut state = mutex.lock().unwrap();
                state.0 += 1;
                condition.notify_all();
                while !state.1 {
                    state = condition.wait(state).unwrap();
                }
                drop(state);
                for index in 0..share(events, producers, id) {
                    let before = if sampled { awake() } else { 0 };
                    emit(index * producers + id);
                    if sampled {
                        samples.push(awake() - before);
                    }
                }
                samples
            })
        }));
    }
    let (mutex, condition) = &*gate;
    let mut state = mutex.lock().unwrap();
    while state.0 != options.producers {
        state = condition.wait(state).unwrap();
    }
    backend.flush()?;
    let before_stats = backend.stats();
    let start = awake();
    state.1 = true;
    condition.notify_all();
    drop(state);
    let mut samples = Vec::new();
    for thread in threads {
        samples.extend(thread.join().map_err(|_| "producer panicked")?);
    }
    let produced = awake();
    backend.flush()?;
    let flushed = awake();
    let stats = backend.stats();
    if before_stats.submitted_records != options.warmup as u64
        || stats.submitted_records != (options.events + options.warmup) as u64
        || stats.written_records != stats.submitted_records
        || stats.write_error_count != 0
        || stats.recovered_records != 0
    {
        return Err("incomplete Foundation tracing workflow".into());
    }
    drop(dispatch);
    drop(guard);
    let stopped = awake();
    drop(backend);
    let cleaned = awake();
    let bytes = std::fs::metadata(&options.output)?.len();
    if bytes != stats.written_bytes {
        return Err("physical bytes differ from Foundation written counter".into());
    }
    samples.sort_unstable();
    let mut noop = Vec::with_capacity(10000);
    for index in 0..10000 {
        let before = awake();
        std::hint::black_box(index);
        noop.push(awake() - before);
    }
    noop.sort_unstable();
    let total = cleaned - start;
    println!("{{\"schema_version\":2,\"status\":\"ok\",\"library\":\"foundation_tracing\",\"version\":\"workspace-0.1.0\",\"strategy\":\"producer_format\",\"phase\":\"{}\",\"events\":{},\"producers\":{},\"warmup_events\":{},\"accepted\":{},\"written\":{},\"drop\":0,\"final_pending\":0,\"producer_wall_ns\":{},\"flush_ns\":{},\"shutdown_ns\":{},\"cleanup_ns\":{},\"total_ns\":{},\"init_ns\":{},\"preparation_ns\":{},\"lifecycle_ns\":{},\"lifecycle_records_per_sec\":{},\"metadata\":\"{}\",\"written_bytes\":{},\"artifact_bytes\":{},\"written_records_per_sec\":{},\"sample_count\":{},\"p50_ns\":{},\"p99_ns\":{},\"p999_ns\":{},\"noop_clock_pair_p50_ns\":{},\"noop_clock_pair_p99_ns\":{},\"queue_policy\":\"block\",\"queue_slots\":{},\"blocking_notifications\":{},\"file_buffer_bytes\":65536,\"storage\":\"{}\",\"has_process_crash_recovery\":{},\"foundation_queue_capacity_bytes\":{},\"foundation_mmap_slot_bytes\":576,\"foundation_mmap_capacity_bytes\":{},\"foundation_submitted_records\":{},\"foundation_written_records\":{},\"foundation_written_bytes\":{},\"event_clock\":\"system\"}}",
        options.phase, options.events, options.producers, options.warmup, options.events, options.events, produced-start, flushed-produced, stopped-flushed, cleaned-stopped, total, initialized-lifecycle, start-initialized, cleaned-lifecycle, (options.events+options.warmup) as f64*1e9/(cleaned-lifecycle) as f64, options.metadata, stats.written_bytes-before_stats.written_bytes, bytes, options.events as f64*1e9/total as f64, samples.len(), quantile(&samples,500), quantile(&samples,990), quantile(&samples,999), quantile(&noop,500), quantile(&noop,990), options.queue_slots, stats.queue_full_count, options.storage, options.storage=="mmap", options.queue_slots*512, 4096+options.queue_slots*576, stats.submitted_records, stats.written_records, stats.written_bytes);
    Ok(())
}
fn main() {
    // Isolated benchmark processes must not inherit an application's filter.
    std::env::remove_var("RUST_LOG");
    if let Err(error) = Options::parse().and_then(run) {
        eprintln!("foundation-tracing-reference: {error}");
        std::process::exit(2);
    }
}
