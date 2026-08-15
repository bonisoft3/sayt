const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const DEFAULT_VERSION = if (@hasDecl(build_options, "version")) build_options.version else "v0.3.2";
const MISE_VERSION = "v2026.3.17";
const MISE_URL_BASE = "https://github.com/jdx/mise/releases/download/" ++ MISE_VERSION ++ "/mise-" ++ MISE_VERSION ++ "-";
const CA_CERTS_FILE = "ca-certificates.crt";
const EMBEDDED_CA_CERTS = @embedFile(CA_CERTS_FILE);


const EnvMap = std.process.Environ.Map;

fn getEnvVar(alloc: std.mem.Allocator, env: *const EnvMap, key: []const u8) ?[]const u8 {
    const value = env.get(key) orelse return null;
    return alloc.dupe(u8, value) catch null;
}

fn getCacheDir(alloc: std.mem.Allocator, env: *const EnvMap) ![]const u8 {
    if (builtin.os.tag == .windows) {
        if (getEnvVar(alloc, env, "LOCALAPPDATA")) |v| {
            defer alloc.free(v);
            return std.fs.path.join(alloc, &.{ v, "sayt" });
        }
        return alloc.dupe(u8, "C:\\Temp\\sayt");
    }
    if (builtin.os.tag == .macos) {
        if (getEnvVar(alloc, env, "HOME")) |v| {
            defer alloc.free(v);
            return std.fs.path.join(alloc, &.{ v, "Library", "Caches", "sayt" });
        }
        return alloc.dupe(u8, "/tmp/sayt");
    }
    if (getEnvVar(alloc, env, "XDG_CACHE_HOME")) |v| {
        defer alloc.free(v);
        return std.fs.path.join(alloc, &.{ v, "sayt" });
    }
    if (getEnvVar(alloc, env, "HOME")) |v| {
        defer alloc.free(v);
        return std.fs.path.join(alloc, &.{ v, ".cache", "sayt" });
    }
    return alloc.dupe(u8, "/tmp/sayt");
}

fn ensureCaBundle(alloc: std.mem.Allocator, io: std.Io, env: *const EnvMap, cache_dir: []const u8) !?[]const u8 {
    if (getEnvVar(alloc, env, "SAYT_CA_CERT")) |existing| {
        if (fileExists(io, existing)) return existing;
        alloc.free(existing);
    }
    if (getEnvVar(alloc, env, "SSL_CERT_FILE")) |existing| {
        if (fileExists(io, existing)) return existing;
        alloc.free(existing);
    }

    const cert_path = try std.fs.path.join(alloc, &.{ cache_dir, CA_CERTS_FILE });
    if (!fileExists(io, cert_path)) {
        std.Io.Dir.cwd().createDirPath(io, cache_dir) catch {};
        const file = try std.Io.Dir.cwd().createFile(io, cert_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, EMBEDDED_CA_CERTS);
    }
    return cert_path;
}

/// The slugs mise's release asset names are built from.
const Platform = struct {
    os: []const u8,
    arch: []const u8,
    /// Linux assets are the static musl builds.
    suffix: []const u8,
    ext: []const u8,
};

fn platformFor(os_tag: std.Target.Os.Tag, arch: std.Target.Cpu.Arch) Platform {
    return .{
        .os = switch (os_tag) {
            .windows => "windows",
            .macos => "macos",
            else => "linux",
        },
        .arch = switch (arch) {
            .aarch64 => "arm64",
            .arm => "armv7",
            else => "x64",
        },
        .suffix = if (os_tag == .linux) "-musl" else "",
        .ext = if (os_tag == .windows) ".zip" else "",
    };
}

fn miseUrlFrom(alloc: std.mem.Allocator, base_override: ?[]const u8, p: Platform) ![]const u8 {
    if (base_override) |base| {
        const trimmed = std.mem.trimEnd(u8, base, "/");
        return std.fmt.allocPrint(
            alloc,
            "{s}/mise-{s}-{s}-{s}{s}{s}",
            .{ trimmed, MISE_VERSION, p.os, p.arch, p.suffix, p.ext },
        );
    }
    return std.fmt.allocPrint(alloc, MISE_URL_BASE ++ "{s}-{s}{s}{s}", .{ p.os, p.arch, p.suffix, p.ext });
}

