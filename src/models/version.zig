const std = @import("std");

/// Download metadata for a specific platform
pub const Download = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: []const u8, // JSON returns as string, not u64
};

/// Platform-specific downloads for a version
pub const PlatformDownloads = struct {
    @"x86_64-linux": ?Download = null,
    @"x86_64-macos": ?Download = null,
    @"x86_64-windows": ?Download = null,
    @"aarch64-linux": ?Download = null,
    @"aarch64-macos": ?Download = null,
};

/// Represents a single Zig version with download information
pub const ZigVersion = struct {
    date: []const u8,
    docs: ?[]const u8 = null,
    stdDocs: ?[]const u8 = null,
    notes: ?[]const u8 = null,
    src: ?Download = null,
    
    // Platform downloads - using inline to flatten the structure
    @"x86_64-linux": ?Download = null,
    @"x86_64-macos": ?Download = null,
    @"x86_64-windows": ?Download = null,
    @"aarch64-linux": ?Download = null,
    @"aarch64-macos": ?Download = null,
};

/// Complete version index from ziglang.org - dynamic structure using raw JSON values
/// We'll define this as a generic type alias that gets resolved in update.zig
pub const VersionIndex = std.HashMap([]const u8, JsonValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage);

/// Placeholder type that will be the actual Value type from the parser we use
pub const JsonValue = struct {
    // We'll store the raw JSON as string and parse on demand
    raw_json: []const u8,
};
