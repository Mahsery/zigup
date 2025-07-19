const std = @import("std");

pub fn validateVersionString(version: []const u8) !void {
    // Length validation
    if (version.len == 0) return error.EmptyVersion;
    if (version.len > 64) return error.VersionTooLong; // Reasonable limit for version strings
    
    // Path traversal prevention
    if (std.mem.indexOf(u8, version, "..") != null) return error.InvalidVersion;
    if (std.mem.indexOf(u8, version, "/") != null) return error.InvalidVersion;
    if (std.mem.indexOf(u8, version, "\\") != null) return error.InvalidVersion;
    if (std.fs.path.isAbsolute(version)) return error.InvalidVersion;
    
    // Character restrictions - only allow alphanumeric, dots, hyphens, and plus
    for (version) |char| {
        switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '.', '-', '+' => {},
            else => return error.InvalidCharacter,
        }
    }
    
    // Additional safety checks
    if (std.mem.startsWith(u8, version, ".")) return error.InvalidVersion; // No leading dots
    if (std.mem.endsWith(u8, version, ".")) return error.InvalidVersion; // No trailing dots
    if (std.mem.indexOf(u8, version, "--") != null) return error.InvalidVersion; // No double hyphens
}

pub fn validateEnvironmentPath(path: []const u8) !void {
    if (std.mem.indexOf(u8, path, "..") != null) return error.UnsafePath;
    if (!std.fs.path.isAbsolute(path)) return error.RelativePath;
}