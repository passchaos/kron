use std::fmt;
use std::fs;
use std::io::Write;
use std::sync::atomic::{AtomicU64, Ordering};

use tracing_subscriber::fmt::format::{DefaultFields, FormatFields};
use tracing_subscriber::fmt::MakeWriter;

use super::*;

static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(0);

fn emit_field_boundaries() {
    let span = tracing::info_span!("bounds", low = i64::MIN, high = u64::MAX, r#type = "plain");
    let _entered = span.enter();
    span.record("low", -7i64);
    for value in [
        "",
        "plain",
        "quote\"slash\\",
        "\n\t\r\0",
        "\x1b[31mred",
        "机器人🙂",
        "\u{7f}",
        "\u{202e}rtl",
    ] {
        tracing::info!(
            value,
            signed = i64::MIN,
            unsigned = u64::MAX,
            wide = u128::MAX,
            yes = true,
            no = false,
            float = 1.25f64,
            r#type = "raw",
            log.hidden = 3,
            "boundary"
        );
    }
    tracing::info!(message = "literal message", sequence = 0u64);
    let error = std::io::Error::other("error message");
    tracing::error!(
        error = &error as &(dyn std::error::Error + 'static),
        "error record"
    );
}

fn exercise_fields<N>(backend: Backend, formatter: N, ansi: bool)
where
    N: for<'writer> FormatFields<'writer> + Send + Sync + 'static,
{
    let subscriber = tracing_subscriber::registry().with(
        tracing_subscriber::fmt::layer()
            .fmt_fields(formatter)
            .with_writer(fmt_writer::FmtMakeWriter::new(backend))
            .with_ansi(ansi)
            .without_time()
            .with_target(false)
            .with_file(true)
            .with_line_number(true)
            .with_thread_ids(true)
            .compact(),
    );
    tracing::subscriber::with_default(subscriber, emit_field_boundaries);
}

#[test]
fn eager_fields_match_default_text_and_span_updates() {
    for mmap in [false, true] {
        for ansi in [false, true] {
            let directory = std::env::temp_dir().join(format!(
                "foundation-field-parity-{}-{}",
                std::process::id(),
                NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed)
            ));
            let mut settings = Settings::new(&directory, "default.log");
            if mmap {
                settings.mode = BackendMode::Mmap {
                    spool_path: directory.join("default.spool"),
                    capacity_bytes: 4096 + 16 * 4096,
                    slot_bytes: 4096,
                };
            }
            let default = Backend::open(settings.clone()).unwrap();
            exercise_fields(default.clone(), DefaultFields::new(), ansi);
            default.flush().unwrap();
            settings.log_file_name = "fast.log".to_owned();
            if let BackendMode::Mmap { spool_path, .. } = &mut settings.mode {
                *spool_path = directory.join("fast.spool");
            }
            let fast = Backend::open(settings).unwrap();
            exercise_fields(fast.clone(), fields::FileFields, ansi);
            fast.flush().unwrap();
            assert_eq!(
                fs::read(directory.join("fast.log")).unwrap(),
                fs::read(directory.join("default.log")).unwrap()
            );
            assert_eq!(
                fast.stats().written_records,
                default.stats().written_records
            );
            drop(fast);
            drop(default);
            fs::remove_dir_all(directory).unwrap();
        }
    }
}

struct RecursiveDisplay;

impl fmt::Display for RecursiveDisplay {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        tracing::info!(nested = true, "recursive event");
        formatter.write_str("outer display")
    }
}

fn emit_events() {
    let span = tracing::info_span!("planner", device = "机器人", revision = 42);
    let _entered = span.enter();
    tracing::info!(sequence = 7, ok = true, "planned {} points", 100);
    tracing::warn!(details = %RecursiveDisplay, "outer event");
    tracing::error!(payload = "x".repeat(2048), "long event");
}

