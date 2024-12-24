//! This module provides an implementation of base32 encoding and decoding. The implementation's
//! intended purpose is to be used in the generation of TypeIDs for: https://github.com/nikoksr/typeid-zig
//!
//! The alogrithms are based on the Go implementation of ULID found at: https://github.com/oklog/ulid
//!
//! The code in this repo largely has been ported from the typeid-go implementation by jetify. The original
//! code can be found at: https://github.com/jetify-com/typeid-go/tree/main/base32
//!
//! Example:
//! ```zig
//! // Encoding 16 bytes to base32
//! var data = [_]u8{0} ** 16;
//! const encoded = base32.encode(data);
//! // encoded = "00000000000000000000000000"
//!
//! // Decoding back to bytes
//! const decoded = try base32.decode(&encoded);
//! // decoded = [_]u8{0} ** 16
//! ```

const std = @import("std");

/// The custom base32 alphabet used for encoding
const alphabet = "0123456789abcdefghjkmnpqrstvwxyz";

/// Lookup table for decoding. 0xFF represents invalid characters.
const dec = blk: {
    var table: [256]u8 = [_]u8{0xFF} ** 256;
    for (alphabet, 0..) |c, i| {
        table[c] = @truncate(i);
    }
    break :blk table;
};

/// Encodes exactly 16 bytes into a 26-character base32 string.
/// The input must be exactly 16 bytes.
pub fn encode(src: [16]u8) [26]u8 {
    var dst: [26]u8 = undefined;

    // Optimized unrolled encoding loop, following same bit manipulation as Go version
    dst[0] = alphabet[(src[0] & 0b11100000) >> 5];
    dst[1] = alphabet[src[0] & 0b00011111];
    dst[2] = alphabet[(src[1] & 0b11111000) >> 3];
    dst[3] = alphabet[((src[1] & 0b00000111) << 2) | ((src[2] & 0b11000000) >> 6)];
    dst[4] = alphabet[(src[2] & 0b00111110) >> 1];
    dst[5] = alphabet[((src[2] & 0b00000001) << 4) | ((src[3] & 0b11110000) >> 4)];
    dst[6] = alphabet[((src[3] & 0b00001111) << 1) | ((src[4] & 0b10000000) >> 7)];
    dst[7] = alphabet[(src[4] & 0b01111100) >> 2];
    dst[8] = alphabet[((src[4] & 0b00000011) << 3) | ((src[5] & 0b11100000) >> 5)];
    dst[9] = alphabet[src[5] & 0b00011111];

    dst[10] = alphabet[(src[6] & 0b11111000) >> 3];
    dst[11] = alphabet[((src[6] & 0b00000111) << 2) | ((src[7] & 0b11000000) >> 6)];
    dst[12] = alphabet[(src[7] & 0b00111110) >> 1];
    dst[13] = alphabet[((src[7] & 0b00000001) << 4) | ((src[8] & 0b11110000) >> 4)];
    dst[14] = alphabet[((src[8] & 0b00001111) << 1) | ((src[9] & 0b10000000) >> 7)];
    dst[15] = alphabet[(src[9] & 0b01111100) >> 2];
    dst[16] = alphabet[((src[9] & 0b00000011) << 3) | ((src[10] & 0b11100000) >> 5)];
    dst[17] = alphabet[src[10] & 0b00011111];
    dst[18] = alphabet[(src[11] & 0b11111000) >> 3];
    dst[19] = alphabet[((src[11] & 0b00000111) << 2) | ((src[12] & 0b11000000) >> 6)];
    dst[20] = alphabet[(src[12] & 0b00111110) >> 1];
    dst[21] = alphabet[((src[12] & 0b00000001) << 4) | ((src[13] & 0b11110000) >> 4)];
    dst[22] = alphabet[((src[13] & 0b00001111) << 1) | ((src[14] & 0b10000000) >> 7)];
    dst[23] = alphabet[(src[14] & 0b01111100) >> 2];
    dst[24] = alphabet[((src[14] & 0b00000011) << 3) | ((src[15] & 0b11100000) >> 5)];
    dst[25] = alphabet[src[15] & 0b00011111];

    return dst;
}

