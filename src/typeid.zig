//! TypeID implementation that provides type-safe UUIDv7s with a type prefix.
//! Implements the TypeID spec v0.3.0 from https://github.com/jetify-com/typeid
//!
//! A TypeID consists of:
//! - A type prefix in snake_case [a-z_] (max 63 chars)
//! - An underscore separator (omitted if prefix empty)
//! - A 26-character base32-encoded UUIDv7
//!
//! Example:
//! ```zig
//! // Create a new TypeID with prefix
//! const tid = try TypeID.init("user");
//!
//! // Get string representation
//! var buf: [90]u8 = undefined;
//! const str = try tid.toString(&buf);
//! // str = "user_01h455vb4pex5vsknk084sn02q"
//!
//! // Parse existing TypeID string
//! const parsed = try TypeID.fromString("post_01h455vb4pex5vsknk084sn02q");
//!
//! // Builder pattern with configuration
//! const configured = try TypeIDBuilder.init()
//!     .setPrefix("user")
//!     .build();
//! ```

const std = @import("std");
const uuid = @import("uuid/uuid.zig");
const base32 = @import("base32/base32.zig");
const testing = std.testing;

/// TypeID-specific errors with descriptive messages
pub const Error = error{
    /// Suffix string cannot be empty
    EmptySuffix,
    /// Separator not allowed when prefix is empty
    EmptyPrefixWithSeparator,
    /// Prefix must be 63 characters or less
    InvalidPrefixLength,
    /// Prefix cannot start with underscore
    InvalidPrefixStart,
    /// Prefix cannot end with underscore
    InvalidPrefixEnd,
    /// Prefix cannot contain consecutive underscores
    InvalidPrefixConsecutiveUnderscores,
    /// Prefix can only contain [a-z_] characters
    InvalidPrefixChars,
    /// Suffix must be exactly 26 characters
    InvalidSuffixLength,
    /// Suffix first character must be 0-7 to avoid overflow
    InvalidSuffixOverflow,
    /// Suffix contains invalid base32 characters
    InvalidSuffixChars,
    /// Provided buffer is too small for string representation
    BufferTooSmall,
};

/// A custom type for the 26-character base32 suffix to prevent confusion with other strings
const Suffix = struct {
    /// The actual base32-encoded value
    value: [26]u8,

    /// Creates a new suffix by encoding 16 bytes into base32
    pub fn fromBytes(bytes: [16]u8) Suffix {
        return .{ .value = base32.encode(bytes) };
    }

    /// Decodes the base32 suffix back into 16 bytes
    pub fn toBytes(self: Suffix) !([16]u8) {
        return base32.decode(&self.value);
    }
};

