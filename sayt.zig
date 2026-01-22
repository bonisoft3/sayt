const std = @import("std");
const builtin = @import("builtin");

const DEFAULT_VERSION = "v0.0.13";
const MISE_VERSION = "v2026.1.2";
const MISE_URL_BASE = "https://github.com/jdx/mise/releases/download/" ++ MISE_VERSION ++ "/mise-" ++ MISE_VERSION ++ "-";
const CA_CERTS_FILE = "ca-certificates.crt";
const EMBEDDED_CA_CERTS = @embedFile(CA_CERTS_FILE);


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

fn ensureCaBundle(alloc: std.mem.Allocator, cache_dir: []const u8) !?[]const u8 {
    if (getEnvVar(alloc, "SAYT_CA_CERT")) |existing| {
        if (fileExists(existing)) return existing;
        alloc.free(existing);
    }
    if (getEnvVar(alloc, "SSL_CERT_FILE")) |existing| {
        if (fileExists(existing)) return existing;
        alloc.free(existing);
    }

    const cert_path = try std.fs.path.join(alloc, &.{ cache_dir, CA_CERTS_FILE });
    if (!fileExists(cert_path)) {
        std.fs.cwd().makePath(cache_dir) catch {};
        const file = try std.fs.cwd().createFile(cert_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(EMBEDDED_CA_CERTS);
    }
    return cert_path;
}

fn getMiseUrl(alloc: std.mem.Allocator) ![]const u8 {
    if (getEnvVar(alloc, "SAYT_MISE_URL")) |override| {
        return override;
    }

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
    const ext: []const u8 = if (builtin.os.tag == .windows) ".zip" else "";

    if (getEnvVar(alloc, "SAYT_MISE_BASE")) |base| {
        defer alloc.free(base);
        const trimmed = std.mem.trimRight(u8, base, "/");
        return std.fmt.allocPrint(
            alloc,
            "{s}/mise-{s}-{s}-{s}{s}{s}",
            .{ trimmed, MISE_VERSION, os, arch, suffix, ext },
        );
    }

    return std.fmt.allocPrint(alloc, MISE_URL_BASE ++ "{s}-{s}{s}{s}", .{ os, arch, suffix, ext });
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn isMuslRuntime() bool {
    if (builtin.os.tag != .linux) return false;
    const loader = switch (builtin.cpu.arch) {
        .x86_64 => "/lib/ld-musl-x86_64.so.1",
        .aarch64 => "/lib/ld-musl-aarch64.so.1",
        .arm => "/lib/ld-musl-armhf.so.1",
        else => return false,
    };
    return fileExists(loader);
}

fn selectNuStub(alloc: std.mem.Allocator, install_dir: []const u8) ![]const u8 {
    const default_stub = try std.fs.path.join(alloc, &.{ install_dir, "nu.toml" });
    if (!isMuslRuntime()) return default_stub;

    const musl_stub = try std.fs.path.join(alloc, &.{ install_dir, "nu.musl.toml" });
    if (fileExists(musl_stub)) {
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

fn releaseUrlBase(alloc: std.mem.Allocator, version: []const u8) ![]const u8 {
    if (getEnvVar(alloc, "SAYT_RELEASE_BASE")) |override| {
        defer alloc.free(override);
        const trimmed = std.mem.trimRight(u8, override, "/");
        return std.fmt.allocPrint(alloc, "{s}/", .{trimmed});
    }
    if (std.mem.eql(u8, version, "latest")) {
        return alloc.dupe(u8, "https://github.com/bonitao/sayt/releases/latest/download/");
    }
    return std.fmt.allocPrint(alloc, "https://github.com/bonitao/sayt/releases/download/{s}/", .{version});
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

fn writeFile(path: []const u8, contents: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(contents);
}

fn addCaBundleFromPath(
    bundle: *std.crypto.Certificate.Bundle,
    alloc: std.mem.Allocator,
    path: []const u8,
) !void {
    bundle.bytes.clearRetainingCapacity();
    bundle.map.clearRetainingCapacity();
    if (std.fs.path.isAbsolute(path)) {
        try bundle.addCertsFromFilePathAbsolute(alloc, path);
        return;
    }
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    try bundle.addCertsFromFile(alloc, file);
}

fn applyCaBundleOverride(
    client: *std.http.Client,
    alloc: std.mem.Allocator,
    ca_path_override: ?[]const u8,
) !void {
    const ca_path = ca_path_override orelse return;
    std.debug.print("Using CA bundle: {s}\n", .{ca_path});
    client.ca_bundle_mutex.lock();
    defer client.ca_bundle_mutex.unlock();
    try addCaBundleFromPath(&client.ca_bundle, alloc, ca_path);
    @atomicStore(bool, &client.next_https_rescan_certs, false, .release);
}

fn downloadFile(alloc: std.mem.Allocator, url: []const u8, dest: []const u8, ca_path_override: ?[]const u8) !void {
    std.debug.print("Downloading: {s}\n", .{url});
    std.debug.print("Destination: {s}\n", .{dest});

    std.debug.print("Parsing URI...\n", .{});
    const uri = std.Uri.parse(url) catch |err| {
        std.debug.print("URI parse error: {}\n", .{err});
        return err;
    };

    // Create output file
    var file = if (std.fs.path.isAbsolute(dest))
        try std.fs.createFileAbsolute(dest, .{})
    else
        try std.fs.cwd().createFile(dest, .{});
    defer file.close();

    std.debug.print("Fetching...\n", .{});

    var client: std.http.Client = .{ .allocator = alloc };
    defer client.deinit();
    try applyCaBundleOverride(&client, alloc, ca_path_override);

    // Use buffered writer for response
    var write_buf: [16 * 1024]u8 = undefined;
    var buffered_writer = file.writer(&write_buf);

    const result = client.fetch(.{
        .location = .{ .uri = uri },
        .response_writer = &buffered_writer.interface,
    }) catch |err| {
        std.debug.print("Fetch error: {}\n", .{err});
        return err;
    };

    // Flush any remaining buffered data
    buffered_writer.end() catch |err| {
        std.debug.print("Flush error: {}\n", .{err});
        return err;
    };

    std.debug.print("Response status: {}\n", .{result.status});
    if (result.status != .ok) {
        std.debug.print("HTTP error: expected 200 OK, got {}\n", .{result.status});
        return error.HttpError;
    }

    if (builtin.os.tag != .windows) try file.chmod(0o755);
}

fn extractZipBinary(
    zip_path: []const u8,
    dest: []const u8,
) !void {
    var zip_file = try std.fs.cwd().openFile(zip_path, .{});
    defer zip_file.close();

    var read_buf: [16 * 1024]u8 = undefined;
    var zip_reader = zip_file.reader(&read_buf);

    var iter = try std.zip.Iterator.init(&zip_reader);
    var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
    const target_name = std.fs.path.basename(dest);
    const dest_dir_path = std.fs.path.dirname(dest) orelse ".";
    var dest_dir = if (std.fs.path.isAbsolute(dest_dir_path))
        try std.fs.openDirAbsolute(dest_dir_path, .{})
    else
        try std.fs.cwd().openDir(dest_dir_path, .{});
    defer dest_dir.close();
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

        dest_dir.deleteFile(filename) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => {},
            else => return err,
        };
        try entry.extract(&zip_reader, .{ .allow_backslashes = true }, &filename_buf, dest_dir);

        dest_dir.deleteFile(target_name) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        dest_dir.rename(filename, target_name) catch |err| switch (err) {
            error.RenameAcrossMountPoints => {
                try dest_dir.copyFile(filename, dest_dir, target_name, .{});
                dest_dir.deleteFile(filename) catch {};
            },
            else => return err,
        };
        found = true;
        break;
    }

    if (!found) return error.MiseZipMissingBinary;
}

fn downloadMise(alloc: std.mem.Allocator, url: []const u8, dest: []const u8, ca_path_override: ?[]const u8) !void {
    if (std.mem.endsWith(u8, url, ".zip")) {
        const zip_path = try std.fmt.allocPrint(alloc, "{s}.zip", .{dest});
        defer alloc.free(zip_path);
        try downloadFile(alloc, url, zip_path, ca_path_override);
        try extractZipBinary(zip_path, dest);
        if (std.fs.path.isAbsolute(zip_path)) {
            std.fs.deleteFileAbsolute(zip_path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        } else {
            std.fs.cwd().deleteFile(zip_path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        }
        return;
    }
    try downloadFile(alloc, url, dest, ca_path_override);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const cache = try getCacheDir(alloc);
    defer alloc.free(cache);
    const ca_bundle = try ensureCaBundle(alloc, cache);
    defer if (ca_bundle) |path| alloc.free(path);

    const mise_dir = try std.fs.path.join(alloc, &.{ cache, "mise-" ++ MISE_VERSION });
    defer alloc.free(mise_dir);
    std.fs.cwd().makePath(mise_dir) catch {};

    const mise_bin = try std.fs.path.join(alloc, &.{ mise_dir, if (builtin.os.tag == .windows) "mise.exe" else "mise" });
    defer alloc.free(mise_bin);

    if (!fileExists(mise_bin)) {
        const url = try getMiseUrl(alloc);
        defer alloc.free(url);
        try downloadMise(alloc, url, mise_bin, ca_bundle);
    }

    const env_ver = getEnvVar(alloc, "SAYT_VERSION");
    defer if (env_ver) |v| alloc.free(v);
    const raw_ver = env_ver orelse DEFAULT_VERSION;
    const ver = try normalizeVersion(alloc, raw_ver);
    defer alloc.free(ver);
    const url_base = try releaseUrlBase(alloc, ver);
    defer alloc.free(url_base);

    // Check for colocated scripts
    var exe_buf: [4096]u8 = undefined;
    const exe_path = std.fs.selfExePath(&exe_buf) catch "";
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";
    var install_dir = exe_dir;
    var found_local = false;

    const local_sayt_nu = try std.fs.path.join(alloc, &.{ install_dir, "sayt.nu" });
    defer alloc.free(local_sayt_nu);
    if (fileExists(local_sayt_nu)) {
        found_local = true;
    } else {
        const parent_dir = std.fs.path.dirname(exe_dir) orelse exe_dir;
        if (!std.mem.eql(u8, parent_dir, exe_dir)) {
            const parent_sayt_nu = try std.fs.path.join(alloc, &.{ parent_dir, "sayt.nu" });
            defer alloc.free(parent_sayt_nu);
            if (fileExists(parent_sayt_nu)) {
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
        const nu_stub = try selectNuStub(alloc, install_dir);
        try owned_args.append(alloc, nu_stub);
        const sayt_nu = try std.fs.path.join(alloc, &.{ install_dir, "sayt.nu" });
        try owned_args.append(alloc, sayt_nu);
        try child_args.appendSlice(alloc, &.{ "tool-stub", nu_stub, sayt_nu });
    } else {
        const stub_name = try std.fmt.allocPrint(alloc, "sayt-full-{s}.toml", .{ver});
        defer alloc.free(stub_name);
        const stub_path = try std.fs.path.join(alloc, &.{ cache, stub_name });
        try owned_args.append(alloc, stub_path);
        if (!fileExists(stub_path)) {
            const stub = try fullDistStub(alloc, ver, url_base);
            defer alloc.free(stub);
            try writeFile(stub_path, stub);
        }
        try child_args.appendSlice(alloc, &.{ "tool-stub", stub_path });
    }

    for (args[1..]) |a| try child_args.append(alloc, a);

    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();
    const trusted_key = "MISE_TRUSTED_CONFIG_PATHS";
    const path_sep: u8 = if (builtin.os.tag == .windows) ';' else ':';
    const mise_config = try std.fs.path.join(alloc, &.{ install_dir, ".mise.toml" });
    defer alloc.free(mise_config);
    if (fileExists(mise_config)) {
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

    var child = std.process.Child.init(child_args.items, alloc);
    child.env_map = &env_map;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    _ = try child.spawnAndWait();
}
