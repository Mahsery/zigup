const std = @import("std");
const install = @import("install.zig");
const update = @import("update.zig");
const wrapper = @import("wrapper.zig");
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

    // Check if version is available before proceeding
    const is_available = update.isVersionAvailable(allocator, version) catch |err| switch (err) {
        error.FileNotFound => false, // No cache file means run update first
        else => return err,
    };

    if (!is_available) {
        std.debug.print("Error: Version '{s}' not found.\n\n", .{version});

        const available_versions = update.getAvailableVersions(allocator) catch |err| switch (err) {
            else => {
                std.debug.print("Run 'zigup update' to fetch available versions, then try again.\n", .{});
                return;
            },
        };
        defer {
            for (available_versions) |v| allocator.free(v);
            allocator.free(available_versions);
        }

        if (available_versions.len == 0) {
            std.debug.print("Run 'zigup update' to fetch available versions, then try again.\n", .{});
            return;
        }

        std.debug.print("Available versions:\n", .{});
        for (available_versions) |available_version| {
            std.debug.print("  {s}\n", .{available_version});
        }
        return;
    }

    const home = try Platform.getHomeDirAlloc(allocator);
    defer allocator.free(home);
    try validation.validateEnvironmentPath(home);

    const zig_exe = try Platform.getExecutableName(allocator, "zig");
    defer allocator.free(zig_exe);

    const version_dir = try Platform.getInstallDir(allocator, version);
    defer allocator.free(version_dir);

    const version_path = try std.fs.path.join(allocator, &.{ version_dir, zig_exe });
    defer allocator.free(version_path);

    std.fs.cwd().access(version_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Version '{s}' not found locally. Installing...\n", .{version});
            install.run(allocator, &[_][]const u8{version}) catch |install_err| {
                std.debug.print("Error: Failed to install version '{s}': {}\n", .{ version, install_err });
                return;
            };

            // Verify installation was successful before creating symlink
            std.fs.cwd().access(version_path, .{}) catch |verify_err| {
                std.debug.print("Error: Installation failed, version '{s}' still not found: {}\n", .{ version, verify_err });
                return;
            };
        },
        else => return err,
    };

    const bin_dir = try Platform.getBinDir(allocator);
    defer allocator.free(bin_dir);

    try std.fs.cwd().makePath(bin_dir);

    // Always create the wrapper (it will overwrite symlink if it exists)
    try wrapper.createWrapper(allocator);

    // Update the default version file that the wrapper uses  
    try wrapper.updateDefaultCommand(allocator, version);

    std.debug.print("Default Zig version set to: {s}\n", .{version});

    const path_instructions = try Platform.getPathInstructions(allocator, bin_dir);
    defer allocator.free(path_instructions);
    std.debug.print("\n{s}\n", .{path_instructions});
}
