//! This module provides a standards-compliant UUIDv7 implementation that generates
//! monotonically increasing, timestamp-based UUIDs with the following properties:
//!
//! - First 48 bits: Unix timestamp in milliseconds
//! - Next 4 bits: Version (7)
//! - Next 12 bits: Monotonic counter for same-timestamp UUIDs
//! - Next 2 bits: UUID variant (2)
//! - Final 62 bits: Random data
//!
//! This implementation is inpsired by github.com/google/uuid, a uuid package for Go.

const std = @import("std");
const math = std.math;
const time = std.time;
const Random = std.Random;

/// A UUIDv7 value represented as a 128-bit unsigned integer
pub const Uuid = u128;

/// Error set for UUID operations
pub const Error = error{
    /// Buffer size mismatch
    BufferTooSmall,
};

/// Mutex for protecting shared state
var time_mutex = std.Thread.Mutex{};
/// Last timestamp+sequence we returned
var last_time: i128 = 0;

/// Generator for UUIDv7 values
pub const Generator = struct {
    /// Random number generator
    random: Random,

    /// Initialize a new generator with given random source
    pub fn init(random: Random) Generator {
        return .{ .random = random };
    }

    /// Get timestamp and sequence that's guaranteed to be monotonic
    fn getMonotonicTime() struct { milli: i64, seq: i64 } {
        time_mutex.lock();
        defer time_mutex.unlock();

        const nano = time.nanoTimestamp();
        const milli = @divFloor(nano, time.ns_per_ms);

        // Get sequence number between 0 and 3906 (ns_per_ms>>8)
        const seq = (nano - milli * time.ns_per_ms) >> 8;
        const now = (milli << 12) + seq;

        // Ensure monotonicity
        const timestamp = if (now <= last_time)
            last_time + 1
        else
            now;

        last_time = timestamp;

        return .{ .milli = @intCast(timestamp >> 12), .seq = @intCast(timestamp & 0xfff) };
    }

    /// Generate a new UUIDv7 value
    pub fn next(self: *Generator) Error!Uuid {
        // Get monotonic time components
        const t = getMonotonicTime();

        // Generate 62 bits of randomness for bottom bits
        const rand_b = self.random.int(u62);

        // Assemble UUID components
        var uuid: Uuid = 0;
        uuid |= @as(u128, @intCast(t.milli)) << 80; // timestamp (48 bits)
        uuid |= @as(u128, 0x7) << 76; // version 7 (4 bits)
        uuid |= @as(u128, @intCast(t.seq)) << 64; // sequence (12 bits)
        uuid |= @as(u128, 0x2) << 62; // RFC variant (2 bits)
        uuid |= rand_b; // random bits (62 bits)

        return uuid;
    }
};

/// Create a cryptographically secure UUIDv7 generator
pub fn initSecure() Generator {
    return Generator.init(std.crypto.random);
}

/// Convert UUID to canonical string format with hyphens (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
pub fn format(uuid: Uuid, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) (@TypeOf(writer).Error)!void {
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u128, &bytes, uuid, .big);

    try std.fmt.format(writer, "{}-{}-{}-{}-{}", .{
        std.fmt.fmtSliceHexLower(bytes[0..4]),
        std.fmt.fmtSliceHexLower(bytes[4..6]),
        std.fmt.fmtSliceHexLower(bytes[6..8]),
        std.fmt.fmtSliceHexLower(bytes[8..10]),
        std.fmt.fmtSliceHexLower(bytes[10..16]),
    });
}

/// Convert UUID to string using a fixed buffer
pub fn toString(uuid: Uuid, buf: *[36]u8) []const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    format(uuid, "", .{}, fbs.writer()) catch unreachable;
    return fbs.getWritten();
}

test "UUIDv7 generation and monotonicity" {
    var gen = initSecure();
    var last = try gen.next();

    // Generate several UUIDs and verify they are monotonically increasing
    for (0..1000) |_| {
        const uuid = try gen.next();
        try std.testing.expect(uuid > last);
        last = uuid;
    }
}

test "UUIDv7 format" {
    const uuid: Uuid = 0x0123456789abcdef0123456789abcdef; // 01234567-89ab-cdef-0123-456789abcdef
    var buf: [36]u8 = undefined;

    const uuid_str_want = "01234567-89ab-cdef-0123-456789abcdef";
    const uuid_str_got = toString(uuid, &buf);

    try std.testing.expectEqualStrings(uuid_str_want, uuid_str_got);
}
