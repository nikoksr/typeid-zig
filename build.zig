const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("typeid", .{ .root_source_file = b.path("src/typeid.zig") });

    const test_step = b.step("test", "Run library tests");
    const tests = b.addTest(.{
        .root_source_file = b.path("src/typeid.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    // Benchmark for UUID generation (demonstrates per-generator mutex performance)
    const bench_uuid = b.addExecutable(.{
        .name = "bench_uuid_contention",
        .root_source_file = b.path("src/bench_uuid_contention.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bench_uuid_step = b.step("bench-uuid", "Run UUID generation benchmark");
    const run_bench_uuid = b.addRunArtifact(bench_uuid);
    bench_uuid_step.dependOn(&run_bench_uuid.step);
}
