const std = @import("std");

pub fn validateVersionString(version: []const u8) !void {
    if (std.mem.indexOf(u8, version, "..") != null) return error.InvalidVersion;
    if (std.mem.indexOf(u8, version, "/") != null) return error.InvalidVersion;
    if (std.mem.indexOf(u8, version, "\\") != null) return error.InvalidVersion;
    if (std.fs.path.isAbsolute(version)) return error.InvalidVersion;
}

pub fn validateEnvironmentPath(path: []const u8) !void {
    if (std.mem.indexOf(u8, path, "..") != null) return error.UnsafePath;
    if (!std.fs.path.isAbsolute(path)) return error.RelativePath;
}