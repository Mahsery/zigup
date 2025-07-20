const std = @import("std");
const Platform = @import("platform.zig").Platform;

/// Get the cache directory path for storing version data
pub fn getCacheDir(allocator: std.mem.Allocator) ![]u8 {
    return Platform.getCacheDir(allocator);
}

/// Get the version index cache file path (index.json)
pub fn getIndexCacheFile(allocator: std.mem.Allocator) ![]u8 {
    const cache_dir = try getCacheDir(allocator);
    defer allocator.free(cache_dir);
    return try std.fs.path.join(allocator, &.{ cache_dir, "index.json" });
}

/// Get the public key cache file path (zig.pub)
pub fn getPublicKeyCacheFile(allocator: std.mem.Allocator) ![]u8 {
    const cache_dir = try getCacheDir(allocator);
    defer allocator.free(cache_dir);
    return try std.fs.path.join(allocator, &.{ cache_dir, "zig.pub" });
}
