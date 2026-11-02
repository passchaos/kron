use std::io::{self, Write};

use crate::{Backend, Priority};

/// Private to the fmt layer, which hands write_all one already formatted event.
/// The public TracingMakeWriter still coalesces fragmented writes until flush
/// or drop. No pointer into the subscriber's reusable buffer is retained.
pub(super) struct FmtMakeWriter {
    backend: Backend,
}

impl FmtMakeWriter {
    pub(super) fn new(backend: Backend) -> Self {
        Self { backend }
    }
}

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for FmtMakeWriter {
    type Writer = FmtWriter<'a>;

    fn make_writer(&'a self) -> Self::Writer {
        FmtWriter {
            backend: &self.backend,
            priority: Priority::Normal,
        }
    }

    fn make_writer_for(&'a self, metadata: &tracing::Metadata<'_>) -> Self::Writer {
        FmtWriter {
            backend: &self.backend,
            priority: super::priority(metadata),
        }
    }
}

pub(super) struct FmtWriter<'a> {
    backend: &'a Backend,
    priority: Priority,
}

impl Write for FmtWriter<'_> {
    fn write(&mut self, record: &[u8]) -> io::Result<usize> {
        if !record.is_empty() {
            crate::backend::discard_if_full(self.backend.submit_native(record, self.priority))
                .map_err(|error| {
                    eprintln!("foundation tracing adapter failed to submit a log record: {error}");
                    io::Error::other(error.to_string())
                })?;
        }
        Ok(record.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        // Records were accepted or deliberately dropped; barriers use the guard.
        Ok(())
    }
}
