//! Reproducible bounded fuzz smoke for public untrusted-input boundaries.
//! This supplements targeted fixtures; it is not a substitute for a persistent
//! sanitizer/libFuzzer campaign or a durability qualification test.
const std = @import("std");
const kron = @import("kron");

test {
    _ = @import("decoder_matrix.zig");
}

test "bounded decoder mutation corpus never escapes its input or emits invalid JSON" {
    var random = std.Random.DefaultPrng.init(0x6b726f6e66757a7a ^ @as(u64, std.testing.random_seed));
    const rng = random.random();
    var original: [4096]u8 = undefined;
    var mutated: [4096]u8 = undefined;
    var encoded_again: [4096]u8 = undefined;
    var text: [16 * 1024]u8 = undefined;
    var scratch: [128]kron.Field = undefined;
    const entries = [_]kron.Field{
        kron.kv("integer", @as(i128, std.math.minInt(i128))),
        kron.kv("float", @as(f64, -0.0)),
        kron.kv("message", "UTF-8 \xc3\xa9\n\"\\"),
        kron.kv("binary", kron.bytes(&.{ 0, 255, 10 })),
    };
    const event: kron.Event = .{
        .level = .info,
        .scope = "fuzz.decoder",
        .message = "a complete event",
        .fields = &entries,
        .timestamp_ns = 123,
        .source = @src(),
    };
    const valid = try kron.codec.encode(event, &original);
    for (0..4096) |iteration| {
        @memcpy(mutated[0..valid.len], valid);
        const changes = 1 + iteration % 4;
        for (0..changes) |_| {
            const index = rng.uintLessThan(usize, valid.len);
            mutated[index] ^= rng.int(u8);
        }
        const length = if (iteration % 3 == 0) rng.uintLessThan(usize, valid.len + 1) else valid.len;
        const input = mutated[0..length];
        const decoded = kron.codec.decode(input, &scratch) catch continue;
        const reencoded = try kron.codec.encode(decoded, &encoded_again);
        // Successful decoding must retain a canonical representation. Changes
        // accepted as ordinary values must never produce out-of-bounds views.
        try std.testing.expectEqualSlices(u8, input, reencoded);
        var output = std.Io.Writer.fixed(&text);
        try kron.encoder.encode(.json, decoded, &output);
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output.buffered(), .{});
        parsed.deinit();
    }
}

test "bounded arbitrary input rejects malformed codec data without allocation" {
    var random = std.Random.DefaultPrng.init(0x756e747275737465 ^ @as(u64, std.testing.random_seed));
    const rng = random.random();
    var bytes: [512]u8 = undefined;
    var scratch: [128]kron.Field = undefined;
    for (0..4096) |_| {
        rng.bytes(&bytes);
        const length = rng.uintLessThan(usize, bytes.len + 1);
        _ = kron.codec.decode(bytes[0..length], &scratch) catch continue;
    }
}

test "bounded malformed deferred formats fail through the writer error boundary" {
    var random = std.Random.DefaultPrng.init(0x666f726d61746675 ^ @as(u64, std.testing.random_seed));
    const rng = random.random();
    var template: [96]u8 = undefined;
    var output_buffer: [32 * 1024]u8 = undefined;
    const args = [_]kron.Field{ kron.kv("0", @as(i64, 42)), kron.kv("name", "value") };
    const alphabet = "{}[]:dxbos.anyname0123456789<^> \n";
    for (0..2048) |_| {
        for (&template) |*byte| byte.* = alphabet[rng.uintLessThan(usize, alphabet.len)];
        var output = std.Io.Writer.fixed(&output_buffer);
        kron.format.render(template[0..rng.uintLessThan(usize, template.len + 1)], &args, &output) catch |err| {
            try std.testing.expectEqual(error.WriteFailed, err);
        };
    }
}