/// TypeID represents a type-safe extension of UUIDv7 with a type prefix.
///
/// A TypeID is composed of:
/// - A type prefix of up to 63 characters in [a-z_] format
/// - An underscore separator (omitted if prefix is empty)
/// - A 26-character base32-encoded UUID suffix
///
/// Example: "user_01h455vb4pex5vsknk084sn02q"
pub const TypeID = struct {
    /// Type prefix (e.g. "user", "post", etc). Must match [a-z_] pattern.
    prefix: []const u8,

    /// Base32-encoded UUIDv7 suffix (exactly 26 characters).
    suffix: Suffix,

    const Self = @This();

    /// The character used to separate prefix from suffix
    const separator = blk: {
        const c = '_';
        if (!std.ascii.isASCII(c)) @compileError("separator must be ASCII");
        break :blk c;
    };

    /// A suffix representing a zero UUID
    const zero_suffix = blk: {
        const z = "00000000000000000000000000".*;
        if (z.len != 26) @compileError("zero suffix must be 26 characters");
        break :blk Suffix{ .value = z };
    };

    /// Creates a new TypeID with the given prefix and a random UUIDv7 suffix.
    /// Validates prefix according to spec requirements.
    /// Prefix must:
    /// - Be max 63 characters
    /// - Contain only [a-z_] characters
    /// - Not start or end with underscore
    /// Returns error if prefix is invalid
    pub fn init(prefix: []const u8) !Self {
        return initWithSuffix(prefix, "");
    }

    /// Creates a new TypeID with the given prefix and an existing suffix
    pub fn initWithSuffix(prefix: []const u8, suffix: []const u8) !Self {
        try validatePrefix(prefix);

        var actual_suffix: Suffix = undefined;
        if (suffix.len == 0) {
            // Generate random UUIDv7-based suffix
            var generator = uuid.initSecure();
            const id = try generator.next();
            var id_bytes: [16]u8 = undefined;
            std.mem.writeInt(u128, &id_bytes, id, .big);
            actual_suffix = Suffix.fromBytes(id_bytes);
        } else {
            try validateSuffix(suffix);
            @memcpy(&actual_suffix.value, suffix);
        }

        return Self{
            .prefix = prefix,
            .suffix = actual_suffix,
        };
    }

    /// Creates a new TypeID from a string in the format "prefix_suffix"
    pub fn fromString(tid: []const u8) !Self {
        const split_at = std.mem.lastIndexOfScalar(u8, tid, separator);
        if (split_at == null) {
            // When there's no separator, treat entire string as suffix
            return initWithSuffix("", tid);
        }

        const prefix = tid[0..split_at.?];
        const suffix = tid[split_at.? + 1 ..];

        if (prefix.len == 0) {
            return Error.EmptyPrefixWithSeparator;
        }

        return initWithSuffix(prefix, suffix);
    }

    /// Creates a new TypeID from a UUID string, using the given prefix
    pub fn fromUUID(prefix: []const u8, uuid_str: []const u8) !Self {
        // Parse UUID string
        const id = try std.fmt.parseUnsigned(u128, uuid_str, 16);
        var bytes: [16]u8 = undefined;
        std.mem.writeInt(u128, &bytes, id, .big);
        return fromUUIDBytes(prefix, &bytes);
    }

    /// Creates a new TypeID from raw UUID bytes, using the given prefix
    pub fn fromUUIDBytes(prefix: []const u8, bytes: []const u8) !Self {
        if (bytes.len != 16) {
            return error.InvalidUUIDLength;
        }
        return Self{
            .prefix = prefix,
            .suffix = Suffix.fromBytes(bytes[0..16].*),
        };
    }

    /// Converts the TypeID to its string representation
    pub fn toString(self: Self, buf: []u8) Error![]const u8 {
        const needed_size = if (self.prefix.len > 0)
            self.prefix.len + 1 + self.suffix.value.len
        else
            self.suffix.value.len;

        if (buf.len < needed_size) {
            return error.BufferTooSmall;
        }

        var i: usize = 0;
        if (self.prefix.len > 0) {
            @memcpy(buf[0..self.prefix.len], self.prefix);
            i = self.prefix.len;
            buf[i] = separator;
            i += 1;
        }

        @memcpy(buf[i .. i + 26], &self.suffix.value);
        i += 26;

        return buf[0..i];
    }

    /// Returns the UUID bytes from the suffix
    pub fn toUUIDBytes(self: Self) ![16]u8 {
        return try self.suffix.toBytes();
    }

    /// Returns the UUID string representation
    pub fn toUUID(self: Self, buf: *[36]u8) ![]const u8 {
        const bytes = try self.toUUIDBytes();
        return uuid.toString(std.mem.readInt(u128, &bytes, .big), buf);
    }

    /// Returns true if this is a zero/empty TypeID
    pub fn isZero(self: Self) bool {
        return std.mem.eql(u8, &self.suffix.value, &zero_suffix.value);
    }

    /// Returns a zero TypeID with the given prefix
    pub fn zero(prefix: []const u8) !Self {
        try validatePrefix(prefix);
        return Self{
            .prefix = prefix,
            .suffix = zero_suffix,
        };
    }

    /// Returns true if two TypeIDs are equal
    pub fn eql(self: Self, other: Self) bool {
        return std.mem.eql(u8, self.prefix, other.prefix) and
            std.mem.eql(u8, &self.suffix.value, &other.suffix.value);
    }

    /// Provides debug formatting for TypeID
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        if (self.prefix.len > 0) {
            try writer.print("{s}_{s}", .{ self.prefix, self.suffix.value });
        } else {
            try writer.writeAll(&self.suffix.value);
        }
    }
};

