const std = @import("std");

pub fn build(b: *std.Build) void {
    // Define all target platforms
    const targets: []const struct {
        target: std.Target.Query,
        name: []const u8,
    } = &.{
        .{ .target = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl }, .name = "sayt-linux-x64" },
        .{ .target = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl }, .name = "sayt-linux-arm64" },
        .{ .target = .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .musleabihf }, .name = "sayt-linux-armv7" },
        .{ .target = .{ .cpu_arch = .x86_64, .os_tag = .macos }, .name = "sayt-macos-x64" },
        .{ .target = .{ .cpu_arch = .aarch64, .os_tag = .macos }, .name = "sayt-macos-arm64" },
        .{ .target = .{ .cpu_arch = .x86_64, .os_tag = .windows }, .name = "sayt-windows-x64" },
        .{ .target = .{ .cpu_arch = .aarch64, .os_tag = .windows }, .name = "sayt-windows-arm64" },
    };

    // Native build for development/testing
    const native_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "sayt",
        .root_source_file = b.path("sayt.zig"),
        .target = native_target,
        .optimize = optimize,
        .link_libc = false,
    });
    b.installArtifact(exe);

    // Run step for development
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the sayt binary");
    run_step.dependOn(&run_cmd.step);

    // Cross-compilation step for all platforms
    const all_step = b.step("all", "Build for all target platforms");

    for (targets) |t| {
        const cross_exe = b.addExecutable(.{
            .name = t.name,
            .root_source_file = b.path("sayt.zig"),
            .target = b.resolveTargetQuery(t.target),
            .optimize = .ReleaseSmall,
            .link_libc = false,
        });
        // For static linking
        cross_exe.root_module.strip = true;

        const install_step = b.addInstallArtifact(cross_exe, .{});
        all_step.dependOn(&install_step.step);
    }

    // Test step
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("sayt.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
