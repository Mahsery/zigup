const std = @import("std");
const install = @import("install.zig");

/// Set a Zig version as the system default, installing it if necessary
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: No version specified\n", .{});
        return;
    }
    
    const version = args[0];
    
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const version_path = try std.fs.path.join(allocator, &.{ home, "bin", version, "zig" });
    defer allocator.free(version_path);
    
    std.fs.cwd().access(version_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Version '{s}' not found. Installing...\n", .{version});
            install.run(allocator, &[_][]const u8{version}) catch |install_err| {
                std.debug.print("Error: Failed to install version '{s}': {}\n", .{ version, install_err });
                return;
            };
        },
        else => return err,
    };
    
    const local_bin_dir = try std.fs.path.join(allocator, &.{ home, ".local", "bin" });
    defer allocator.free(local_bin_dir);
    
    try std.fs.cwd().makePath(local_bin_dir);
    
    const symlink_path = try std.fs.path.join(allocator, &.{ local_bin_dir, "zig" });
    defer allocator.free(symlink_path);
    
    std.fs.cwd().deleteFile(symlink_path) catch {};
    try std.posix.symlink(version_path, symlink_path);
    
    std.debug.print("Default Zig version set to: {s}\n", .{version});
    std.debug.print("Symlink created at: {s}\n", .{symlink_path});
    std.debug.print("\nMake sure ~/.local/bin is in your PATH. Add this to your shell profile:\n", .{});
    std.debug.print("export PATH=\"$HOME/.local/bin:$PATH\"\n", .{});
}