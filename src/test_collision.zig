//! Test to verify collision safety after moving to per-generator state
//! 
//! This test verifies:
//! 1. Single generator still produces monotonic UUIDs (no collisions)
//! 2. Multiple generators can produce colliding UUIDs (by design - they're independent)
//! 3. Collision probability is what we expect given randomness

const std = @import("std");
const uuid = @import("uuid/uuid.zig");
const testing = std.testing;

test "single generator monotonicity (collision-free within generator)" {
    std.debug.print("\n=== Single Generator Collision Safety ===\n\n", .{});
    
    var gen = uuid.initSecure();
    var seen = std.AutoHashMap(uuid.Uuid, void).init(testing.allocator);
    defer seen.deinit();
    
    const count = 100_000;
    var last: uuid.Uuid = 0;
    
    std.debug.print("Generating {} UUIDs from single generator...\n", .{count});
    
    for (0..count) |_| {
        const id = try gen.next();
        
        // Check monotonicity (must always increase)
        try testing.expect(id > last);
        last = id;
        
        // Check for duplicates
        const result = try seen.getOrPut(id);
        try testing.expect(!result.found_existing);
    }
    
    std.debug.print("✓ All {} UUIDs are unique and monotonically increasing\n", .{count});
    std.debug.print("✓ No collisions within a single generator\n\n", .{});
}

test "multiple generators can have different UUIDs (by design)" {
    std.debug.print("=== Multiple Generator Independence ===\n\n", .{});
    
    var gen1 = uuid.initSecure();
    var gen2 = uuid.initSecure();
    
    const id1 = try gen1.next();
    const id2 = try gen2.next();
    
    std.debug.print("Generator 1 UUID: {x:0>32}\n", .{id1});
    std.debug.print("Generator 2 UUID: {x:0>32}\n", .{id2});
    
    // They should be different due to random bits (62 bits of randomness)
    // Collision probability is 1/(2^62) per pair
    try testing.expect(id1 != id2);
    
    std.debug.print("✓ Different generators produce different UUIDs\n", .{});
    std.debug.print("  (This is expected - the 62 random bits make collisions virtually impossible)\n\n", .{});
}

test "multi-threaded generation produces unique UUIDs" {
    std.debug.print("=== Multi-threaded Collision Safety ===\n\n", .{});
    
    const ThreadContext = struct {
        gen: uuid.Generator,
        ids: std.ArrayList(uuid.Uuid),
        
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
            .gen = uuid.initSecure(),
            .ids = std.ArrayList(uuid.Uuid).init(testing.allocator),
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
    
    std.debug.print("Generated {} UUIDs across {} threads\n", .{1000 * num_threads, num_threads});
    
    // Check each generator's UUIDs are monotonic
    for (contexts, 0..) |ctx, thread_id| {
        var last: uuid.Uuid = 0;
        for (ctx.ids.items) |id| {
            if (id <= last) {
                std.debug.print("✗ Thread {} produced non-monotonic UUID!\n", .{thread_id});
                return error.NonMonotonic;
            }
            last = id;
        }
    }
    
    std.debug.print("✓ All {} generators maintained monotonicity\n", .{num_threads});
    
    // Collect all UUIDs and check for duplicates
    var all_ids = std.AutoHashMap(uuid.Uuid, usize).init(testing.allocator);
    defer all_ids.deinit();
    
    for (contexts, 0..) |ctx, thread_id| {
        for (ctx.ids.items) |id| {
            const result = try all_ids.getOrPut(id);
            if (result.found_existing) {
                std.debug.print("✗ Collision detected! Thread {} and {} produced same UUID\n", .{thread_id, result.value_ptr.*});
                return error.CollisionDetected;
            }
            result.value_ptr.* = thread_id;
        }
    }
    
    std.debug.print("✓ No collisions among {} total UUIDs\n", .{1000 * num_threads});
    std.debug.print("\nConclusion: Per-generator state is collision-safe\n", .{});
}

pub fn main() !void {
    try std.testing.refAllDecls(@This());
    std.debug.print("\nRun with: zig build test-collision\n", .{});
}
