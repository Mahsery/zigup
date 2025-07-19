const std = @import("std");
const validation = @import("../utils/validation.zig");

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: No version specified\n", .{});
        return;
    }

    const version = args[0];
    try validation.validateVersionString(version);

    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    try validation.validateEnvironmentPath(home);

    const version_dir = try std.fs.path.join(allocator, &.{ home, "bin", version });
    defer allocator.free(version_dir);

    std.fs.cwd().access(version_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Error: Version '{s}' is not installed\n", .{version});
            return;
        },
        else => return err,
    };

    const local_bin = try std.fs.path.join(allocator, &.{ home, ".local", "bin", "zig" });
    defer allocator.free(local_bin);

    var buffer: [1024]u8 = undefined;
    if (std.fs.cwd().readLink(local_bin, &buffer)) |current_target| {
        const expected_target = try std.fs.path.join(allocator, &.{ home, "bin", version, "zig" });
        defer allocator.free(expected_target);
        
        if (std.mem.eql(u8, current_target, expected_target)) {
            std.debug.print("Error: Cannot remove '{s}' - it is currently the default version\n", .{version});
            std.debug.print("Set a different version as default first with: zigup default <version>\n", .{});
            return;
        }
    } else |_| {}

    std.debug.print("Removing Zig version '{s}' from {s}...\n", .{ version, version_dir });
    
    std.fs.cwd().deleteTree(version_dir) catch |err| switch (err) {
        error.AccessDenied => {
            std.debug.print("Error: Permission denied removing directory: {s}\n", .{version_dir});
            std.debug.print("Please fix directory permissions or run: sudo chown -R $USER:$USER ~/bin\n", .{});
            return;
        },
        else => return err,
    };

    std.debug.print("Successfully removed version '{s}'\n", .{version});
}