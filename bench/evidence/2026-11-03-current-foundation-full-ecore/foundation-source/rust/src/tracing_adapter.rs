mod fields;
mod fmt_writer;
#[cfg(test)]
mod tests;
mod timestamp;

use std::io::{self, IsTerminal, Write};

use tracing::Dispatch;
use tracing_subscriber::fmt::format::{DefaultFields, FormatFields};
use tracing_subscriber::fmt::time::{FormatTime, SystemTime};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::{EnvFilter, Layer};

use crate::{Backend, BackendMode, BoxError, Priority, Settings};

fn priority(metadata: &tracing::Metadata<'_>) -> Priority {
    if *metadata.level() == tracing::Level::ERROR {
        Priority::Critical
    } else {
        Priority::Normal
    }
}

#[derive(Debug, Clone, Copy)]
pub struct TracingOptions<'a> {
    pub default_filter: &'a str,
    pub primary_filter_env: Option<&'a str>,
    pub console: bool,
}

impl Default for TracingOptions<'static> {
    fn default() -> Self {
        Self {
            default_filter: "info",
            primary_filter_env: None,
            console: true,
        }
    }
}

#[derive(Clone)]
pub struct TracingMakeWriter {
    backend: Backend,
}

impl TracingMakeWriter {
    pub fn new(backend: Backend) -> Self {
        Self { backend }
    }
}

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for TracingMakeWriter {
    type Writer = EventWriter;

    fn make_writer(&'a self) -> Self::Writer {
        EventWriter {
            backend: self.backend.clone(),
            record: Vec::with_capacity(512),
            priority: Priority::Normal,
        }
    }

    fn make_writer_for(&'a self, metadata: &tracing::Metadata<'_>) -> Self::Writer {
        EventWriter {
            backend: self.backend.clone(),
            record: Vec::with_capacity(512),
            priority: priority(metadata),
        }
    }
}

pub struct EventWriter {
    backend: Backend,
    record: Vec<u8>,
    priority: Priority,
}

impl EventWriter {
    fn submit(&mut self) -> io::Result<()> {
        if self.record.is_empty() {
            return Ok(());
        }
        let record = std::mem::take(&mut self.record);
        crate::backend::discard_if_full(self.backend.submit_native(&record, self.priority))
            .map_err(|error| io::Error::other(error.to_string()))
    }
}

impl Write for EventWriter {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.record.extend_from_slice(buffer);
        Ok(buffer.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        self.submit()
    }
}

impl Drop for EventWriter {
    fn drop(&mut self) {
        if let Err(error) = self.submit() {
            eprintln!("foundation tracing adapter failed to submit a log record: {error}");
        }
    }
}

pub struct TracingGuard {
    backend: Backend,
}

impl TracingGuard {
    pub fn backend(&self) -> &Backend {
        &self.backend
    }

    pub fn flush(&self) -> crate::Result<()> {
        self.backend.flush()
    }

    pub fn flush_durable(&self) -> crate::Result<()> {
        self.backend.flush_durable()
    }
}

impl Drop for TracingGuard {
    fn drop(&mut self) {
        let _ = self.backend.flush();
    }
}

pub fn build_tracing(
    settings: Settings,
    options: TracingOptions<'_>,
) -> Result<(Dispatch, TracingGuard), BoxError> {
    let optimized = matches!(settings.mode, BackendMode::Memory);
    let backend = Backend::open(settings)?;
    let dispatch = if optimized {
        file_dispatch(
            backend.clone(),
            options,
            fields::FileFields,
            timestamp::UtcTime,
        )
    } else {
        // Preserve the established mmap contention and tail-latency behavior.
        file_dispatch(backend.clone(), options, DefaultFields::new(), SystemTime)
    };
    Ok((dispatch, TracingGuard { backend }))
}

fn file_dispatch<N, T>(
    backend: Backend,
    options: TracingOptions<'_>,
    fields: N,
    timer: T,
) -> Dispatch
where
    N: for<'writer> FormatFields<'writer> + Send + Sync + 'static,
    T: FormatTime + Send + Sync + 'static,
{
    let file_writer = fmt_writer::FmtMakeWriter::new(backend.clone());
    let console_layer = options.console.then(|| {
        tracing_subscriber::fmt::layer()
            .with_writer(std::io::stderr)
            .with_ansi(std::io::stderr().is_terminal())
            .with_target(false)
            .with_file(true)
            .with_line_number(true)
            .with_thread_ids(true)
            .with_thread_names(true)
            .compact()
            .with_filter(log_filter(
                options.primary_filter_env,
                options.default_filter,
            ))
    });
    let file_layer = tracing_subscriber::fmt::layer()
        .fmt_fields(fields)
        .with_timer(timer)
        .with_writer(file_writer)
        .with_ansi(false)
        .with_target(false)
        .with_file(true)
        .with_line_number(true)
        .with_thread_ids(true)
        .with_thread_names(true)
        .compact()
        .with_filter(log_filter(
            options.primary_filter_env,
            options.default_filter,
        ));
    let subscriber = tracing_subscriber::registry()
        .with(console_layer)
        .with(file_layer);
    Dispatch::new(subscriber)
}

pub fn init_tracing(
    settings: Settings,
    options: TracingOptions<'_>,
) -> Result<TracingGuard, BoxError> {
    let (dispatch, guard) = build_tracing(settings, options)?;
    tracing::dispatcher::set_global_default(dispatch)?;
    Ok(guard)
}

fn log_filter(primary_env: Option<&str>, default_filter: &str) -> EnvFilter {
    primary_env
        .and_then(|name| EnvFilter::try_from_env(name).ok())
        .or_else(|| EnvFilter::try_from_default_env().ok())
        .unwrap_or_else(|| EnvFilter::new(default_filter))
}