/// Custom error type for decode operations
pub const DecodeError = error{
    /// Input string length was not exactly 26 characters
    InvalidLength,
    /// Input contained an invalid base32 character
    InvalidCharacter,
};

/// Decodes a 26-character base32 string back into 16 bytes.
/// Returns DecodeError if the input is invalid.
pub fn decode(encoded: []const u8) DecodeError![16]u8 {
    if (encoded.len != 26) return DecodeError.InvalidLength;

    // Check all characters are valid
    for (encoded) |c| {
        if (dec[c] == 0xFF) return DecodeError.InvalidCharacter;
    }

    var id: [16]u8 = undefined;

    // Unrolled decoding loop, following same bit manipulation as Go version
    id[0] = (dec[encoded[0]] << 5) | dec[encoded[1]];
    id[1] = (dec[encoded[2]] << 3) | (dec[encoded[3]] >> 2);
    id[2] = (dec[encoded[3]] << 6) | (dec[encoded[4]] << 1) | (dec[encoded[5]] >> 4);
    id[3] = (dec[encoded[5]] << 4) | (dec[encoded[6]] >> 1);
    id[4] = (dec[encoded[6]] << 7) | (dec[encoded[7]] << 2) | (dec[encoded[8]] >> 3);
    id[5] = (dec[encoded[8]] << 5) | dec[encoded[9]];

    id[6] = (dec[encoded[10]] << 3) | (dec[encoded[11]] >> 2);
    id[7] = (dec[encoded[11]] << 6) | (dec[encoded[12]] << 1) | (dec[encoded[13]] >> 4);
    id[8] = (dec[encoded[13]] << 4) | (dec[encoded[14]] >> 1);
    id[9] = (dec[encoded[14]] << 7) | (dec[encoded[15]] << 2) | (dec[encoded[16]] >> 3);
    id[10] = (dec[encoded[16]] << 5) | dec[encoded[17]];
    id[11] = (dec[encoded[18]] << 3) | (dec[encoded[19]] >> 2);
    id[12] = (dec[encoded[19]] << 6) | (dec[encoded[20]] << 1) | (dec[encoded[21]] >> 4);
    id[13] = (dec[encoded[21]] << 4) | (dec[encoded[22]] >> 1);
    id[14] = (dec[encoded[22]] << 7) | (dec[encoded[23]] << 2) | (dec[encoded[24]] >> 3);
    id[15] = (dec[encoded[24]] << 5) | dec[encoded[25]];

    return id;
}

test "random encode/decode" {
    const iterations = 1000;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // Generate 16 random bytes
        var data: [16]u8 = undefined;
        std.crypto.random.bytes(&data);

        // Encode them using our implementation
        const encoded = encode(data);

        // Decode and verify we get the same data back
        const decoded = try decode(&encoded);

        // std.debug.print("==================================================\n", .{});
        // std.debug.print("encoded:\t{any}\n", .{encoded});
        // std.debug.print("decoded:\t{any}\n", .{decoded});
        // std.debug.print("data:\t\t{any}\n", .{data});

        // Verify the roundtrip
        try std.testing.expectEqualSlices(u8, &data, &decoded);

        // Additional verification that encoded string only contains valid characters
        for (encoded) |c| {
            // Check character is in our alphabet
            var found = false;
            for (alphabet) |valid_char| {
                if (c == valid_char) {
                    found = true;
                    break;
                }
            }
            try std.testing.expect(found);
        }
    }
}

test "decode invalid length" {
    try std.testing.expectError(DecodeError.InvalidLength, decode("abc"));
}

test "decode invalid character" {
    const invalid = "0123456789abcdefghijklmno!"; // ! is invalid
    try std.testing.expectError(DecodeError.InvalidCharacter, decode(invalid));
}