fn getMiseUrl(alloc: std.mem.Allocator, env: *const EnvMap) ![]const u8 {
    if (getEnvVar(alloc, env, "SAYT_MISE_URL")) |override| {
        return override;
    }
    const base = getEnvVar(alloc, env, "SAYT_MISE_BASE");
    defer if (base) |b| alloc.free(b);
    return miseUrlFrom(alloc, base, platformFor(builtin.os.tag, builtin.cpu.arch));
}

fn fileExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn isMuslRuntime(io: std.Io) bool {
    if (builtin.os.tag != .linux) return false;
    const glibc_loader = switch (builtin.cpu.arch) {
        .x86_64 => "/lib64/ld-linux-x86-64.so.2",
        .aarch64 => "/lib/ld-linux-aarch64.so.1",
        .arm => "/lib/ld-linux-armhf.so.3",
        else => return false,
    };
    return !fileExists(io, glibc_loader);
}

fn selectNuStub(alloc: std.mem.Allocator, io: std.Io, install_dir: []const u8) ![]const u8 {
    const default_stub = try std.fs.path.join(alloc, &.{ install_dir, "nu.toml" });
    if (!isMuslRuntime(io)) return default_stub;

    const musl_stub = try std.fs.path.join(alloc, &.{ install_dir, "nu.musl.toml" });
    if (fileExists(io, musl_stub)) {
        alloc.free(default_stub);
        return musl_stub;
    }
    alloc.free(musl_stub);
    return default_stub;
}

fn normalizeVersion(alloc: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.eql(u8, raw, "latest")) {
        return alloc.dupe(u8, raw);
    }
    if (raw.len > 0 and raw[0] != 'v') {
        return std.fmt.allocPrint(alloc, "v{s}", .{raw});
    }
    return alloc.dupe(u8, raw);
}

fn releaseUrlBaseFrom(alloc: std.mem.Allocator, base_override: ?[]const u8, version: []const u8) ![]const u8 {
    if (base_override) |override| {
        const trimmed = std.mem.trimEnd(u8, override, "/");
        return std.fmt.allocPrint(alloc, "{s}/", .{trimmed});
    }
    if (std.mem.eql(u8, version, "latest")) {
        return alloc.dupe(u8, "https://github.com/bonisoft3/sayt/releases/latest/download/");
    }
    return std.fmt.allocPrint(alloc, "https://github.com/bonisoft3/sayt/releases/download/{s}/", .{version});
}

fn releaseUrlBase(alloc: std.mem.Allocator, env: *const EnvMap, version: []const u8) ![]const u8 {
    const override = getEnvVar(alloc, env, "SAYT_RELEASE_BASE");
    defer if (override) |o| alloc.free(o);
    return releaseUrlBaseFrom(alloc, override, version);
}

fn fullDistStub(alloc: std.mem.Allocator, version: []const u8, url_base: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        alloc,
        \\version = "{s}"
        \\bin = "sayt"
        \\
        \\[platforms.linux-amd64]
        \\url = "{s}sayt-linux-x64.tar.gz"
        \\
        \\[platforms.linux-arm64]
        \\url = "{s}sayt-linux-arm64.tar.gz"
        \\
        \\[platforms.linux-armv7]
        \\url = "{s}sayt-linux-armv7.tar.gz"
        \\
        \\[platforms.darwin-amd64]
        \\url = "{s}sayt-macos-x64.tar.gz"
        \\
        \\[platforms.darwin-arm64]
        \\url = "{s}sayt-macos-arm64.tar.gz"
        \\
        \\[platforms.windows-amd64]
        \\url = "{s}sayt-windows-x64.zip"
        \\bin = "sayt.exe"
        \\
        \\[platforms.windows-arm64]
        \\url = "{s}sayt-windows-arm64.zip"
        \\bin = "sayt.exe"
        \\
    ,
        .{ version, url_base, url_base, url_base, url_base, url_base, url_base, url_base },
    );
}

