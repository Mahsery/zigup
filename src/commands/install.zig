const std = @import("std");
const zimdjson = @import("zimdjson");
const fs_utils = @import("../utils/fs.zig");

/// Download and install a specific Zig version
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: No version specified\n", .{});
        return;
    }
    
    const version = args[0];
    std.debug.print("Installing Zig version: {s}\n", .{version});
    
    const cache_dir = try getCacheDir(allocator);
    defer allocator.free(cache_dir);
    
    const cache_file = try std.fs.path.join(allocator, &.{ cache_dir, "index.json" });
    defer allocator.free(cache_file);
    
    const json_data = std.fs.cwd().readFileAlloc(allocator, cache_file, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Error: Version cache not found. Run 'zigup update' first.\n", .{});
            return;
        },
        else => return err,
    };
    defer allocator.free(json_data);
    
    const Parser = zimdjson.dom.StreamParser(.default);
    var parser = Parser.init;
    defer parser.deinit(allocator);
    var json_slice = std.io.fixedBufferStream(json_data);
    const document = try parser.parseFromReader(allocator, json_slice.reader().any());
    
    const platform = try detectPlatform();
    std.debug.print("Detected platform: {s}\n", .{platform});
    
    const version_key = if (std.mem.eql(u8, version, "master") or std.mem.eql(u8, version, "nightly"))
        "master"
    else
        version;
    
    const version_obj = document.at(version_key);
    const download_info = version_obj.at(platform);
    
    const tarball_url = download_info.at("tarball").asString() catch |err| switch (err) {
        error.MissingField => {
            std.debug.print("Error: Version '{s}' or platform '{s}' not found\n", .{ version, platform });
            return;
        },
        else => return err,
    };
    std.debug.print("Download URL: {s}\n", .{tarball_url});
    
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const bin_dir = try std.fs.path.join(allocator, &.{ home, "bin" });
    defer allocator.free(bin_dir);
    
    std.fs.cwd().makePath(bin_dir) catch |err| switch (err) {
        error.AccessDenied => {
            std.debug.print("Error: Cannot create {s}. Please run: sudo chown {s}:{s} {s}\n", .{ bin_dir, std.posix.getenv("USER") orelse "user", std.posix.getenv("USER") orelse "user", bin_dir });
            return;
        },
        else => return err,
    };
    
    const version_dir = try std.fs.path.join(allocator, &.{ bin_dir, version });
    defer allocator.free(version_dir);
    
    
    const archive_name = std.fs.path.basename(tarball_url);
    const archive_path = try std.fs.path.join(allocator, &.{ cache_dir, archive_name });
    defer allocator.free(archive_path);
    
    std.debug.print("Downloading to {s}...\n", .{archive_path});
    fs_utils.downloadFile(allocator, tarball_url, archive_path) catch |err| {
        std.debug.print("Error: Download failed: {}\n", .{err});
        return;
    };
    
    std.debug.print("Extracting to {s}...\n", .{version_dir});
    fs_utils.extractTarXz(allocator, archive_path, version_dir) catch |err| {
        std.debug.print("Error: Extraction failed: {}\n", .{err});
        return;
    };
    
    std.fs.cwd().deleteFile(archive_path) catch {};
    
    std.debug.print("Successfully installed Zig version: {s}\n", .{version});
}

/// Get the cache directory path for storing version data
fn getCacheDir(allocator: std.mem.Allocator) ![]u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return try std.fs.path.join(allocator, &.{ home, ".cache", "zigup" });
}

/// Detect current platform for appropriate Zig download selection
fn detectPlatform() ![]const u8 {
    const builtin = @import("builtin");
    const arch = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .arm => "arm",
        else => return error.UnsupportedArchitecture,
    };
    
    const os = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "macos", 
        .windows => "windows",
        .freebsd => "freebsd",
        else => return error.UnsupportedOS,
    };
    
    return try std.fmt.allocPrint(std.heap.page_allocator, "{s}-{s}", .{ arch, os });
}