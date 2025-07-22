const std = @import("std");
const ZigupError = @import("../utils/errors.zig").ZigupError;

/// Represents a semantic version with comparison capabilities
pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
    pre_release: ?[]const u8 = null,
    build_metadata: ?[]const u8 = null,
    is_dev: bool = false,
    
    const Self = @This();
    
    /// Parse a version string into a Version struct
    /// Supports formats like: "0.14.1", "0.15.0-dev.1175+e4abdf5a1", "master", "nightly"
    pub fn parse(allocator: std.mem.Allocator, version_str: []const u8) !Self {
        // Handle special cases
        if (std.mem.eql(u8, version_str, "master") or std.mem.eql(u8, version_str, "nightly")) {
            return Self{
                .major = 999,
                .minor = 999,
                .patch = 999,
                .is_dev = true,
            };
        }
        
        // Find the start of version numbers
        var start: usize = 0;
        if (std.mem.startsWith(u8, version_str, "v")) start = 1;
        
        // Look for version pattern in string (for URLs like zig-x86_64-linux-0.15.0-dev.1175+e4abdf5a1.tar.xz)
        if (std.mem.indexOf(u8, version_str, "-")) |dash_idx| {
            if (std.mem.indexOf(u8, version_str[dash_idx+1..], "0.")) |version_start| {
                start = dash_idx + 1 + version_start;
            }
        } else if (std.mem.indexOf(u8, version_str, "0.")) |version_start| {
            start = version_start;
        }
        
        const version_part = version_str[start..];
        
        // Split by '.' to get major.minor.patch
        var parts = std.mem.splitScalar(u8, version_part, '.');
        
        const major_str = parts.next() orelse return ZigupError.VersionParseError;
        const minor_str = parts.next() orelse return ZigupError.VersionParseError;
        const patch_and_rest = parts.next() orelse return ZigupError.VersionParseError;
        
        const major = std.fmt.parseInt(u32, major_str, 10) catch return ZigupError.VersionParseError;
        const minor = std.fmt.parseInt(u32, minor_str, 10) catch return ZigupError.VersionParseError;
        
        // Parse patch (might contain pre-release and build info)
        var patch: u32 = 0;
        var pre_release: ?[]const u8 = null;
        var build_metadata: ?[]const u8 = null;
        var is_dev = false;
        
        // Check for build metadata first (+...)
        var patch_part = patch_and_rest;
        if (std.mem.indexOf(u8, patch_and_rest, "+")) |plus_idx| {
            patch_part = patch_and_rest[0..plus_idx];
            build_metadata = try allocator.dupe(u8, patch_and_rest[plus_idx+1..]);
            
            // Remove file extension if present
            if (std.mem.indexOf(u8, build_metadata.?, ".")) |dot_idx| {
                const clean_build = try allocator.dupe(u8, build_metadata.?[0..dot_idx]);
                allocator.free(build_metadata.?);
                build_metadata = clean_build;
            }
        }
        
        // Check for pre-release (-...)
        if (std.mem.indexOf(u8, patch_part, "-")) |dash_idx| {
            const patch_str = patch_part[0..dash_idx];
            patch = std.fmt.parseInt(u32, patch_str, 10) catch return ZigupError.VersionParseError;
            
            pre_release = try allocator.dupe(u8, patch_part[dash_idx+1..]);
            is_dev = std.mem.startsWith(u8, pre_release.?, "dev");
        } else {
            // Remove file extension from patch if present
            var clean_patch_part = patch_part;
            if (std.mem.indexOf(u8, patch_part, ".tar")) |tar_idx| {
                clean_patch_part = patch_part[0..tar_idx];
            }
            patch = std.fmt.parseInt(u32, clean_patch_part, 10) catch return ZigupError.VersionParseError;
        }
        
        return Self{
            .major = major,
            .minor = minor,
            .patch = patch,
            .pre_release = pre_release,
            .build_metadata = build_metadata,
            .is_dev = is_dev,
        };
    }
    
    /// Compare two versions
    /// Returns: -1 if self < other, 0 if equal, 1 if self > other
    pub fn compare(self: Self, other: Self) i8 {
        // Compare major.minor.patch
        if (self.major != other.major) {
            return if (self.major < other.major) -1 else 1;
        }
        if (self.minor != other.minor) {
            return if (self.minor < other.minor) -1 else 1;
        }
        if (self.patch != other.patch) {
            return if (self.patch < other.patch) -1 else 1;
        }
        
        // Handle pre-release versions (dev versions are newer than release)
        const self_has_pre = self.pre_release != null;
        const other_has_pre = other.pre_release != null;
        
        if (!self_has_pre and !other_has_pre) return 0;
        if (!self_has_pre and other_has_pre) return 1; // Release > pre-release
        if (self_has_pre and !other_has_pre) return -1; // Pre-release < release
        
        // Both have pre-release, compare them
        const self_pre = self.pre_release.?;
        const other_pre = other.pre_release.?;
        
        // Extract dev numbers for comparison
        if (std.mem.startsWith(u8, self_pre, "dev") and std.mem.startsWith(u8, other_pre, "dev")) {
            const self_dev_str = self_pre[4..]; // Skip "dev."
            const other_dev_str = other_pre[4..]; // Skip "dev."
            
            const self_dev = std.fmt.parseInt(u32, self_dev_str, 10) catch 0;
            const other_dev = std.fmt.parseInt(u32, other_dev_str, 10) catch 0;
            
            if (self_dev != other_dev) {
                return if (self_dev < other_dev) -1 else 1;
            }
        }
        
        // Fallback to string comparison for pre-release
        const cmp = std.mem.order(u8, self_pre, other_pre);
        return switch (cmp) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    }
    
    /// Check if this version is newer than other
    pub fn isNewerThan(self: Self, other: Self) bool {
        return self.compare(other) > 0;
    }
    
    /// Check if this version is older than other
    pub fn isOlderThan(self: Self, other: Self) bool {
        return self.compare(other) < 0;
    }
    
    /// Check if this version equals other
    pub fn equals(self: Self, other: Self) bool {
        return self.compare(other) == 0;
    }
    
    /// Format version to string
    pub fn toString(self: Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        
        try result.writer().print("{}.{}.{}", .{ self.major, self.minor, self.patch });
        
        if (self.pre_release) |pre| {
            try result.writer().print("-{s}", .{pre});
        }
        
        if (self.build_metadata) |build| {
            try result.writer().print("+{s}", .{build});
        }
        
        return result.toOwnedSlice();
    }
    
    /// Free allocated memory
    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        if (self.pre_release) |pre| allocator.free(pre);
        if (self.build_metadata) |build| allocator.free(build);
    }
    
    /// Check if version is a development/nightly version
    pub fn isDevelopment(self: Self) bool {
        return self.is_dev or (self.pre_release != null and std.mem.startsWith(u8, self.pre_release.?, "dev"));
    }
};