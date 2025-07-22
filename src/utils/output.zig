const std = @import("std");

/// Print to stdout for user-facing output, program results, status messages
pub fn printOut(comptime fmt: []const u8, args: anytype) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(fmt, args);
}

/// Print to stderr for errors, warnings, usage instructions
pub fn printErr(comptime fmt: []const u8, args: anytype) !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.print(fmt, args);
}
