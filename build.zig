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

    const result_mod = b.createModule(.{
        .root_source_file = b.path("src/result.zig"),
        .target = target,
        .optimize = optimize,
    });
    const result_tests = b.addTest(.{
        .root_module = result_mod,
    });
    const run_result_tests = b.addRunArtifact(result_tests);

    const pipe_mod = b.createModule(.{
        .root_source_file = b.path("src/pipe.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pipe_tests = b.addTest(.{ .root_module = pipe_mod });
    const run_pipe_tests = b.addRunArtifact(pipe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_option_tests.step);
    test_step.dependOn(&run_result_tests.step);
    test_step.dependOn(&run_pipe_tests.step);

    // Docs
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate API documentation");
    docs_step.dependOn(&install_docs.step);
}