fn writeFile(io: std.Io, path: []const u8, contents: []const u8) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, contents);
}

fn addCaBundleFromPath(
    bundle: *std.crypto.Certificate.Bundle,
    alloc: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !void {
    bundle.bytes.clearRetainingCapacity();
    bundle.map.clearRetainingCapacity();
    const now = std.Io.Clock.real.now(io);
    if (std.fs.path.isAbsolute(path)) {
        try bundle.addCertsFromFilePathAbsolute(alloc, io, now, path);
        return;
    }
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var file_reader = file.reader(io, &.{});
    try bundle.addCertsFromFile(alloc, &file_reader, now.toSeconds());
}

fn applyCaBundleOverride(
    client: *std.http.Client,
    alloc: std.mem.Allocator,
    io: std.Io,
    ca_path_override: ?[]const u8,
) !void {
    const ca_path = ca_path_override orelse return;
    std.debug.print("Using CA bundle: {s}\n", .{ca_path});
    try client.ca_bundle_lock.lock(io);
    defer client.ca_bundle_lock.unlock(io);
    try addCaBundleFromPath(&client.ca_bundle, alloc, io, ca_path);
    // A null `now` makes the next HTTPS request rescan system roots over the
    // bundle just installed; stamping it keeps the override in force.
    client.now = std.Io.Clock.real.now(io);
}

fn downloadFile(alloc: std.mem.Allocator, io: std.Io, url: []const u8, dest: []const u8, ca_path_override: ?[]const u8) !void {
    std.debug.print("Downloading: {s}\n", .{url});
    std.debug.print("Destination: {s}\n", .{dest});

    std.debug.print("Parsing URI...\n", .{});
    const uri = std.Uri.parse(url) catch |err| {
        std.debug.print("URI parse error: {}\n", .{err});
        return err;
    };

    const file = if (std.fs.path.isAbsolute(dest))
        try std.Io.Dir.createFileAbsolute(io, dest, .{})
    else
        try std.Io.Dir.cwd().createFile(io, dest, .{});
    defer file.close(io);

    std.debug.print("Fetching...\n", .{});

    var client: std.http.Client = .{ .allocator = alloc, .io = io };
    defer client.deinit();
    try applyCaBundleOverride(&client, alloc, io, ca_path_override);

    var write_buf: [16 * 1024]u8 = undefined;
    var buffered_writer = file.writer(io, &write_buf);

    const result = client.fetch(.{
        .location = .{ .uri = uri },
        .response_writer = &buffered_writer.interface,
    }) catch |err| {
        std.debug.print("Fetch error: {}\n", .{err});
        return err;
    };

    buffered_writer.end() catch |err| {
        std.debug.print("Flush error: {}\n", .{err});
        return err;
    };

    std.debug.print("Response status: {}\n", .{result.status});
    if (result.status != .ok) {
        std.debug.print("HTTP error: expected 200 OK, got {}\n", .{result.status});
        return error.HttpError;
    }

    if (builtin.os.tag != .windows) try file.setPermissions(io, .executable_file);
}

fn extractZipBinary(
    io: std.Io,
    zip_path: []const u8,
    dest: []const u8,
) !void {
    const zip_file = try std.Io.Dir.cwd().openFile(io, zip_path, .{});
    defer zip_file.close(io);

    var read_buf: [16 * 1024]u8 = undefined;
    var zip_reader = zip_file.reader(io, &read_buf);

    var iter = try std.zip.Iterator.init(&zip_reader);
    var filename_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const target_name = std.fs.path.basename(dest);
    const dest_dir_path = std.fs.path.dirname(dest) orelse ".";
    var dest_dir = if (std.fs.path.isAbsolute(dest_dir_path))
        try std.Io.Dir.openDirAbsolute(io, dest_dir_path, .{})
    else
        try std.Io.Dir.cwd().openDir(io, dest_dir_path, .{});
    defer dest_dir.close(io);
    var found = false;

    while (try iter.next()) |entry| {
        if (entry.filename_len > filename_buf.len) return error.ZipInsufficientBuffer;
        try zip_reader.seekTo(entry.header_zip_offset + @sizeOf(std.zip.CentralDirectoryFileHeader));
        try zip_reader.interface.readSliceAll(filename_buf[0..entry.filename_len]);
        var filename = filename_buf[0..entry.filename_len];
        std.mem.replaceScalar(u8, filename, '\\', '/');
        if (filename.len == 0 or filename[filename.len - 1] == '/') continue;
        const base_start = if (std.mem.lastIndexOfScalar(u8, filename, '/')) |idx| idx + 1 else 0;
        const basename = filename[base_start..];
        if (!std.mem.eql(u8, basename, target_name)) continue;

        dest_dir.deleteFile(io, filename) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => {},
            else => return err,
        };
        try entry.extract(&zip_reader, .{ .allow_backslashes = true }, &filename_buf, dest_dir);

        dest_dir.deleteFile(io, target_name) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        dest_dir.rename(filename, dest_dir, target_name, io) catch |err| switch (err) {
            error.CrossDevice => {
                try dest_dir.copyFile(filename, dest_dir, target_name, io, .{});
                dest_dir.deleteFile(io, filename) catch {};
            },
            else => return err,
        };
        found = true;
        break;
    }

    if (!found) return error.MiseZipMissingBinary;
}

