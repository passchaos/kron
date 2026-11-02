// Calendar conversion follows musl __secs_to_tm, as used by tracing-subscriber.
// Copyright (c) 2005-2020 Rich Felker, et al.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use std::cell::RefCell;
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};
use tracing_subscriber::fmt::format::Writer;
use tracing_subscriber::fmt::time::FormatTime;

thread_local! {
    static PREFIX: RefCell<Option<(i64, String)>> = const { RefCell::new(None) };
}

pub(super) struct UtcTime;

impl FormatTime for UtcTime {
    fn format_time(&self, writer: &mut Writer<'_>) -> fmt::Result {
        format_timestamp(writer, SystemTime::now())
    }
}

fn format_timestamp(writer: &mut Writer<'_>, time: SystemTime) -> fmt::Result {
    let (seconds, nanos) = match time.duration_since(UNIX_EPOCH) {
        Ok(duration) => (
            i64::try_from(duration.as_secs()).map_err(|_| fmt::Error)?,
            duration.subsec_nanos(),
        ),
        Err(error) => {
            let duration = error.duration();
            let fraction = duration.subsec_nanos();
            let seconds = -i128::from(duration.as_secs()) - i128::from(fraction != 0);
            (
                i64::try_from(seconds).map_err(|_| fmt::Error)?,
                if fraction == 0 {
                    0
                } else {
                    1_000_000_000 - fraction
                },
            )
        }
    };
    PREFIX.with(|prefix| {
        if let Ok(mut cached) = prefix.try_borrow_mut() {
            if cached.as_ref().is_none_or(|(key, _)| *key != seconds) {
                *cached = Some((seconds, calendar_prefix(seconds)));
            }
            writer.write_str(&cached.as_ref().unwrap().1)?;
        } else {
            // A recursive fmt::Write callback must not panic on a TLS borrow.
            writer.write_str(&calendar_prefix(seconds))?;
        }
        let mut value = nanos / 1000;
        let mut digits = [b'0'; 6];
        for digit in digits.iter_mut().rev() {
            *digit += (value % 10) as u8;
            value /= 10;
        }
        writer.write_char('.')?;
        writer.write_str(std::str::from_utf8(&digits).map_err(|_| fmt::Error)?)?;
        writer.write_char('Z')
    })
}

fn calendar_prefix(seconds: i64) -> String {
    const LEAPOCH: i64 = 946_684_800 + 86400 * (31 + 29);
    const DAYS_400: i64 = 146_097;
    const DAYS_100: i64 = 36_524;
    const DAYS_4: i64 = 1461;
    const MONTHS: [i64; 12] = [31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 31, 29];
    let mut days = seconds.div_euclid(86400) - LEAPOCH / 86400;
    let within_day = seconds.rem_euclid(86400);
    let cycles = days.div_euclid(DAYS_400);
    days = days.rem_euclid(DAYS_400);
    let centuries = (days / DAYS_100).min(3);
    days -= centuries * DAYS_100;
    let four_years = (days / DAYS_4).min(24);
    days -= four_years * DAYS_4;
    let years = (days / 365).min(3);
    days -= years * 365;
    let mut year = 2000 + cycles * 400 + centuries * 100 + four_years * 4 + years;
    let mut month = 0;
    while MONTHS[month] <= days {
        days -= MONTHS[month];
        month += 1;
    }
    let month = if month >= 10 {
        year += 1;
        month - 9
    } else {
        month + 3
    };
    let year = if year > 9999 {
        format!("+{year}")
    } else if year < 0 {
        format!("{year:05}")
    } else {
        format!("{year:04}")
    };
    format!(
        "{year}-{month:02}-{:02}T{:02}:{:02}:{:02}",
        days + 1,
        within_day / 3600,
        within_day / 60 % 60,
        within_day % 60
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn timestamp_keeps_microseconds_and_calendar_boundaries() {
        let cases = [
            (0, 0, "1970-01-01T00:00:00.000000Z"),
            (0, 123456789, "1970-01-01T00:00:00.123456Z"),
            (1, 999999999, "1970-01-01T00:00:01.999999Z"),
            (-1, 500000000, "1969-12-31T23:59:59.500000Z"),
            (951782400, 1, "2000-02-29T00:00:00.000000Z"),
            (2147483648, 0, "2038-01-19T03:14:08.000000Z"),
            (-2208988800, 0, "1900-01-01T00:00:00.000000Z"),
            (-62167219200, 0, "0000-01-01T00:00:00.000000Z"),
            (-62167219201, 0, "-0001-12-31T23:59:59.000000Z"),
            (253402300800, 0, "+10000-01-01T00:00:00.000000Z"),
            (i64::MAX, 0, "+292277026596-12-04T15:30:07.000000Z"),
            (i64::MIN + 1, 0, "-292277022657-01-27T08:29:53.000000Z"),
            (i64::MIN, 0, "-292277022657-01-27T08:29:52.000000Z"),
        ];
        for (seconds, nanos, expected) in cases.into_iter().chain(cases.into_iter().rev()) {
            let time = if seconds >= 0 {
                UNIX_EPOCH + Duration::new(seconds as u64, nanos)
            } else {
                UNIX_EPOCH - Duration::new(seconds.unsigned_abs(), 0) + Duration::new(0, nanos)
            };
            let mut text = String::new();
            format_timestamp(&mut Writer::new(&mut text), time).unwrap();
            assert_eq!(text, expected);
        }
    }

    #[test]
    #[cfg(target_pointer_width = "64")]
    fn calendar_matches_libc_across_random_dates() {
        let mut state = 0x91bd_2738_53ab_468fu64;
        for _ in 0..10_000 {
            state ^= state << 7;
            state ^= state >> 9;
            state ^= state << 8;
            let seconds = (state % 255_611_289_599) as i64 - 2_208_988_800;
            let mut tm = std::mem::MaybeUninit::<libc::tm>::uninit();
            assert!(!unsafe { libc::gmtime_r(&seconds, tm.as_mut_ptr()) }.is_null());
            let tm = unsafe { tm.assume_init() };
            let expected = format!(
                "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
                tm.tm_year + 1900,
                tm.tm_mon + 1,
                tm.tm_mday,
                tm.tm_hour,
                tm.tm_min,
                tm.tm_sec
            );
            assert_eq!(calendar_prefix(seconds), expected);
        }
    }
}
