const std = @import("std");
const install = @import("install.zig");
const validation = @import("../utils/validation.zig");
const Platform = @import("../utils/platform.zig").Platform;

/// Set a Zig version as the system default, installing it if necessary
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: No version specified\n", .{});
        return;
    }
    
    const version = args[0];
    try validation.validateVersionString(version);
    
    const home = try Platform.getHomeDir();
    try validation.validateEnvironmentPath(home);
    
    const zig_exe = try Platform.getExecutableName(allocator, "zig");
    defer allocator.free(zig_exe);
    
    const version_dir = try Platform.getInstallDir(allocator, version);
    defer allocator.free(version_dir);
    
    const version_path = try std.fs.path.join(allocator, &.{ version_dir, zig_exe });
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
    
    const bin_dir = try Platform.getBinDir(allocator);
    defer allocator.free(bin_dir);
    
    try std.fs.cwd().makePath(bin_dir);
    
    const link_path = try std.fs.path.join(allocator, &.{ bin_dir, "zig" });
    defer allocator.free(link_path);
    
    try Platform.createVersionLink(allocator, version_path, link_path);
    
    std.debug.print("Default Zig version set to: {s}\n", .{version});
    
    const path_instructions = try Platform.getPathInstructions(allocator, bin_dir);
    defer allocator.free(path_instructions);
    std.debug.print("\n{s}\n", .{path_instructions});
}