//! Child process for crash-loss tests. READY means every submit returned and
//! submitted_records was checked; no log flush happens in the kill scenario.
use std::io::{Read, Write};
use std::path::PathBuf;

use foundation_logging_core::{build_tracing, Backend, Settings, TracingOptions};

fn record(sequence: usize) -> String {
    format!(
        "BEGIN id={sequence:08} {} END id={sequence:08}",
        "x".repeat(93)
    )
}

fn main() {
    let arguments = std::env::args().collect::<Vec<_>>();
    let frontend = &arguments[1];
    let directory = PathBuf::from(&arguments[2]);
    let mmap = arguments[3] == "mmap";
    let count: usize = arguments[4].parse().unwrap();
    let normal = arguments[5] == "normal";
    let mut settings = Settings::new(&directory, "app.log").with_mmap_enabled(mmap);
    settings.max_file_bytes = 1024 * 1024 * 1024;
    if frontend == "recover" {
        let backend = Backend::open(settings).unwrap();
        backend.flush().unwrap();
        let stats = backend.stats();
        println!(
            "RECOVERED {} {}",
            stats.recovered_records, stats.written_records
        );
        return;
    }
    let (backend, dispatch, guard) = if frontend == "tracing" {
        let (dispatch, guard) = build_tracing(
            settings,
            TracingOptions {
                console: false,
                ..TracingOptions::default()
            },
        )
        .unwrap();
        (guard.backend().clone(), Some(dispatch), Some(guard))
    } else {
        (Backend::open(settings).unwrap(), None, None)
    };
    for sequence in 0..count {
        if let Some(dispatch) = &dispatch {
            tracing::dispatcher::with_default(dispatch, || {
                tracing::info!(record = record(sequence), "crash_probe");
            });
        } else {
            let mut bytes = record(sequence).into_bytes();
            bytes.push(b'\n');
            assert_eq!(bytes.len(), 128);
            backend.submit(&bytes).unwrap();
        }
    }
    assert_eq!(backend.stats().submitted_records, count as u64);
    if normal {
        backend.flush().unwrap();
    }
    let stats = backend.stats();
    println!(
        "READY {} {}",
        stats.submitted_records, stats.written_records
    );
    std::io::stdout().flush().unwrap();
    if !normal {
        let mut command = [0];
        std::io::stdin().read_exact(&mut command).unwrap();
        panic!("kill scenario must terminate with SIGKILL");
    }
    drop(dispatch);
    drop(guard);
    drop(backend);
}
