const std = @import("std");
const zimdjson = @import("zimdjson");
const cache_utils = @import("../utils/cache.zig");

/// Check if a version exists in the cached version information
pub fn isVersionAvailable(allocator: std.mem.Allocator, version: []const u8) !bool {
    const cache_file = try cache_utils.getIndexCacheFile(allocator);
    defer allocator.free(cache_file);
    
    const json_data = std.fs.cwd().readFileAlloc(allocator, cache_file, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return false, // No cache means no available versions
        else => return err,
    };
    defer allocator.free(json_data);
    
    const Parser = zimdjson.dom.StreamParser(.default);
    var parser = Parser.init;
    defer parser.deinit(allocator);
    var json_slice = std.io.fixedBufferStream(json_data);
    const document = try parser.parseFromReader(allocator, json_slice.reader().any());
    
    // Check if version exists (including master/nightly)
    const version_key = if (std.mem.eql(u8, version, "nightly"))
        "master"
    else
        version;
    
    const version_obj = document.at(version_key);
    return (version_obj.asObject() catch null) != null;
}

/// Get list of available versions from cache
pub fn getAvailableVersions(allocator: std.mem.Allocator) ![][]const u8 {
    const cache_file = try cache_utils.getIndexCacheFile(allocator);
    defer allocator.free(cache_file);
    
    const json_data = std.fs.cwd().readFileAlloc(allocator, cache_file, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return &[_][]const u8{}, // Return empty list if no cache
        else => return err,
    };
    defer allocator.free(json_data);
    
    const Parser = zimdjson.dom.StreamParser(.default);
    var parser = Parser.init;
    defer parser.deinit(allocator);
    var json_slice = std.io.fixedBufferStream(json_data);
    const document = try parser.parseFromReader(allocator, json_slice.reader().any());
    
    var versions = std.ArrayList([]const u8).init(allocator);
    
    // Add master/nightly if it exists
    const master_obj = document.at("master");
    if ((master_obj.asObject() catch null) != null) {
        try versions.append(try allocator.dupe(u8, "master"));
        try versions.append(try allocator.dupe(u8, "nightly"));
    }
    
    // Add known release versions that exist in the data
    const releases = [_][]const u8{ "0.14.1", "0.14.0", "0.13.0", "0.12.0", "0.11.0" };
    for (releases) |version| {
        const version_obj = document.at(version);
        if ((version_obj.asObject() catch null) != null) {
            try versions.append(try allocator.dupe(u8, version));
        }
    }
    
    return versions.toOwnedSlice();
}

/// Fetch and cache the latest Zig version index from ziglang.org
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;
    
    std.debug.print("Fetching Zig version information...\n", .{});
    
    const url = "https://ziglang.org/download/index.json";
    const fs_utils = @import("../utils/fs.zig");
    try fs_utils.validateUrl(url);
    
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    
    var buf: [8192]u8 = undefined;
    var req = try client.open(.GET, try std.Uri.parse(url), .{
        .server_header_buffer = &buf,
    });
    defer req.deinit();
    
    try req.send();
    try req.finish();
    try req.wait();
    
    const body = try req.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);
    
    const cache_dir = try cache_utils.getCacheDir(allocator);
    defer allocator.free(cache_dir);
    
    const cache_file = try cache_utils.getIndexCacheFile(allocator);
    defer allocator.free(cache_file);
    
    try std.fs.cwd().makePath(cache_dir);
    try std.fs.cwd().writeFile(.{ .sub_path = cache_file, .data = body });
    
    std.debug.print("Version information cached successfully.\n", .{});
}

/// Display available Zig versions from cache
pub fn showCachedVersions(allocator: std.mem.Allocator) !void {
    const cache_dir = try cache_utils.getCacheDir(allocator);
    defer allocator.free(cache_dir);
    
    const cache_file = try cache_utils.getIndexCacheFile(allocator);
    defer allocator.free(cache_file);
    
    const json_data = std.fs.cwd().readFileAlloc(allocator, cache_file, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("No cached version information. Run 'zigup update' first.\n", .{});
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
    
    std.debug.print("Available Zig versions:\n", .{});
    std.debug.print("  master (nightly)\n", .{});
    
    const releases = [_][]const u8{ "0.14.1", "0.14.0", "0.13.0", "0.12.0", "0.11.0" };
    for (releases) |version| {
        const version_obj = document.at(version);
        if (version_obj.asObject()) |_| {
            std.debug.print("  {s}\n", .{version});
        } else |_| {}
    }
}

