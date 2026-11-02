use std::fmt;

use tracing::field::{Field, Visit};
use tracing_subscriber::field::RecordFields;
use tracing_subscriber::field::VisitOutput;
use tracing_subscriber::fmt::format::{DefaultVisitor, FormatFields, Writer};

/// Eager file-field formatting with the same text as DefaultFields. Complex
/// Debug/Error values, escaping and ANSI output use the upstream visitor.
pub(super) struct FileFields;

impl<'writer> FormatFields<'writer> for FileFields {
    fn format_fields<R: RecordFields>(&self, writer: Writer<'writer>, fields: R) -> fmt::Result {
        let mut visitor = FileVisitor {
            writer,
            empty: true,
            result: Ok(()),
        };
        fields.record(&mut visitor);
        visitor.result
    }
}

struct FileVisitor<'writer> {
    writer: Writer<'writer>,
    empty: bool,
    result: fmt::Result,
}

impl FileVisitor<'_> {
    fn prepare(&mut self, field: &Field) -> fmt::Result {
        if !self.empty {
            self.writer.write_char(' ')?;
        }
        self.empty = false;
        if field.name() != "message" {
            self.writer
                .write_str(field.name().strip_prefix("r#").unwrap_or(field.name()))?;
            self.writer.write_char('=')?;
        }
        Ok(())
    }

    fn skipped(&self, field: &Field) -> bool {
        self.result.is_err() || field.name().starts_with("log.")
    }

    fn numeric(&mut self, field: &Field, digits: &[u8]) {
        self.result = self.prepare(field).and_then(|()| {
            self.writer
                .write_str(std::str::from_utf8(digits).expect("decimal digits are ASCII"))
        });
    }
}

impl Visit for FileVisitor<'_> {
    fn record_u64(&mut self, field: &Field, value: u64) {
        if self.skipped(field) {
            return;
        }
        if self.writer.has_ansi_escapes() {
            self.record_debug(field, &value);
            return;
        }
        let mut digits = [0; 20];
        let start = crate::decimal::format_u64(&mut digits, value);
        self.numeric(field, &digits[start..]);
    }

    fn record_i64(&mut self, field: &Field, value: i64) {
        if self.skipped(field) {
            return;
        }
        if self.writer.has_ansi_escapes() {
            self.record_debug(field, &value);
            return;
        }
        let mut digits = [0; 20];
        let start = crate::decimal::format_i64(&mut digits, value);
        self.numeric(field, &digits[start..]);
    }

    fn record_bool(&mut self, field: &Field, value: bool) {
        if self.skipped(field) {
            return;
        }
        if self.writer.has_ansi_escapes() {
            self.record_debug(field, &value);
            return;
        }
        self.result = self
            .prepare(field)
            .and_then(|()| self.writer.write_str(if value { "true" } else { "false" }));
    }

    fn record_str(&mut self, field: &Field, value: &str) {
        if self.skipped(field) {
            return;
        }
        if self.writer.has_ansi_escapes()
            || !value
                .bytes()
                .all(|byte| (b' '..0x7f).contains(&byte) && byte != b'"' && byte != b'\\')
        {
            let mut visitor = DefaultVisitor::new(self.writer.by_ref(), self.empty);
            visitor.record_str(field, value);
            self.result = visitor.finish();
            self.empty = false;
            return;
        }
        self.result = (|| {
            self.prepare(field)?;
            if field.name() != "message" {
                self.writer.write_char('"')?;
            }
            self.writer.write_str(value)?;
            if field.name() != "message" {
                self.writer.write_char('"')?;
            }
            Ok(())
        })();
    }

    fn record_debug(&mut self, field: &Field, value: &dyn fmt::Debug) {
        if self.skipped(field) {
            return;
        }
        let mut visitor = DefaultVisitor::new(self.writer.by_ref(), self.empty);
        visitor.record_debug(field, value);
        self.result = visitor.finish();
        self.empty = false;
    }

    fn record_error(&mut self, field: &Field, value: &(dyn std::error::Error + 'static)) {
        if self.skipped(field) {
            return;
        }
        let mut visitor = DefaultVisitor::new(self.writer.by_ref(), self.empty);
        visitor.record_error(field, value);
        self.result = visitor.finish();
        self.empty = false;
    }
}
