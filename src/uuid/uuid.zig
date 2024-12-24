//! This module provides a standards-compliant UUIDv7 implementation that generates
//! monotonically increasing, timestamp-based UUIDs with the following properties:
//!
//! - First 48 bits: Unix timestamp in milliseconds
//! - Next 4 bits: Version (7)
//! - Next 12 bits: Monotonic counter for same-timestamp UUIDs
//! - Next 2 bits: UUID variant (2)
//! - Final 62 bits: Random data
//!
//! Example:
//! ```zig
//! var gen = initSecure();
//! const uuid = try gen.next();
//! var buf: [36]u8 = undefined;
//! const formatted = toString(uuid, &buf);
//! // Output: 018df210-1c50-7a0f-9e4f-8ada87ad71b2
//! ```
//!
//! Thread safety: Generator instances should not be shared across threads.
//! Use separate generators per thread to maintain monotonicity.
//!
//! Sources of inspiration and orientation:
//!   - https://en.wikipedia.org/wiki/Universally_unique_identifier#Version_7_(timestamp_and_random)
//!   - https://www.ietf.org/archive/id/draft-peabody-dispatch-new-uuid-format-03.html#name-uuid-version-7
//!   - Various GitHub repositories

const std = @import("std");
const math = std.math;
const time = std.time;
const Random = std.rand.Random;

/// A UUIDv7 value represented as a 128-bit unsigned integer
pub const Uuid = u128;

/// Error set for UUID operations
pub const Error = error{
    /// Timestamp overflow - beyond year 10889
    TimestampOverflow,
    /// Timestamp is from before Unix epoch
    TimestampUnderflow,
};

/// UUIDv7 Generator state
/// Maintains monotonicity by tracking the last timestamp and counter
const State = struct {
    /// Last timestamp used for UUID generation
    last_ts: i64 = 0,
    /// Counter for UUIDs generated in same timestamp
    counter: u32 = 0,
    /// Max counter value before we need to wait for next timestamp
    /// Using 12 bits for counter (in rand_a)
    const max_counter = (1 << 12) - 1;

    /// Reset counter if we're on a new timestamp
    fn updateState(self: *State, curr_ts: i64) void {
        if (curr_ts > self.last_ts) {
            self.last_ts = curr_ts;
            self.counter = 0;
        } else {
            self.counter +%= 1;
        }
    }

    /// Check if we can generate another UUID at current timestamp
    fn canGenerate(self: *const State) bool {
        return self.counter <= max_counter;
    }
};

/// Generator for UUIDv7 values
pub const Generator = struct {
    /// Random number generator
    random: Random,
    /// Generator state for monotonicity
    state: State = .{},

    /// Initialize a new generator with given random source
    pub fn init(random: Random) Generator {
        return .{
            .random = random,
        };
    }

    /// Generate a new UUIDv7 value
    /// Returns error.TimestampOverflow if timestamp exceeds 2^48-1 milliseconds
    /// Returns error.TimestampUnderflow if timestamp is before Unix epoch
    pub fn next(self: *Generator) Error!Uuid {
        // Get current timestamp
        const now = time.milliTimestamp();

        // Check timestamp bounds
        if (now < 0) return error.TimestampUnderflow;
        if (now >= (1 << 48)) return error.TimestampOverflow;

        // Update generator state
        self.state.updateState(now);
        if (!self.state.canGenerate()) {
            // Wait for next millisecond if counter exhausted
            while (time.milliTimestamp() <= now) {}
            return self.next();
        }

        // Convert timestamp to unsigned 48-bit big-endian value
        const ts_bytes = @as(u48, @intCast(now));

        // Generate 62 bits of random data for rand_b
        const rand_b = self.random.int(u62);

        // Assemble UUID components:
        // - 48 bits timestamp
        // - 4 bits version (7)
        // - 12 bits rand_a (using counter for monotonicity)
        // - 2 bits variant (2)
        // - 62 bits rand_b
        var uuid: Uuid = 0;
        uuid |= @as(u128, ts_bytes) << 80; // timestamp
        uuid |= @as(u128, 0x7) << 76; // version
        uuid |= @as(u128, self.state.counter) << 64; // rand_a (counter)
        uuid |= @as(u128, 0x2) << 62; // variant
        uuid |= @as(u128, rand_b); // rand_b

        return uuid;
    }
};

/// Create a cryptographically secure UUIDv7 generator
pub fn initSecure() Generator {
    return Generator.init(std.crypto.random);
}

/// Convert UUID to canonical string format with hyphens (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
pub fn toString(uuid: Uuid, buf: []u8) []const u8 {
    std.debug.assert(buf.len >= 36);
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u128, &bytes, uuid, .big);

    const hex_digits = "0123456789abcdef";
    var i: usize = 0;
    var j: usize = 0;

    // Write groups with proper hyphen placement:
    // 8 chars - hyphen - 4 chars - hyphen - 4 chars - hyphen - 4 chars - hyphen - 12 chars

    // First 8 chars (4 bytes)
    while (i < 8) : (i += 2) {
        buf[i] = hex_digits[bytes[j] >> 4];
        buf[i + 1] = hex_digits[bytes[j] & 0x0f];
        j += 1;
    }
    buf[i] = '-';
    i += 1;

    // Next 4 chars (2 bytes)
    var count: usize = 0;
    while (count < 4) : (count += 2) {
        buf[i] = hex_digits[bytes[j] >> 4];
        buf[i + 1] = hex_digits[bytes[j] & 0x0f];
        j += 1;
        i += 2;
    }
    buf[i] = '-';
    i += 1;

    // Next 4 chars (2 bytes)
    count = 0;
    while (count < 4) : (count += 2) {
        buf[i] = hex_digits[bytes[j] >> 4];
        buf[i + 1] = hex_digits[bytes[j] & 0x0f];
        j += 1;
        i += 2;
    }
    buf[i] = '-';
    i += 1;

    // Next 4 chars (2 bytes)
    count = 0;
    while (count < 4) : (count += 2) {
        buf[i] = hex_digits[bytes[j] >> 4];
        buf[i + 1] = hex_digits[bytes[j] & 0x0f];
        j += 1;
        i += 2;
    }
    buf[i] = '-';
    i += 1;

    // Final 12 chars (6 bytes)
    while (j < 16) : (j += 1) {
        buf[i] = hex_digits[bytes[j] >> 4];
        buf[i + 1] = hex_digits[bytes[j] & 0x0f];
        i += 2;
    }

    return buf[0..36];
}

test "UUIDv7 generation and monotonicity" {
    var gen = initSecure();
    var last = try gen.next();

    // Generate several UUIDs and verify they are monotonically increasing
    for (0..1000) |_| {
        // var buf: [36]u8 = undefined;
        // const formatted = toString(last, &buf);
        // std.debug.print("{s}\n", .{formatted});

        const uuid = try gen.next();
        try std.testing.expect(uuid > last);
        last = uuid;
    }
}
