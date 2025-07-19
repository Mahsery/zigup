const std = @import("std");
const Platform = @import("../utils/platform.zig").Platform;

/// List all locally installed Zig versions
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;
    
    const home = try Platform.getHomeDirAlloc(allocator);
    defer allocator.free(home);
    const bin_dir = try std.fs.path.join(allocator, &.{ home, "bin" });
    defer allocator.free(bin_dir);
    
    var dir = std.fs.cwd().openDir(bin_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("No Zig versions installed.\n", .{});
            return;
        },
        else => return err,
    };
    defer dir.close();
    
    std.debug.print("Installed Zig versions:\n", .{});
    
    const zig_exe = try Platform.getExecutableName(allocator, "zig");
    defer allocator.free(zig_exe);
    
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            const zig_path = try std.fs.path.join(allocator, &.{ bin_dir, entry.name, zig_exe });
            defer allocator.free(zig_path);
            
            std.fs.cwd().access(zig_path, .{}) catch continue;
            std.debug.print("  {s}\n", .{entry.name});
        }
    }
}