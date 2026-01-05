//! Benchmark to measure global mutex contention in UUID generation
//! 
//! This benchmark demonstrates the performance impact of the global mutex
//! in uuid.zig by comparing single-threaded vs multi-threaded generation.

const std = @import("std");
const uuid = @import("uuid/uuid.zig");

const num_iterations = 100_000;
const num_threads = 8;

fn singleThreadedBenchmark() !void {
    var gen = uuid.initSecure();
    
    const start = std.time.nanoTimestamp();
    
    for (0..num_iterations) |_| {
        _ = try gen.next();
    }
    
    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divFloor(end - start, std.time.ns_per_ms);
    const ops_per_sec = (num_iterations * std.time.ns_per_s) / @as(u64, @intCast(end - start));
    
    std.debug.print("Single-threaded: {} UUIDs in {}ms ({} ops/sec)\n", .{
        num_iterations,
        elapsed_ms,
        ops_per_sec,
    });
}

const ThreadContext = struct {
    thread_id: usize,
    count: usize,
    duration_ns: i128,
};

fn workerThread(ctx: *ThreadContext) !void {
    var gen = uuid.initSecure();
    
    const start = std.time.nanoTimestamp();
    
    for (0..ctx.count) |_| {
        _ = try gen.next();
    }
    
    const end = std.time.nanoTimestamp();
    ctx.duration_ns = end - start;
}

fn multiThreadedBenchmark() !void {
    const allocator = std.heap.page_allocator;
    
    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;
    
    const per_thread = num_iterations / num_threads;
    
    const total_start = std.time.nanoTimestamp();
    
    // Spawn threads
    for (0..num_threads) |i| {
        contexts[i] = .{
            .thread_id = i,
            .count = per_thread,
            .duration_ns = 0,
        };
        threads[i] = try std.Thread.spawn(.{}, workerThread, .{&contexts[i]});
    }
    
    // Wait for all threads
    for (0..num_threads) |i| {
        threads[i].join();
    }
    
    const total_end = std.time.nanoTimestamp();
    const total_elapsed = total_end - total_start;
    const total_elapsed_ms = @divFloor(total_elapsed, std.time.ns_per_ms);
    const total_ops_per_sec = (num_iterations * std.time.ns_per_s) / @as(u64, @intCast(total_elapsed));
    
    std.debug.print("\nMulti-threaded ({} threads): {} UUIDs in {}ms ({} ops/sec)\n", .{
        num_threads,
        num_iterations,
        total_elapsed_ms,
        total_ops_per_sec,
    });
    
    // Show per-thread stats
    std.debug.print("Per-thread breakdown:\n", .{});
    for (contexts, 0..) |ctx, i| {
        const thread_ms = @divFloor(ctx.duration_ns, std.time.ns_per_ms);
        const thread_ops_per_sec = (ctx.count * std.time.ns_per_s) / @as(u64, @intCast(ctx.duration_ns));
        std.debug.print("  Thread {}: {}ms ({} ops/sec)\n", .{
            i,
            thread_ms,
            thread_ops_per_sec,
        });
    }
    
    _ = allocator;
}

pub fn main() !void {
    std.debug.print("=== UUID Generation Mutex Contention Benchmark ===\n\n", .{});
    std.debug.print("Generating {} UUIDs...\n\n", .{num_iterations});
    
    try singleThreadedBenchmark();
    try multiThreadedBenchmark();
    
    std.debug.print("\n=== Analysis ===\n", .{});
    std.debug.print("If multi-threaded performance is significantly worse than\n", .{});
    std.debug.print("single-threaded * num_threads, the global mutex is causing contention.\n", .{});
}
