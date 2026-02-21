const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Public module — importable as @import("zfp") by dependents
    const zfp_mod = b.addModule("zfp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zfp",
        .root_module = zfp_mod,
    });
    b.installArtifact(lib);

    // Tests
    const option_mod = b.createModule(.{
        .root_source_file = b.path("src/option.zig"),
        .target = target,
        .optimize = optimize,
    });
    const option_tests = b.addTest(.{
        .root_module = option_mod,
    });
    const run_option_tests = b.addRunArtifact(option_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_option_tests.step);
}
