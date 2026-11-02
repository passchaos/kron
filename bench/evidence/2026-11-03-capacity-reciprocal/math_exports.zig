const Divider = @import("divider").Divider;

export fn capacityQuotient(numerator: u64, divisor: u64, multiplier: u64) u64 {
    return (Divider{ .multiplier = multiplier }).quotient(numerator, divisor);
}

export fn capacityRemainder(numerator: u64, divisor: u64, multiplier: u64) u64 {
    return (Divider{ .multiplier = multiplier }).divide(numerator, divisor).remainder;
}
