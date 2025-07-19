const std = @import("std");
const validation = @import("../utils/validation.zig");
const Platform = @import("../utils/platform.zig").Platform;
const builtin = @import("builtin");

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: No version specified\n", .{});
        return;
    }

    const version = args[0];
    try validation.validateVersionString(version);

    const home = try Platform.getHomeDir();
    try validation.validateEnvironmentPath(home);

    const version_dir = try Platform.getInstallDir(allocator, version);
    defer allocator.free(version_dir);

    std.fs.cwd().access(version_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Error: Version '{s}' is not installed\n", .{version});
            return;
        },
        else => return err,
    };

    const bin_dir = try Platform.getBinDir(allocator);
    defer allocator.free(bin_dir);
    
    const link_path = try std.fs.path.join(allocator, &.{ bin_dir, "zig" });
    defer allocator.free(link_path);

    // Check if this version is currently the default
    switch (builtin.os.tag) {
        .windows => {
            // Check batch wrapper content
            const wrapper_path = try std.fmt.allocPrint(allocator, "{s}.bat", .{link_path});
            defer allocator.free(wrapper_path);
            
            if (std.fs.cwd().readFileAlloc(allocator, wrapper_path, 1024)) |content| {
                defer allocator.free(content);
                
                const zig_exe = try Platform.getExecutableName(allocator, "zig");
                defer allocator.free(zig_exe);
                
                const expected_path = try std.fs.path.join(allocator, &.{ version_dir, zig_exe });
                defer allocator.free(expected_path);
                
                if (std.mem.indexOf(u8, content, expected_path) != null) {
                    std.debug.print("Error: Cannot remove '{s}' - it is currently the default version\n", .{version});
                    std.debug.print("Set a different version as default first with: zigup default <version>\n", .{});
                    return;
                }
            } else |_| {}
        },
        else => {
            // Check symlink target
            var buffer: [1024]u8 = undefined;
            if (std.fs.cwd().readLink(link_path, &buffer)) |current_target| {
                const zig_exe = try Platform.getExecutableName(allocator, "zig");
                defer allocator.free(zig_exe);
                
                const expected_target = try std.fs.path.join(allocator, &.{ version_dir, zig_exe });
                defer allocator.free(expected_target);
                
                if (std.mem.eql(u8, current_target, expected_target)) {
                    std.debug.print("Error: Cannot remove '{s}' - it is currently the default version\n", .{version});
                    std.debug.print("Set a different version as default first with: zigup default <version>\n", .{});
                    return;
                }
            } else |_| {}
        },
    }

    std.debug.print("Removing Zig version '{s}' from {s}...\n", .{ version, version_dir });
    
    std.fs.cwd().deleteTree(version_dir) catch |err| switch (err) {
        error.AccessDenied => {
            const instructions = switch (builtin.os.tag) {
                .windows => "Please check directory permissions or run as Administrator",
                else => "Please fix directory permissions or run: sudo chown -R $USER:$USER ~/bin",
            };
            std.debug.print("Error: Permission denied removing directory: {s}\n", .{version_dir});
            std.debug.print("{s}\n", .{instructions});
            return;
        },
        else => return err,
    };

    std.debug.print("Successfully removed version '{s}'\n", .{version});
}