const std = @import("std");
const zimdjson = @import("zimdjson");
const fs_utils = @import("../utils/fs.zig");
const cache_utils = @import("../utils/cache.zig");

/// Download and install a specific Zig version
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: No version specified\n", .{});
        return;
    }
    
    const version = args[0];
    std.debug.print("Installing Zig version: {s}\n", .{version});
    
    const cache_dir = try cache_utils.getCacheDir(allocator);
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
    
    const platform = try detectPlatform(allocator);
    defer allocator.free(platform);
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
    
    // Download and verify minisign signature
    const signature_url = try std.fmt.allocPrint(allocator, "{s}.minisig", .{tarball_url});
    defer allocator.free(signature_url);
    const signature_path = try std.fmt.allocPrint(allocator, "{s}.minisig", .{archive_path});
    defer allocator.free(signature_path);
    
    std.debug.print("Downloading signature...\n", .{});
    fs_utils.downloadFile(allocator, signature_url, signature_path) catch |err| {
        std.debug.print("Error: Signature download failed: {}\n", .{err});
        return;
    };
    
    std.debug.print("Verifying signature...\n", .{});
    verifyMinisign(allocator, archive_path, signature_path) catch |err| {
        std.debug.print("Error: Signature verification failed: {}\n", .{err});
        std.fs.cwd().deleteFile(archive_path) catch {};
        std.fs.cwd().deleteFile(signature_path) catch {};
        return;
    };
    
    std.debug.print("Extracting to {s}...\n", .{version_dir});
    fs_utils.extractTarXz(allocator, archive_path, version_dir) catch |err| {
        std.debug.print("Error: Extraction failed: {}\n", .{err});
        return;
    };
    
    std.fs.cwd().deleteFile(archive_path) catch {};
    std.fs.cwd().deleteFile(signature_path) catch {};
    
    std.debug.print("Successfully installed Zig version: {s}\n", .{version});
}

/// Verify minisign signature using Zig team's public key
fn verifyMinisign(allocator: std.mem.Allocator, file_path: []const u8, signature_path: []const u8) !void {
    const cache_dir = try cache_utils.getCacheDir(allocator);
    defer allocator.free(cache_dir);
    
    const pubkey_path = try std.fs.path.join(allocator, &.{ cache_dir, "zig.pub" });
    defer allocator.free(pubkey_path);
    
    // Download the public key if not cached or refresh it
    std.debug.print("Fetching Zig public key...\n", .{});
    fs_utils.downloadFile(allocator, "https://ziglang.org/download/index.json", pubkey_path) catch |err| {
        std.debug.print("Error: Failed to fetch Zig public key: {}\n", .{err});
        return err;
    };
    
    // Extract public key from the downloaded JSON
    const pubkey_data = std.fs.cwd().readFileAlloc(allocator, pubkey_path, 1024 * 1024) catch |err| {
        std.debug.print("Error: Failed to read public key file: {}\n", .{err});
        return err;
    };
    defer allocator.free(pubkey_data);
    
    const Parser = zimdjson.dom.StreamParser(.default);
    var parser = Parser.init;
    defer parser.deinit(allocator);
    var json_slice = std.io.fixedBufferStream(pubkey_data);
    const document = try parser.parseFromReader(allocator, json_slice.reader().any());
    
    const pubkey = document.at("minisign_public_key").asString() catch {
        std.debug.print("Error: Could not find minisign_public_key in Zig download index\n", .{});
        return error.PublicKeyNotFound;
    };
    
    var process = std.process.Child.init(&[_][]const u8{
        "minisign", "-Vm", file_path, "-P", pubkey, "-x", signature_path
    }, allocator);
    
    const result = process.spawnAndWait() catch |err| {
        std.debug.print("Error: Failed to run minisign command. Is minisign installed?\n", .{});
        std.debug.print("Install with: sudo apt install minisign (Ubuntu/Debian) or brew install minisign (macOS)\n", .{});
        return err;
    };
    
    switch (result) {
        .Exited => |code| if (code != 0) {
            std.debug.print("Error: Signature verification failed. This download may be compromised.\n", .{});
            return error.SignatureVerificationFailed;
        },
        else => {
            std.debug.print("Error: minisign command terminated unexpectedly\n", .{});
            return error.SignatureVerificationFailed;
        },
    }
}


/// Detect current platform for appropriate Zig download selection
fn detectPlatform(allocator: std.mem.Allocator) ![]const u8 {
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
    
    return try std.fmt.allocPrint(allocator, "{s}-{s}", .{ arch, os });
}