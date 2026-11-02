use std::fs;
use std::time::Instant;

use foundation_logging_core::{build_tracing, BackendMode, Settings, TracingOptions};

const WARMUP: usize = 10_000;
const LATENCY_SAMPLES: usize = 20_000;
const ITERATIONS: usize = 200_000;
const PAYLOAD: &str = concat!(
    "phase1 benchmark payload abcdefghijklmnopqrstuvwxyz 0123456789 ",
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789"
);

fn percentile(sorted: &[f64], fraction: f64) -> f64 {
    sorted[(fraction * (sorted.len() - 1) as f64) as usize]
}

fn emit(sequence: usize) {
    tracing::info!(sequence, payload = PAYLOAD, "benchmark record");
}

fn main() {
    let mode = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "memory".to_owned());
    let repetitions = std::env::args()
        .nth(2)
        .map(|value| value.parse::<usize>().unwrap())
        .unwrap_or(7)
        .max(1);
    assert!(matches!(mode.as_str(), "memory" | "mmap"));

    let root = std::env::temp_dir().join(format!(
        "foundation-standard-tracing-phase29-{}-{mode}",
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&root);
    fs::create_dir_all(&root).unwrap();
    let mut producer_samples = Vec::with_capacity(repetitions);
    let mut end_to_end_samples = Vec::with_capacity(repetitions);
    let mut p50_samples = Vec::with_capacity(repetitions);
    let mut p95_samples = Vec::with_capacity(repetitions);
    let mut p99_samples = Vec::with_capacity(repetitions);

    for repetition in 0..repetitions {
        let directory = root.join(repetition.to_string());
        fs::create_dir_all(&directory).unwrap();
        let mut settings = Settings::new(&directory, "tracing.log");
        settings.max_file_bytes = 1024 * 1024 * 1024;
        if mode == "mmap" {
            settings.mode = BackendMode::Mmap {
                spool_path: directory.join("tracing.spool"),
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

        tracing::dispatcher::with_default(&dispatch, || {
            for sequence in 0..WARMUP {
                emit(sequence);
            }
        });
        let mut latency = Vec::with_capacity(LATENCY_SAMPLES);
        tracing::dispatcher::with_default(&dispatch, || {
            for sequence in 0..LATENCY_SAMPLES {
                let started = Instant::now();
                emit(sequence);
                latency.push(started.elapsed().as_nanos() as f64);
            }
        });
        latency.sort_unstable_by(f64::total_cmp);

        let producer_started = Instant::now();
        tracing::dispatcher::with_default(&dispatch, || {
            for sequence in 0..ITERATIONS {
                emit(sequence);
            }
        });
        let producer_elapsed = producer_started.elapsed();
        let drain_started = Instant::now();
        guard.flush().unwrap();
        let total_elapsed = producer_elapsed + drain_started.elapsed();
        producer_samples.push(producer_elapsed.as_nanos() as f64 / ITERATIONS as f64);
        end_to_end_samples.push(total_elapsed.as_nanos() as f64 / ITERATIONS as f64);
        p50_samples.push(percentile(&latency, 0.50));
        p95_samples.push(percentile(&latency, 0.95));
        p99_samples.push(percentile(&latency, 0.99));

        drop(guard);
        drop(dispatch);
        fs::remove_dir_all(directory).unwrap();
    }

    producer_samples.sort_unstable_by(f64::total_cmp);
    end_to_end_samples.sort_unstable_by(f64::total_cmp);
    p50_samples.sort_unstable_by(f64::total_cmp);
    p95_samples.sort_unstable_by(f64::total_cmp);
    p99_samples.sort_unstable_by(f64::total_cmp);
    println!(
        "{{\"mode\":\"{mode}\",\"producer_ns\":{},\"end_to_end_ns\":{},\"p50_ns\":{},\"p95_ns\":{},\"p99_ns\":{}}}",
        producer_samples[repetitions / 2],
        end_to_end_samples[repetitions / 2],
        p50_samples[repetitions / 2],
        p95_samples[repetitions / 2],
        p99_samples[repetitions / 2]
    );
    fs::remove_dir_all(root).unwrap();
}
