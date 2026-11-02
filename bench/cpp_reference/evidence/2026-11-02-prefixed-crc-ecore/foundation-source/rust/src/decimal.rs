const MAX_U64_DIGITS: usize = 20;

#[inline]
pub(crate) fn format_i64(output: &mut [u8; MAX_U64_DIGITS], value: i64) -> usize {
    let mut cursor = format_u64(output, value.unsigned_abs());
    if value < 0 {
        cursor -= 1;
        output[cursor] = b'-';
    }
    cursor
}

pub(crate) fn format_u64(output: &mut [u8; MAX_U64_DIGITS], mut value: u64) -> usize {
    let mut cursor = output.len();
    loop {
        let quotient = value / 10;
        cursor -= 1;
        output[cursor] = b'0' + (value - quotient * 10) as u8;
        value = quotient;
        if value == 0 {
            break;
        }
    }
    cursor
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn specialized_decimal_formatters_match_standard_formatting() {
        let mut unsigned_values = vec![0, 1, 8, 9, u64::MAX];
        let mut power = 10u64;
        while power <= 1_000_000_000_000_000_000 {
            unsigned_values.extend([power - 1, power, power + 1]);
            power *= 10;
        }
        let mut state = 0x9e37_79b9_7f4a_7c15u64;
        for _ in 0..20_000 {
            state ^= state << 7;
            state ^= state >> 9;
            state ^= state << 8;
            unsigned_values.push(state);
        }

        let mut unsigned = [0u8; MAX_U64_DIGITS];
        let mut signed = [0u8; MAX_U64_DIGITS];
        for value in unsigned_values {
            let start = format_u64(&mut unsigned, value);
            assert_eq!(&unsigned[start..], value.to_string().as_bytes());

            let value = value as i64;
            let start = format_i64(&mut signed, value);
            assert_eq!(&signed[start..], value.to_string().as_bytes());
        }
        for value in [i64::MIN, -1, 0, 1, i64::MAX] {
            let start = format_i64(&mut signed, value);
            assert_eq!(&signed[start..], value.to_string().as_bytes());
        }
    }
}