fn exercise_writer<W>(writer: W)
where
    W: for<'writer> MakeWriter<'writer> + Send + Sync + 'static,
{
    let subscriber = tracing_subscriber::registry().with(
        tracing_subscriber::fmt::layer()
            .with_writer(writer)
            .with_ansi(false)
            .without_time()
            .with_target(false)
            .with_file(true)
            .with_line_number(true)
            .with_thread_ids(true)
            .compact(),
    );
    tracing::subscriber::with_default(subscriber, emit_events);
}

#[test]
fn direct_fmt_writer_matches_buffered_records_with_spans_and_recursion() {
    for mmap in [false, true] {
        let directory = std::env::temp_dir().join(format!(
            "foundation-fmt-parity-{}-{}",
            std::process::id(),
            NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&directory).unwrap();
        let mut settings = Settings::new(&directory, "buffered.log");
        if mmap {
            settings.mode = BackendMode::Mmap {
                spool_path: directory.join("buffered.spool"),
                capacity_bytes: 4096 + 16 * 4096,
                slot_bytes: 4096,
            };
        }
        let buffered = Backend::open(settings.clone()).unwrap();
        exercise_writer(TracingMakeWriter::new(buffered.clone()));
        buffered.flush().unwrap();

        settings.log_file_name = "direct.log".to_owned();
        if let BackendMode::Mmap { spool_path, .. } = &mut settings.mode {
            *spool_path = directory.join("direct.spool");
        }
        let direct = Backend::open(settings).unwrap();
        exercise_writer(fmt_writer::FmtMakeWriter::new(direct.clone()));
        direct.flush().unwrap();
        let expected = fs::read(directory.join("buffered.log")).unwrap();
        assert_eq!(fs::read(directory.join("direct.log")).unwrap(), expected);
        let records = buffered.stats().submitted_records;
        assert!(records >= 3);
        assert_eq!(direct.stats().submitted_records, records);
        assert_eq!(direct.stats().written_records, records);
        assert_eq!(direct.stats().written_bytes, expected.len() as u64);
        drop(buffered);
        drop(direct);
        fs::remove_dir_all(directory).unwrap();
    }
}

#[test]
fn public_writer_still_coalesces_fragments_and_empty_writes() {
    let directory = std::env::temp_dir().join(format!(
        "foundation-fmt-fragments-{}-{}",
        std::process::id(),
        NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed)
    ));
    let backend = Backend::open(Settings::new(&directory, "records.log")).unwrap();
    let maker = TracingMakeWriter::new(backend.clone());
    {
        let mut writer = maker.make_writer();
        writer.write_all(b"").unwrap();
        writer.write_all(b"first ").unwrap();
        writer.write_all(b"record\n").unwrap();
        writer.flush().unwrap();
        writer.write_all(b"second\n").unwrap();
    }
    backend.flush().unwrap();
    assert_eq!(backend.stats().written_records, 2);
    assert_eq!(
        fs::read(directory.join("records.log")).unwrap(),
        b"first record\nsecond\n"
    );
    drop(maker);
    drop(backend);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn direct_fmt_writer_marks_oversized_records() {
    let directory = std::env::temp_dir().join(format!(
        "foundation-fmt-errors-{}-{}",
        std::process::id(),
        NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed)
    ));
    let mut settings = Settings::new(&directory, "records.log");
    settings.queue_capacity_bytes = 4;
    let backend = Backend::open(settings).unwrap();
    let maker = fmt_writer::FmtMakeWriter::new(backend.clone());
    let mut writer = maker.make_writer();
    writer.write_all(b"12345").unwrap();
    writer.write_all(b"").unwrap();
    writer.write_all(b"123\n").unwrap();
    writer.flush().unwrap();
    backend.flush().unwrap();
    assert_eq!(backend.stats().written_records, 2);
    assert_eq!(
        fs::read(directory.join("records.log")).unwrap(),
        b"...\n123\n"
    );
    drop(maker);
    drop(backend);
    fs::remove_dir_all(directory).unwrap();
}
