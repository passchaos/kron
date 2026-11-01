//! Portable fixed-offset wall-time and Gregorian calendar support. Time-zone
//! databases, daylight saving and hidden system/environment lookup are excluded.
pub const civil = @import("civil.zig");
pub const Date = civil.Date;
pub const DateTime = civil.DateTime;
pub const Weekday = civil.Weekday;
pub const isLeapYear = civil.isLeapYear;
pub const daysInMonth = civil.daysInMonth;
pub const Timestamp = @import("types.zig").Timestamp;
pub const Duration = @import("types.zig").Duration;
pub const UtcOffset = @import("types.zig").UtcOffset;
pub const rfc3339 = @import("rfc3339.zig");
pub const Formatter = rfc3339.Formatter;
pub const FormatOptions = rfc3339.Options;
pub const Precision = rfc3339.Precision;

test {
    _ = civil;
    _ = @import("types.zig");
    _ = rfc3339;
}
