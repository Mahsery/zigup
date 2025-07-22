const std = @import("std");
const zimdjson = @import("zimdjson");
const cache_utils = @import("../utils/cache.zig");
const VersionIndex = @import("../models/version.zig").VersionIndex;
const ZigVersion = @import("../models/version.zig").ZigVersion;
const HttpClient = @import("../utils/http_client.zig").HttpClient;
const ZigupError = @import("../utils/errors.zig").ZigupError;

/// Check if a version exists in the cached version information
pub fn isVersionAvailable(allocator: std.mem.Allocator, version: []const u8) !bool {
    var version_index = getVersionIndex(allocator) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer {
        var iter = version_index.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        version_index.deinit();
    }

    // Check if version exists (including master/nightly)
    if (std.mem.eql(u8, version, "nightly")) {
        return version_index.contains("master");
    }

    return version_index.contains(version);
}

/// Get list of available versions from cache with semantic sorting
pub fn getAvailableVersions(allocator: std.mem.Allocator) ![][]const u8 {
    var version_index = getVersionIndex(allocator) catch |err| switch (err) {
        error.FileNotFound => return &[_][]const u8{}, // Return empty list if no cache
        else => return err,
    };
    defer {
        var iter = version_index.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        version_index.deinit();
    }

    var versions = std.ArrayList([]const u8).init(allocator);
    var release_versions = std.ArrayList([]const u8).init(allocator);
    defer release_versions.deinit();

    // Separate master/nightly from release versions
    var iterator = version_index.iterator();
    while (iterator.next()) |entry| {
        const version_name = entry.key_ptr.*;
        if (std.mem.eql(u8, version_name, "master")) {
            try versions.append(try allocator.dupe(u8, "nightly"));
        } else {
            try release_versions.append(try allocator.dupe(u8, version_name));
        }
    }

    // Sort release versions semantically (newest first)
    std.mem.sort([]const u8, release_versions.items, {}, compareVersions);
    
    // Add sorted versions to final list
    for (release_versions.items) |version| {
        try versions.append(version);
    }

    return versions.toOwnedSlice();
}

/// Compare versions for semantic sorting (newest first)
fn compareVersions(context: void, a: []const u8, b: []const u8) bool {
    _ = context;
    
    // Simple version comparison - parse major.minor.patch and compare
    const a_parts = parseSimpleVersion(a);
    const b_parts = parseSimpleVersion(b);
    
    // Compare major version first
    if (a_parts.major != b_parts.major) return a_parts.major > b_parts.major;
    // Then minor version
    if (a_parts.minor != b_parts.minor) return a_parts.minor > b_parts.minor;
    // Then patch version
    return a_parts.patch > b_parts.patch;
}

const SimpleVersion = struct {
    major: u32,
    minor: u32, 
    patch: u32,
};

fn parseSimpleVersion(version_str: []const u8) SimpleVersion {
    var parts = std.mem.splitScalar(u8, version_str, '.');
    
    const major_str = parts.next() orelse return SimpleVersion{ .major = 0, .minor = 0, .patch = 0 };
    const minor_str = parts.next() orelse return SimpleVersion{ .major = 0, .minor = 0, .patch = 0 };
    const patch_str = parts.next() orelse return SimpleVersion{ .major = 0, .minor = 0, .patch = 0 };
    
    const major = std.fmt.parseInt(u32, major_str, 10) catch 0;
    const minor = std.fmt.parseInt(u32, minor_str, 10) catch 0;
    const patch = std.fmt.parseInt(u32, patch_str, 10) catch 0;
    
    return SimpleVersion{ .major = major, .minor = minor, .patch = patch };
}

/// Fetch and cache the latest Zig version index from ziglang.org
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0) {
        std.debug.print("Error: 'zigup update' does not accept arguments\n", .{});
        std.debug.print("Usage: zigup update\n", .{});
        return;
    }

    std.debug.print("Fetching Zig version information...\n", .{});

    const url = "https://ziglang.org/download/index.json";
    
    var http_client = HttpClient.init(allocator);
    defer http_client.deinit();

    const body = http_client.fetchJson(url) catch |err| {
        std.debug.print("Error: Failed to fetch version information: {}\n", .{err});
        return ZigupError.HttpRequestFailed;
    };
    defer allocator.free(body);

    const cache_dir = try cache_utils.getCacheDir(allocator);
    defer allocator.free(cache_dir);

    const cache_file = try cache_utils.getIndexCacheFile(allocator);
    defer allocator.free(cache_file);

    try std.fs.cwd().makePath(cache_dir);
    try std.fs.cwd().writeFile(.{ .sub_path = cache_file, .data = body });

    std.debug.print("Version information cached successfully.\n", .{});
}

/// Get parsed version index as HashMap
fn getVersionIndex(allocator: std.mem.Allocator) !VersionIndex {
    const cache_file = try cache_utils.getIndexCacheFile(allocator);
    defer allocator.free(cache_file);

    const json_data = std.fs.cwd().readFileAlloc(allocator, cache_file, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        else => return err,
    };
    defer allocator.free(json_data);

    var parser = zimdjson.dom.StreamParser(.default).init;
    defer parser.deinit(allocator);
    var json_slice = std.io.fixedBufferStream(json_data);
    const document = try parser.parseFromReader(allocator, json_slice.reader().any());
    
    var version_map = VersionIndex.init(allocator);
    
    // Simply store all key-value pairs as raw JSON strings for now
    // This avoids complex lifetime issues with zimdjson Values
    const obj = try document.asObject();
    var iterator = obj.iterator();
    while (iterator.next()) |field| {
        const version_name = try allocator.dupe(u8, field.key);
        const raw_json = "{}"; // Placeholder - we'll enhance this later if needed
        try version_map.put(version_name, .{ .raw_json = raw_json });
    }
    
    return version_map;
}

/// Display available Zig versions from cache with pagination
pub fn showCachedVersions(allocator: std.mem.Allocator) !void {
    try showCachedVersionsWithLimit(allocator, 5);
}

/// Display available Zig versions from cache with optional limit
pub fn showCachedVersionsWithLimit(allocator: std.mem.Allocator, limit: ?usize) !void {
    const versions = getAvailableVersions(allocator) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("No cached version information. Run 'zigup update' first.\n", .{});
            return;
        },
        else => return err,
    };
    defer {
        for (versions) |v| allocator.free(v);
        allocator.free(versions);
    }

    std.debug.print("Available Zig versions:\n", .{});

    const show_count = if (limit) |l| @min(l, versions.len) else versions.len;
    
    for (versions[0..show_count]) |version| {
        std.debug.print("  {s}\n", .{version});
    }
    
    if (limit != null and versions.len > show_count) {
        const remaining = versions.len - show_count;
        std.debug.print("  ... and {d} more\n", .{remaining});
        std.debug.print("\nUse 'zigup update list --all' to see all available versions.\n", .{});
    }
}