/// Builder pattern for creating TypeIDs with optional configuration
pub const TypeIDBuilder = struct {
    prefix: ?[]const u8 = null,

    pub fn init() TypeIDBuilder {
        return .{};
    }

    pub fn setPrefix(self: *TypeIDBuilder, prefix: []const u8) *TypeIDBuilder {
        self.prefix = prefix;
        return self;
    }

    pub fn build(self: TypeIDBuilder) !TypeID {
        const prefix = self.prefix orelse "";
        return TypeID.init(prefix);
    }
};

/// Validates a TypeID prefix according to the spec
fn validatePrefix(prefix: []const u8) !void {
    if (prefix.len > 63) {
        return Error.InvalidPrefixLength;
    }

    if (prefix.len == 0) {
        return;
    }

    if (prefix[0] == '_') {
        return Error.InvalidPrefixStart;
    }
    if (prefix[prefix.len - 1] == '_') {
        return Error.InvalidPrefixEnd;
    }

    // Validate characters
    for (prefix) |c| {
        if (!std.ascii.isLower(c) and c != '_') {
            return Error.InvalidPrefixChars;
        }
    }
}

/// Validates a TypeID suffix according to the spec
fn validateSuffix(suffix: []const u8) !void {
    if (suffix.len == 0) {
        return Error.EmptySuffix;
    }

    if (suffix.len != 26) {
        return Error.InvalidSuffixLength;
    }

    // First char must be 0-7 to avoid overflows
    if (suffix[0] > '7') {
        return Error.InvalidSuffixOverflow;
    }

    // Validate characters are valid base32
    if (base32.decode(suffix)) |_| {
        // Valid base32
        return;
    } else |_| {
        return Error.InvalidSuffixChars;
    }
}

test "valid type-ids" {
    const Case = struct {
        name: []const u8,
        typeid: []const u8,
        prefix: []const u8,
        uuid: []const u8,
    };

    const cases = [_]Case{
        .{ .name = "nil", .typeid = "00000000000000000000000000", .prefix = "", .uuid = "00000000-0000-0000-0000-000000000000" },
        .{ .name = "one", .typeid = "00000000000000000000000001", .prefix = "", .uuid = "00000000-0000-0000-0000-000000000001" },
        .{ .name = "ten", .typeid = "0000000000000000000000000a", .prefix = "", .uuid = "00000000-0000-0000-0000-00000000000a" },
        .{ .name = "sixteen", .typeid = "0000000000000000000000000g", .prefix = "", .uuid = "00000000-0000-0000-0000-000000000010" },
        .{ .name = "thirty-two", .typeid = "00000000000000000000000010", .prefix = "", .uuid = "00000000-0000-0000-0000-000000000020" },
        .{ .name = "max-valid", .typeid = "7zzzzzzzzzzzzzzzzzzzzzzzzz", .prefix = "", .uuid = "ffffffff-ffff-ffff-ffff-ffffffffffff" },
        .{ .name = "valid-alphabet", .typeid = "prefix_0123456789abcdefghjkmnpqrs", .prefix = "prefix", .uuid = "0110c853-1d09-52d8-d73e-1194e95b5f19" },
        .{ .name = "valid-uuidv7", .typeid = "prefix_01h455vb4pex5vsknk084sn02q", .prefix = "prefix", .uuid = "01890a5d-ac96-774b-bcce-b302099a8057" },
        .{ .name = "prefix-underscore", .typeid = "pre_fix_00000000000000000000000000", .prefix = "pre_fix", .uuid = "00000000-0000-0000-0000-000000000000" },
    };

    for (cases) |case| {
        const tid = try TypeID.fromString(case.typeid);

        var uuid_buf: [36]u8 = undefined;
        const tid_uuid = try tid.toUUID(&uuid_buf);

        var str_buf: [90]u8 = undefined; // Max size: 63 (prefix) + 1 (separator) + 26 (suffix)
        const tid_str = try tid.toString(&str_buf);

        try testing.expectEqualStrings(case.prefix, tid.prefix);
        try testing.expectEqualStrings(case.typeid, tid_str);
        try testing.expectEqualStrings(case.uuid, tid_uuid);
    }
}

