//! Standard eager tracing comparison. Native and Foundation share versions,
//! filter, metadata, text formatter, payload, and file verification.
use std::fs;
use std::time::Instant;

use foundation_logging_core::{build_tracing, BackendMode, Settings, TracingOptions};
use tracing::Dispatch;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::{EnvFilter, Layer};

const WARMUP: usize = 10_000;
const LATENCY_SAMPLES: usize = 20_000;
const PAYLOAD: &str = concat!(
    "phase1 benchmark payload abcdefghijklmnopqrstuvwxyz 0123456789 ",
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789"
);

fn emit(sequence: usize) {
    tracing::info!(sequence, payload = PAYLOAD, "benchmark record");
}

fn emit_records<const TIMED: bool>(dispatch: &Dispatch, count: usize, threads: usize) -> Vec<u128> {
    let run = |count| {
        let mut samples = Vec::with_capacity(if TIMED { count } else { 0 });
        tracing::dispatcher::with_default(dispatch, || {
            for sequence in 0..count {
                if TIMED {
                    let started = Instant::now();
                    emit(sequence);
                    samples.push(started.elapsed().as_nanos());
                } else {
                    emit(sequence);
                }
            }
        });
        samples
    };
    if threads == 1 {
        return run(count);
    }
    std::thread::scope(|scope| {
        let workers = (0..threads)
            .map(|index| {
                let run = &run;
                scope.spawn(move || run(count / threads + usize::from(index < count % threads)))
            })
            .collect::<Vec<_>>();
        workers
            .into_iter()
            .flat_map(|worker| worker.join().unwrap())
            .collect()
    })
}

fn subscriber<W>(writer: W) -> Dispatch
where
    W: for<'writer> tracing_subscriber::fmt::MakeWriter<'writer> + Send + Sync + 'static,
{
    Dispatch::new(
        tracing_subscriber::registry().with(
            tracing_subscriber::fmt::layer()
                .with_writer(writer)
                .with_ansi(false)
                .with_target(false)
                .with_file(true)
                .with_line_number(true)
                .with_thread_ids(true)
                .with_thread_names(true)
                .compact()
                .with_filter(EnvFilter::new("info")),
        ),
    )
}

fn main() {
    let mode = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "memory".to_owned());
    let iterations = std::env::args()
        .nth(2)
        .map(|value| value.parse::<usize>().unwrap())
        .unwrap_or(200_000);
    assert!(iterations > 0);
    let threads = std::env::args()
        .nth(3)
        .map(|value| value.parse::<usize>().unwrap())
        .unwrap_or(1);
    assert!(threads > 0 && threads <= LATENCY_SAMPLES);
    let root = std::env::temp_dir().join(format!(
        "foundation-standard-rust-{}-{mode}",
        std::process::id()
    ));
    fs::create_dir_all(&root).unwrap();
    let output = root.join("records.log");
    let mut counter = None;
    let (dispatch, drain): (Dispatch, Box<dyn FnOnce()>) = match mode.as_str() {
        "memory" | "mmap" => {
            let mut settings = Settings::new(&root, "records.log");
            settings.max_file_bytes = 1024 * 1024 * 1024;
            if mode == "mmap" {
                settings.mode = BackendMode::Mmap {
                    spool_path: root.join("records.spool"),
                    capacity_bytes: 64 * 1024 * 1024,
                    slot_bytes: 1024,
                };
            }
            let (dispatch, guard) = build_tracing(
                settings,
                TracingOptions {
                    console: false,
                    ..TracingOptions::default()
                },
            )
            .unwrap();
            (
                dispatch,
                Box::new(move || {
                    guard.flush().unwrap();
                    let stats = guard.backend().stats();
                    assert_eq!(
                        stats.submitted_records,
                        (WARMUP + LATENCY_SAMPLES + iterations) as u64
                    );
                    assert_eq!(stats.written_records, stats.submitted_records);
                }),
            )
        }
        "nonblocking" | "nonblocking-buffered" => {
            let file = fs::File::create(&output).unwrap();
            let (writer, guard) = if mode == "nonblocking-buffered" {
                tracing_appender::non_blocking(std::io::BufWriter::with_capacity(256 * 1024, file))
            } else {
                tracing_appender::non_blocking(file)
            };
            counter = Some(writer.error_counter());
            (subscriber(writer), Box::new(move || drop(guard)))
        }
        "frontend" => (subscriber(std::io::sink), Box::new(|| {})),
        _ => panic!("expected memory, mmap, nonblocking or frontend"),
    };
    emit_records::<false>(&dispatch, WARMUP, threads);
    let mut latency = emit_records::<true>(&dispatch, LATENCY_SAMPLES, threads);
    latency.sort_unstable();
    let started = Instant::now();
    emit_records::<false>(&dispatch, iterations, threads);
    let producer = started.elapsed();
    drain();
    let total = started.elapsed();
    drop(dispatch);
    let dropped = counter.map(|counter| counter.dropped_lines()).unwrap_or(0);
    assert_eq!(
        dropped, 0,
        "native nonblocking dropped records; performance comparison rejected"
    );
    let mut output_bytes = 0;
    if mode != "frontend" {
        let contents = fs::read(&output).unwrap();
        output_bytes = contents.len();
        assert_eq!(
            contents.iter().filter(|&&byte| byte == b'\n').count(),
            WARMUP + LATENCY_SAMPLES + iterations
        );
    }
    let percentile = |fraction: f64| latency[((latency.len() - 1) as f64 * fraction) as usize];
    println!(
        "{{\"name\":\"tracing-{mode}\",\"iterations\":{iterations},\"threads\":{threads},\"record_bytes\":{},\"output_bytes\":{output_bytes},\"dropped\":{dropped},\"producer_ns_per_record\":{},\"end_to_end_ns_per_record\":{},\"drain_ms\":{},\"p50_ns\":{},\"p95_ns\":{},\"p99_ns\":{}}}",
        PAYLOAD.len(), producer.as_nanos() as f64 / iterations as f64,
        total.as_nanos() as f64 / iterations as f64, (total - producer).as_secs_f64() * 1000.0,
        percentile(0.50), percentile(0.95), percentile(0.99)
    );
    fs::remove_dir_all(root).unwrap();
}