fn downloadMise(alloc: std.mem.Allocator, io: std.Io, url: []const u8, dest: []const u8, ca_path_override: ?[]const u8) !void {
    if (std.mem.endsWith(u8, url, ".zip")) {
        const zip_path = try std.fmt.allocPrint(alloc, "{s}.zip", .{dest});
        defer alloc.free(zip_path);
        try downloadFile(alloc, io, url, zip_path, ca_path_override);
        try extractZipBinary(io, zip_path, dest);
        if (std.fs.path.isAbsolute(zip_path)) {
            std.Io.Dir.deleteFileAbsolute(io, zip_path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        } else {
            std.Io.Dir.cwd().deleteFile(io, zip_path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        }
        return;
    }
    try downloadFile(alloc, io, url, dest, ca_path_override);
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;
    const env = init.environ_map;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const cache = try getCacheDir(alloc, env);
    defer alloc.free(cache);
    const ca_bundle = try ensureCaBundle(alloc, io, env, cache);
    defer if (ca_bundle) |path| alloc.free(path);

    const mise_dir = try std.fs.path.join(alloc, &.{ cache, "mise-" ++ MISE_VERSION });
    defer alloc.free(mise_dir);
    std.Io.Dir.cwd().createDirPath(io, mise_dir) catch {};

    const mise_bin = try std.fs.path.join(alloc, &.{ mise_dir, if (builtin.os.tag == .windows) "mise.exe" else "mise" });
    defer alloc.free(mise_bin);

    if (!fileExists(io, mise_bin)) {
        const url = try getMiseUrl(alloc, env);
        defer alloc.free(url);
        try downloadMise(alloc, io, url, mise_bin, ca_bundle);
    }

    const env_ver = getEnvVar(alloc, env, "SAYT_VERSION");
    defer if (env_ver) |v| alloc.free(v);
    // Empty/whitespace SAYT_VERSION means "use the built-in default",
    // matching saytw's ${SAYT_VERSION:-...} semantics.
    const raw_ver = if (env_ver) |v|
        (if (std.mem.trim(u8, v, " \t").len == 0) DEFAULT_VERSION else v)
    else
        DEFAULT_VERSION;
    const ver = try normalizeVersion(alloc, raw_ver);
    defer alloc.free(ver);
    const url_base = try releaseUrlBase(alloc, env, ver);
    defer alloc.free(url_base);

    var exe_buf: [4096]u8 = undefined;
    const exe_len = std.process.executablePath(io, &exe_buf) catch 0;
    const exe_path = exe_buf[0..exe_len];
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";
    var install_dir = exe_dir;
    var found_local = false;

    const local_sayt_nu = try std.fs.path.join(alloc, &.{ install_dir, "sayt.nu" });
    defer alloc.free(local_sayt_nu);
    if (fileExists(io, local_sayt_nu)) {
        found_local = true;
    } else {
        const parent_dir = std.fs.path.dirname(exe_dir) orelse exe_dir;
        if (!std.mem.eql(u8, parent_dir, exe_dir)) {
            const parent_sayt_nu = try std.fs.path.join(alloc, &.{ parent_dir, "sayt.nu" });
            defer alloc.free(parent_sayt_nu);
            if (fileExists(io, parent_sayt_nu)) {
                install_dir = parent_dir;
                found_local = true;
            }
        }
    }

    var child_args = std.ArrayList([]const u8).empty;
    defer child_args.deinit(alloc);
    var owned_args = std.ArrayList([]const u8).empty;
    defer {
        for (owned_args.items) |item| alloc.free(item);
        owned_args.deinit(alloc);
    }
    try child_args.append(alloc, mise_bin);

    if (found_local) {
        const nu_stub = try selectNuStub(alloc, io, install_dir);
        try owned_args.append(alloc, nu_stub);
        const sayt_nu = try std.fs.path.join(alloc, &.{ install_dir, "sayt.nu" });
        try owned_args.append(alloc, sayt_nu);
        try child_args.appendSlice(alloc, &.{ "tool-stub", nu_stub, sayt_nu });
    } else {
        const stub_name = try std.fmt.allocPrint(alloc, "sayt-full-{s}.toml", .{ver});
        defer alloc.free(stub_name);
        const stub_path = try std.fs.path.join(alloc, &.{ cache, stub_name });
        try owned_args.append(alloc, stub_path);
        if (!fileExists(io, stub_path)) {
            const stub = try fullDistStub(alloc, ver, url_base);
            defer alloc.free(stub);
            try writeFile(io, stub_path, stub);
        }
        try child_args.appendSlice(alloc, &.{ "tool-stub", stub_path });
    }

    for (args[1..]) |a| try child_args.append(alloc, a);

    var env_map = env.*;
    const trusted_key = "MISE_TRUSTED_CONFIG_PATHS";
    const path_sep: u8 = if (builtin.os.tag == .windows) ';' else ':';
    const mise_config = try std.fs.path.join(alloc, &.{ install_dir, ".mise.toml" });
    defer alloc.free(mise_config);
    if (fileExists(io, mise_config)) {
        if (env_map.get(trusted_key)) |existing| {
            if (std.mem.indexOf(u8, existing, install_dir) == null) {
                const combined = try std.fmt.allocPrint(alloc, "{s}{c}{s}", .{ install_dir, path_sep, existing });
                defer alloc.free(combined);
                try env_map.put(trusted_key, combined);
            }
        } else {
            try env_map.put(trusted_key, install_dir);
        }
    }
    if (ca_bundle) |path| {
        if (env_map.get("SSL_CERT_FILE") == null) {
            try env_map.put("SSL_CERT_FILE", path);
        }
        if (env_map.get("SAYT_CA_CERT") == null) {
            try env_map.put("SAYT_CA_CERT", path);
        }
    }
    // A consumer repo pinning locked=true would otherwise fail the stub run.
    try env_map.put("MISE_LOCKED", "0");

    var child = try std.process.spawn(io, .{
        .argv = child_args.items,
        .environ_map = &env_map,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    switch (try child.wait(io)) {
        .exited => |code| if (code != 0) std.process.exit(code),
        .signal => |sig| std.process.exit(128 +% @as(u8, @truncate(@intFromEnum(sig)))),
        .stopped, .unknown => std.process.exit(1),
    }
}

// The *_test.nu suites drive a built binary; these cover the string logic
// deciding what gets downloaded, where a wrong answer is a 404 or a silently
// wrong version.

const testing = std.testing;

test "normalizeVersion adds the v prefix only when missing" {
    const alloc = testing.allocator;
    for ([_][2][]const u8{
        .{ "1.2.3", "v1.2.3" },
        .{ "v1.2.3", "v1.2.3" },
        // `latest` is a release channel, not a semver: prefixing it would ask
        // for a tag named vlatest.
        .{ "latest", "latest" },
    }) |case| {
        const got = try normalizeVersion(alloc, case[0]);
        defer alloc.free(got);
        try testing.expectEqualStrings(case[1], got);
    }
}

test "platformFor maps each target to its mise asset slugs" {
    try testing.expectEqualStrings("windows", platformFor(.windows, .x86_64).os);
    try testing.expectEqualStrings("macos", platformFor(.macos, .aarch64).os);
    try testing.expectEqualStrings("linux", platformFor(.linux, .x86_64).os);

    try testing.expectEqualStrings("arm64", platformFor(.macos, .aarch64).arch);
    try testing.expectEqualStrings("armv7", platformFor(.linux, .arm).arch);
    try testing.expectEqualStrings("x64", platformFor(.linux, .x86_64).arch);

    try testing.expectEqualStrings("-musl", platformFor(.linux, .x86_64).suffix);
    try testing.expectEqualStrings("", platformFor(.macos, .aarch64).suffix);
    try testing.expectEqualStrings(".zip", platformFor(.windows, .x86_64).ext);
    try testing.expectEqualStrings("", platformFor(.linux, .x86_64).ext);
}

test "miseUrlFrom builds the default asset url" {
    const alloc = testing.allocator;
    const got = try miseUrlFrom(alloc, null, platformFor(.linux, .x86_64));
    defer alloc.free(got);
    try testing.expectEqualStrings(MISE_URL_BASE ++ "linux-x64-musl", got);
}

test "miseUrlFrom honours a base override and tolerates a trailing slash" {
    const alloc = testing.allocator;
    const want = "http://mirror/mise-" ++ MISE_VERSION ++ "-windows-x64.zip";
    for ([_][]const u8{ "http://mirror", "http://mirror/" }) |base| {
        const got = try miseUrlFrom(alloc, base, platformFor(.windows, .x86_64));
        defer alloc.free(got);
        try testing.expectEqualStrings(want, got);
    }
}

test "releaseUrlBaseFrom picks the channel url for latest" {
    const alloc = testing.allocator;
    const got = try releaseUrlBaseFrom(alloc, null, "latest");
    defer alloc.free(got);
    try testing.expectEqualStrings("https://github.com/bonisoft3/sayt/releases/latest/download/", got);
}

test "releaseUrlBaseFrom pins the tag url for a version" {
    const alloc = testing.allocator;
    const got = try releaseUrlBaseFrom(alloc, null, "v0.3.2");
    defer alloc.free(got);
    try testing.expectEqualStrings("https://github.com/bonisoft3/sayt/releases/download/v0.3.2/", got);
}

// Every caller joins an asset name onto this, so a missing separator would
// silently produce `…/v0.3.2sayt-linux-x64.tar.gz`.
test "releaseUrlBaseFrom override always ends in one slash" {
    const alloc = testing.allocator;
    for ([_][]const u8{ "http://mirror/rel", "http://mirror/rel/" }) |base| {
        const got = try releaseUrlBaseFrom(alloc, base, "v1.0.0");
        defer alloc.free(got);
        try testing.expectEqualStrings("http://mirror/rel/", got);
    }
}

test "fullDistStub carries the version and one url per platform" {
    const alloc = testing.allocator;
    const stub = try fullDistStub(alloc, "v9.9.9", "http://base/");
    defer alloc.free(stub);

    try testing.expect(std.mem.indexOf(u8, stub, "version = \"v9.9.9\"") != null);
    for ([_][]const u8{
        "linux-amd64",  "linux-arm64",   "linux-armv7", "darwin-amd64",
        "darwin-arm64", "windows-amd64", "windows-arm64",
    }) |platform| {
        try testing.expect(std.mem.indexOf(u8, stub, platform) != null);
    }
    // Windows entries override `bin`, otherwise mise looks for an extensionless
    // `sayt` inside the zip.
    try testing.expect(std.mem.indexOf(u8, stub, "bin = \"sayt.exe\"") != null);
    try testing.expect(std.mem.indexOf(u8, stub, "http://base/sayt-macos-arm64.tar.gz") != null);
}
