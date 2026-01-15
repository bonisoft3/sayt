const std = @import("std");
const builtin = @import("builtin");

const ArchiveKind = enum {
    tar_gz,
    zip,
};

const Target = struct {
    name: []const u8,
    bin_name: []const u8,
    exec_name: []const u8,
    archive: ArchiveKind,
    target_query: std.Target.Query,
};

const ReleaseStep = struct {
    step: std.Build.Step,
    b: *std.Build,
    release_version: []const u8,
    targets: []const Target,

    pub fn create(
        b: *std.Build,
        release_version: []const u8,
        all_step: *std.Build.Step,
        targets: []const Target,
    ) *ReleaseStep {
        const self = b.allocator.create(ReleaseStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "release-assets",
                .owner = b,
                .makeFn = make,
            }),
            .b = b,
            .release_version = b.dupe(release_version),
            .targets = targets,
        };
        self.step.dependOn(all_step);
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const self: *ReleaseStep = @fieldParentPtr("step", step);

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const root_path = self.b.pathFromRoot(".");
        var root_dir = try std.fs.openDirAbsolute(root_path, .{ .iterate = true });
        defer root_dir.close();

        const release_rel = "zig-out/release";
        const bin_rel = "zig-out/bin";
        const dist_rel = try std.fs.path.join(allocator, &.{ release_rel, self.release_version });
        const work_rel = try std.fs.path.join(allocator, &.{ release_rel, ".work" });
        const dist_abs = try std.fs.path.join(allocator, &.{ root_path, dist_rel });

        try deleteTreeIfExists(&root_dir, work_rel);
        try root_dir.makePath(dist_rel);
        try root_dir.makePath(work_rel);

        const core_files = [_][]const u8{
            "sayt.nu",
            "tools.nu",
            "dind.nu",
            "config.cue",
            "nu.toml",
            "nu.musl.toml",
            "docker.toml",
            "docker.musl.toml",
            "uvx.toml",
            "uvx.musl.toml",
            "cue.toml",
            "cue.musl.toml",
            ".mise.toml",
        };

        for (self.targets) |target| {
            const bin_src_rel = try std.fs.path.join(allocator, &.{ bin_rel, target.bin_name });
            const bin_dist_rel = try std.fs.path.join(allocator, &.{ dist_rel, target.bin_name });
            try root_dir.copyFile(bin_src_rel, root_dir, bin_dist_rel, .{});

            const dir_rel = try std.fs.path.join(allocator, &.{ work_rel, target.name });
            try deleteTreeIfExists(&root_dir, dir_rel);
            try root_dir.makePath(dir_rel);

            for (core_files) |file_name| {
                const dest_rel = try std.fs.path.join(allocator, &.{ dir_rel, file_name });
                try root_dir.copyFile(file_name, root_dir, dest_rel, .{});
            }

            const bin_exec_rel = try std.fs.path.join(allocator, &.{ dir_rel, target.exec_name });
            try root_dir.copyFile(bin_src_rel, root_dir, bin_exec_rel, .{});
            if (target.archive == .tar_gz and builtin.os.tag != .windows) {
                try setExecutable(&root_dir, bin_exec_rel);
            }

            const dir_abs = try std.fs.path.join(allocator, &.{ root_path, dir_rel });
            switch (target.archive) {
                .tar_gz => {
                    const tar_name = try std.fmt.allocPrint(allocator, "{s}.tar", .{target.name});
                    const tgz_name = try std.fmt.allocPrint(allocator, "{s}.tar.gz", .{target.name});
                    const tar_abs = try std.fs.path.join(allocator, &.{ dist_abs, tar_name });
                    const tgz_abs = try std.fs.path.join(allocator, &.{ dist_abs, tgz_name });
                    try createTarGz(step, allocator, dir_abs, tar_abs, tgz_abs);
                },
                .zip => {
                    const zip_name = try std.fmt.allocPrint(allocator, "{s}.zip", .{target.name});
                    const zip_abs = try std.fs.path.join(allocator, &.{ dist_abs, zip_name });
                    try createZip(step, allocator, dir_abs, zip_abs);
                },
            }
        }

        try deleteTreeIfExists(&root_dir, work_rel);
    }

    fn deleteTreeIfExists(dir: *std.fs.Dir, path: []const u8) !void {
        try dir.deleteTree(path);
    }

    fn deleteFileIfExists(path: []const u8) !void {
        std.fs.deleteFileAbsolute(path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }

    fn setExecutable(dir: *std.fs.Dir, path: []const u8) !void {
        var file = try dir.openFile(path, .{});
        defer file.close();
        try file.chmod(0o755);
    }

    fn createTarGz(
        step: *std.Build.Step,
        allocator: std.mem.Allocator,
        dir_abs: []const u8,
        tar_abs: []const u8,
        tgz_abs: []const u8,
    ) !void {
        try deleteFileIfExists(tar_abs);
        try deleteFileIfExists(tgz_abs);
        try runCommand(step, allocator, &.{ "7zz", "a", "-ttar", tar_abs, "." }, dir_abs);
        try runCommand(step, allocator, &.{ "7zz", "a", "-tgzip", tgz_abs, tar_abs }, null);
        try deleteFileIfExists(tar_abs);
    }

    fn createZip(
        step: *std.Build.Step,
        allocator: std.mem.Allocator,
        dir_abs: []const u8,
        zip_abs: []const u8,
    ) !void {
        try deleteFileIfExists(zip_abs);
        try runCommand(step, allocator, &.{ "7zz", "a", "-tzip", zip_abs, "." }, dir_abs);
    }

    fn runCommand(
        step: *std.Build.Step,
        allocator: std.mem.Allocator,
        argv: []const []const u8,
        cwd: ?[]const u8,
    ) !void {
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = argv,
            .cwd = cwd,
            .max_output_bytes = 1024 * 1024,
        }) catch |err| {
            return step.fail("failed to run {s}: {s}", .{ argv[0], @errorName(err) });
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    if (result.stdout.len > 0) try step.addError("{s}", .{result.stdout});
                    if (result.stderr.len > 0) try step.addError("{s}", .{result.stderr});
                    return step.fail("command failed ({d}): {s}", .{ code, argv[0] });
                }
            },
            else => {
                if (result.stdout.len > 0) try step.addError("{s}", .{result.stdout});
                if (result.stderr.len > 0) try step.addError("{s}", .{result.stderr});
                return step.fail("command failed: {s}", .{ argv[0] });
            },
        }
    }
};

