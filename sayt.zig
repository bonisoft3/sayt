const std = @import("std");
const builtin = @import("builtin");

const MISE_VERSION = "v2025.11.11";
const MISE_URL_BASE = "https://github.com/jdx/mise/releases/download/" ++ MISE_VERSION ++ "/mise-" ++ MISE_VERSION ++ "-";

const help_text =
    \\Usage:
    \\  > sayt {flags} ...(rest)
    \\
    \\Subcommands:
    \\  sayt build (custom) - Runs the configured build task via vscode-task-runner
    \\  sayt doctor (custom) - Runs environment diagnostics for required tooling
    \\  sayt generate (custom) - Generates files according to SAY config rules
    \\  sayt help (custom) - Shows help information for subcommands
    \\  sayt integrate (custom) - Runs the integrate docker compose workflow
    \\  sayt launch (custom) - Launches the develop docker compose stack
    \\  sayt lint (custom) - Runs lint rules from the SAY configuration
    \\  sayt release (custom) - Builds release artifacts using the release task
    \\  sayt setup (custom) - Installs runtimes and tools for the project
    \\  sayt test (custom) - Runs the configured test task via vscode-task-runner
    \\  sayt verify (custom) - Verifies release artifacts using the same release flow
    \\
    \\Flags:
    \\  -h, --help: show this help message
    \\  -d, --directory <string>: directory where to run the command (default: '.')
    \\
    \\Parameters:
    \\  ...rest <any>
    \\
;

fn getEnvVar(alloc: std.mem.Allocator, key: []const u8) ?[]const u8 {
    return std.process.getEnvVarOwned(alloc, key) catch null;
}

fn getCacheDir(alloc: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .windows) {
        if (getEnvVar(alloc, "LOCALAPPDATA")) |v| {
            defer alloc.free(v);
            return std.fs.path.join(alloc, &.{ v, "sayt" });
        }
        return alloc.dupe(u8, "C:\\Temp\\sayt");
    }
    if (builtin.os.tag == .macos) {
        if (getEnvVar(alloc, "HOME")) |v| {
            defer alloc.free(v);
            return std.fs.path.join(alloc, &.{ v, "Library", "Caches", "sayt" });
        }
        return alloc.dupe(u8, "/tmp/sayt");
    }
    if (getEnvVar(alloc, "XDG_CACHE_HOME")) |v| {
        defer alloc.free(v);
        return std.fs.path.join(alloc, &.{ v, "sayt" });
    }
    if (getEnvVar(alloc, "HOME")) |v| {
        defer alloc.free(v);
        return std.fs.path.join(alloc, &.{ v, ".cache", "sayt" });
    }
    return alloc.dupe(u8, "/tmp/sayt");
}

fn getMiseUrl(alloc: std.mem.Allocator) ![]const u8 {
    const os = switch (builtin.os.tag) {
        .windows => "windows",
        .macos => "macos",
        else => "linux",
    };
    const arch = switch (builtin.cpu.arch) {
        .aarch64 => "arm64",
        .arm => "armv7",
        else => "x64",
    };
    const suffix: []const u8 = if (builtin.os.tag == .linux) "-musl" else "";
    return std.fmt.allocPrint(alloc, MISE_URL_BASE ++ "{s}-{s}{s}", .{ os, arch, suffix });
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn downloadFile(alloc: std.mem.Allocator, url: []const u8, dest: []const u8) !void {
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    var buf: [8192]u8 = undefined;
    var req = try client.open(.GET, try std.Uri.parse(url), .{ .server_header_buffer = &buf });
    defer req.deinit();

    try req.send();
    try req.wait();

    if (req.response.status != .ok) return error.HttpError;

    const body = try req.reader().readAllAlloc(alloc, 50 * 1024 * 1024);
    defer alloc.free(body);

    const file = try std.fs.cwd().createFile(dest, .{});
    defer file.close();
    try file.writeAll(body);
    if (builtin.os.tag != .windows) try file.chmod(0o755);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    for (args) |a| {
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            try std.io.getStdOut().writeAll(help_text);
            return;
        }
    }

    const cache = try getCacheDir(alloc);
    defer alloc.free(cache);

    const mise_dir = try std.fs.path.join(alloc, &.{ cache, "mise-" ++ MISE_VERSION });
    defer alloc.free(mise_dir);
    std.fs.cwd().makePath(mise_dir) catch {};

    const mise_bin = try std.fs.path.join(alloc, &.{ mise_dir, if (builtin.os.tag == .windows) "mise.exe" else "mise" });
    defer alloc.free(mise_bin);

    if (!fileExists(mise_bin)) {
        const url = try getMiseUrl(alloc);
        defer alloc.free(url);
        try downloadFile(alloc, url, mise_bin);
    }

    // Check for installed sayt
    var exe_buf: [4096]u8 = undefined;
    const exe_path = std.fs.selfExePath(&exe_buf) catch "";
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";
    const install_dir = try std.fs.path.join(alloc, &.{ exe_dir, ".." });
    defer alloc.free(install_dir);

    const version_file = try std.fs.path.join(alloc, &.{ install_dir, ".version" });
    defer alloc.free(version_file);

    var child_args = std.ArrayList([]const u8).init(alloc);
    defer child_args.deinit();
    try child_args.append(mise_bin);

    if (fileExists(version_file)) {
        const nu_toml = try std.fs.path.join(alloc, &.{ install_dir, "nu.toml" });
        const sayt_nu = try std.fs.path.join(alloc, &.{ install_dir, "sayt.nu" });
        try child_args.appendSlice(&.{ "tool-stub", nu_toml, sayt_nu });
    } else {
        const ver = getEnvVar(alloc, "SAYT_VERSION") orelse "latest";
        const sayt_ver = try std.fmt.allocPrint(alloc, "github:igorgatis/sayt@{s}", .{ver});
        const bin = if (builtin.os.tag == .linux)
            (if (builtin.cpu.arch == .x86_64) "sayt-amd64.elf" else "sayt-arm64.elf")
        else
            "sayt.com";
        try child_args.appendSlice(&.{ "exec", sayt_ver, "--", bin });
    }

    for (args[1..]) |a| try child_args.append(a);

    var child = std.process.Child.init(child_args.items, alloc);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    _ = try child.spawnAndWait();
}
