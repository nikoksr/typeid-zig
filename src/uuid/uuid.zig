//! This module provides a standards-compliant UUIDv7 implementation that generates
//! monotonically increasing, timestamp-based UUIDs with the following properties:
//!
//! - First 48 bits: Unix timestamp in milliseconds
//! - Next 4 bits: Version (7)
//! - Next 12 bits: Monotonic counter for same-timestamp UUIDs
//! - Next 2 bits: UUID variant (2)
//! - Final 62 bits: Random data
//!
//! This implementation is inspired by github.com/google/uuid, a uuid package for Go.

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

/// Generator for UUIDv7 values
pub const Generator = struct {
    /// Random number generator
    random: Random,
    /// Mutex for protecting per-generator state
    mutex: std.Thread.Mutex = .{},
    /// Last timestamp+sequence this generator returned
    last_time: i128 = 0,

    /// Initialize a new generator with given random source
    pub fn init(random: Random) Generator {
        return .{ .random = random };
    }

    /// Get timestamp and sequence that's guaranteed to be monotonic
    fn getMonotonicTime(self: *Generator) struct { milli: i64, seq: i64 } {
        self.mutex.lock();
        defer self.mutex.unlock();

        const nano = time.nanoTimestamp();
        const milli = @divFloor(nano, time.ns_per_ms);

        // Get sequence number between 0 and 3906 (ns_per_ms>>8)
        const seq = (nano - milli * time.ns_per_ms) >> 8;
        const now = (milli << 12) + seq;

        // Ensure monotonicity
        const timestamp = if (now <= self.last_time)
            self.last_time + 1
        else
            now;

        self.last_time = timestamp;

        return .{ .milli = @intCast(timestamp >> 12), .seq = @intCast(timestamp & 0xfff) };
    }

    /// Generate a new UUIDv7 value
    pub fn next(self: *Generator) Error!Uuid {
        // Get monotonic time components
        const t = self.getMonotonicTime();

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

test "RFC 9562 - UUIDv7 bit layout compliance" {
    var gen = initSecure();
    const test_uuid = try gen.next();
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u128, &bytes, test_uuid, .big);

    // Verify version field (bits 48-51, octet 6 high nibble) = 0b0111 (7)
    const version = (bytes[6] & 0xF0) >> 4;
    try std.testing.expectEqual(@as(u8, 0x7), version);

    // Verify variant field (bits 64-65, octet 8 MSBs) = 0b10
    const variant = (bytes[8] & 0xC0) >> 6;
    try std.testing.expectEqual(@as(u8, 0b10), variant);

    // Verify timestamp exists (bits 0-47, octets 0-5)
    const timestamp = (@as(u64, bytes[0]) << 40) |
        (@as(u64, bytes[1]) << 32) |
        (@as(u64, bytes[2]) << 24) |
        (@as(u64, bytes[3]) << 16) |
        (@as(u64, bytes[4]) << 8) |
        (@as(u64, bytes[5]));
    try std.testing.expect(timestamp > 0);
}

test "RFC 9562 - monotonicity guarantee" {
    var gen = initSecure();
    var last = try gen.next();

    // Verify monotonic ordering across 10,000 UUIDs
    for (0..10_000) |_| {
        const current = try gen.next();
        try std.testing.expect(current > last);
        last = current;
    }
}

test "RFC 9562 - string format compliance" {
    var gen = initSecure();
    const test_uuid = try gen.next();
    var buf: [36]u8 = undefined;
    const uuid_str = toString(test_uuid, &buf);

    // Verify length and dash positions per RFC format:
    // xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    try std.testing.expectEqual(@as(usize, 36), uuid_str.len);
    try std.testing.expectEqual(@as(u8, '-'), uuid_str[8]);
    try std.testing.expectEqual(@as(u8, '-'), uuid_str[13]);
    try std.testing.expectEqual(@as(u8, '-'), uuid_str[18]);
    try std.testing.expectEqual(@as(u8, '-'), uuid_str[23]);

    // Verify all non-dash characters are hexadecimal
    for (uuid_str, 0..) |c, i| {
        if (i == 8 or i == 13 or i == 18 or i == 23) continue;
        const is_hex = (c >= '0' and c <= '9') or
            (c >= 'a' and c <= 'f') or
            (c >= 'A' and c <= 'F');
        try std.testing.expect(is_hex);
    }
}

test "collision safety - single generator" {
    var gen = initSecure();
    var seen = std.AutoHashMap(Uuid, void).init(std.testing.allocator);
    defer seen.deinit();

    const count = 100_000;
    var last: Uuid = 0;

    for (0..count) |_| {
        const id = try gen.next();

        // Check monotonicity (must always increase)
        try std.testing.expect(id > last);
        last = id;

        // Check for duplicates
        const result = try seen.getOrPut(id);
        try std.testing.expect(!result.found_existing);
    }
}

test "collision safety - multiple generators produce different UUIDs" {
    var gen1 = initSecure();
    var gen2 = initSecure();

    const id1 = try gen1.next();
    const id2 = try gen2.next();

    // Different generators should produce different UUIDs
    // (62 bits of randomness make collisions virtually impossible)
    try std.testing.expect(id1 != id2);
}

test "collision safety - multi-threaded generation" {
    const ThreadContext = struct {
        gen: Generator,
        ids: std.ArrayList(Uuid),

        fn worker(ctx: *@This()) !void {
            for (0..1000) |_| {
                const id = try ctx.gen.next();
                try ctx.ids.append(id);
            }
        }
    };

    const num_threads = 8;
    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    // Initialize contexts
    for (0..num_threads) |i| {
        contexts[i] = .{
            .gen = initSecure(),
            .ids = std.ArrayList(Uuid).init(std.testing.allocator),
        };
    }
    defer {
        for (0..num_threads) |i| {
            contexts[i].ids.deinit();
        }
    }

    // Spawn threads
    for (0..num_threads) |i| {
        threads[i] = try std.Thread.spawn(.{}, ThreadContext.worker, .{&contexts[i]});
    }

    // Wait for completion
    for (0..num_threads) |i| {
        threads[i].join();
    }

    // Check each generator's UUIDs are monotonic
    for (contexts) |ctx| {
        var last: Uuid = 0;
        for (ctx.ids.items) |id| {
            try std.testing.expect(id > last);
            last = id;
        }
    }

    // Collect all UUIDs and check for duplicates
    var all_ids = std.AutoHashMap(Uuid, void).init(std.testing.allocator);
    defer all_ids.deinit();

    for (contexts) |ctx| {
        for (ctx.ids.items) |id| {
            const result = try all_ids.getOrPut(id);
            try std.testing.expect(!result.found_existing);
        }
    }
}

