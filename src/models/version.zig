const std = @import("std");

/// Represents a single Zig version with download information
pub const ZigVersion = struct {
    name: []const u8,
    date: []const u8,
    downloads: std.StringHashMap(Download),

    /// Download metadata for a specific platform
    const Download = struct {
        tarball: []const u8,
        shasum: []const u8,
        size: u64,
    };
};

/// Complete version index from ziglang.org
pub const VersionIndex = struct {
    master: ZigVersion,
    versions: std.StringHashMap(ZigVersion),
};