const release_targets = [_]Target{
    .{
        .name = "sayt-linux-x64",
        .bin_name = "sayt-linux-x64",
        .exec_name = "sayt",
        .archive = .tar_gz,
        .target_query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    },
    .{
        .name = "sayt-linux-arm64",
        .bin_name = "sayt-linux-arm64",
        .exec_name = "sayt",
        .archive = .tar_gz,
        .target_query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
    },
    .{
        .name = "sayt-linux-armv7",
        .bin_name = "sayt-linux-armv7",
        .exec_name = "sayt",
        .archive = .tar_gz,
        .target_query = .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .musleabihf },
    },
    .{
        .name = "sayt-macos-x64",
        .bin_name = "sayt-macos-x64",
        .exec_name = "sayt",
        .archive = .tar_gz,
        .target_query = .{ .cpu_arch = .x86_64, .os_tag = .macos },
    },
    .{
        .name = "sayt-macos-arm64",
        .bin_name = "sayt-macos-arm64",
        .exec_name = "sayt",
        .archive = .tar_gz,
        .target_query = .{ .cpu_arch = .aarch64, .os_tag = .macos },
    },
    .{
        .name = "sayt-windows-x64",
        .bin_name = "sayt-windows-x64.exe",
        .exec_name = "sayt.exe",
        .archive = .zip,
        .target_query = .{ .cpu_arch = .x86_64, .os_tag = .windows },
    },
    .{
        .name = "sayt-windows-arm64",
        .bin_name = "sayt-windows-arm64.exe",
        .exec_name = "sayt.exe",
        .archive = .zip,
        .target_query = .{ .cpu_arch = .aarch64, .os_tag = .windows },
    },
};

pub fn build(b: *std.Build) void {
    // Native build for development/testing
    const native_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const native_module = b.createModule(.{
        .root_source_file = b.path("sayt.zig"),
        .target = native_target,
        .optimize = optimize,
        .link_libc = false,
    });
    const exe = b.addExecutable(.{
        .name = "sayt",
        .root_module = native_module,
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

    for (release_targets) |target| {
        const cross_module = b.createModule(.{
            .root_source_file = b.path("sayt.zig"),
            .target = b.resolveTargetQuery(target.target_query),
            .optimize = .ReleaseSmall,
            .link_libc = false,
            .strip = true,
        });
        const cross_exe = b.addExecutable(.{
            .name = target.name,
            .root_module = cross_module,
        });

        const install_step = b.addInstallArtifact(cross_exe, .{});
        all_step.dependOn(&install_step.step);
    }

    // Test step
    const test_module = b.createModule(.{
        .root_source_file = b.path("sayt.zig"),
        .target = native_target,
        .optimize = optimize,
        .link_libc = false,
    });
    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const release_version = b.option([]const u8, "release-version", "Release version tag (vX.Y.Z)") orelse "v0.0.0";
    const release_task = ReleaseStep.create(b, release_version, all_step, release_targets[0..]);
    const release_step = b.step("release", "Build release assets");
    release_step.dependOn(&release_task.step);
}
