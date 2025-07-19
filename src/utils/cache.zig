const std = @import("std");

/// Get the cache directory path for storing version data
pub fn getCacheDir(allocator: std.mem.Allocator) ![]u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return try std.fs.path.join(allocator, &.{ home, ".cache", "zigup" });
}