test "invalid type-ids" {
    const Case = struct {
        name: []const u8,
        typeid: []const u8,
        description: []const u8,
    };

    const cases = [_]Case{
        .{ .name = "prefix-uppercase", .typeid = "PREFIX_00000000000000000000000000", .description = "The prefix should be lowercase with no uppercase letters" },
        .{ .name = "prefix-numeric", .typeid = "12345_00000000000000000000000000", .description = "The prefix can't have numbers, it needs to be alphabetic" },
        .{ .name = "prefix-period", .typeid = "pre.fix_00000000000000000000000000", .description = "The prefix can't have symbols, it needs to be alphabetic" },
        .{ .name = "prefix-non-ascii", .typeid = "préfix_00000000000000000000000000", .description = "The prefix can only have ascii letters" },
        .{ .name = "prefix-spaces", .typeid = "  prefix_00000000000000000000000000", .description = "The prefix can't have any spaces" },
        .{ .name = "prefix-64-chars", .typeid = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl_00000000000000000000000000", .description = "The prefix can't be 64 characters, it needs to be 63 characters or less" },
        .{ .name = "separator-empty-prefix", .typeid = "_00000000000000000000000000", .description = "If the prefix is empty, the separator should not be there" },
        .{ .name = "separator-empty", .typeid = "_", .description = "A separator by itself should not be treated as the empty string" },
        .{ .name = "suffix-short", .typeid = "prefix_1234567890123456789012345", .description = "The suffix can't be 25 characters, it needs to be exactly 26 characters" },
        .{ .name = "suffix-long", .typeid = "prefix_123456789012345678901234567", .description = "The suffix can't be 27 characters, it needs to be exactly 26 characters" },
        .{ .name = "suffix-spaces", .typeid = "prefix_1234567890123456789012345 ", .description = "The suffix can't have any spaces" },
        .{ .name = "suffix-uppercase", .typeid = "prefix_0123456789ABCDEFGHJKMNPQRS", .description = "The suffix should be lowercase with no uppercase letters" },
        .{ .name = "suffix-hyphens", .typeid = "prefix_123456789-123456789-123456", .description = "The suffix can't have any hyphens" },
        .{ .name = "suffix-wrong-alphabet", .typeid = "prefix_ooooooiiiiiiuuuuuuulllllll", .description = "The suffix should only have letters from the spec's alphabet" },
        .{ .name = "suffix-ambiguous-crockford", .typeid = "prefix_i23456789ol23456789oi23456", .description = "The suffix should not have any ambiguous characters from the crockford encoding" },
        .{ .name = "suffix-hyphens-crockford", .typeid = "prefix_123456789-0123456789-0123456", .description = "The suffix can't ignore hyphens as in the crockford encoding" },
        .{ .name = "suffix-overflow", .typeid = "prefix_8zzzzzzzzzzzzzzzzzzzzzzzzz", .description = "The suffix should encode at most 128-bits" },
        .{ .name = "prefix-underscore-start", .typeid = "_prefix_00000000000000000000000000", .description = "The prefix can't start with an underscore" },
        .{ .name = "prefix-underscore-end", .typeid = "prefix__00000000000000000000000000", .description = "The prefix can't end with an underscore" },
    };

    for (cases) |case| {
        const result = TypeID.fromString(case.typeid);
        _ = result catch continue;

        return error.TestUnexpectedSuccess;
    }
}

test "Buffer too small" {
    const tid = try TypeID.fromString("prefix_00000000000000000000000000");

    // Test string buffer too small
    var small_buf: [10]u8 = undefined;
    try testing.expectError(error.BufferTooSmall, tid.toString(&small_buf));

    // Test with exact size buffer
    var exact_buf: [33]u8 = undefined; // prefix(6) + separator(1) + suffix(26)
    _ = try tid.toString(&exact_buf);
}

test "Builder pattern" {
    // Test empty builder
    var builder = TypeIDBuilder.init();
    const id1 = try builder.build();
    try testing.expect(id1.prefix.len == 0);

    // Test with prefix
    builder = TypeIDBuilder.init();
    const id2 = try builder.setPrefix("test").build();
    try testing.expectEqualStrings("test", id2.prefix);
}

test "Formatting" {
    const tid = try TypeID.fromString("prefix_00000000000000000000000000");
    var buf: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.fmt.format(fbs.writer(), "TypeID: {s}", .{tid});
    try testing.expectEqualStrings("TypeID: prefix_00000000000000000000000000", fbs.getWritten());
}
