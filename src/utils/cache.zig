const std = @import("std");
const Platform = @import("platform.zig").Platform;

/// Get the cache directory path for storing version data
pub fn getCacheDir(allocator: std.mem.Allocator) ![]u8 {
    return Platform.getCacheDir(allocator);
}