const std = @import("std");
const validation = @import("../utils/validation.zig");
const output = @import("../utils/output.zig");
const update = @import("update.zig");

/// Set a local Zig version for the current project directory
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try output.printErr("Error: No version specified\n", .{});
        try output.printOut("Usage: zigup use <version>\n", .{});
        return;
    }

    const version = args[0];
    try validation.validateVersionString(version);

    // Check if version is available before proceeding
    const is_available = if (update.isVersionAvailable(allocator, version)) |available| available else |err| if (err == error.FileNotFound) false else return err;

    if (!is_available) {
        try output.printErr("Error: Version '{s}' not found.\n", .{version});
        try output.printOut("Run 'zigup update' to fetch available versions, then try again.\n", .{});
        return;
    }

    // Write the version to .zig-version file in current directory
    const file = std.fs.cwd().createFile(".zig-version", .{}) catch |err| {
        try output.printErr("Error: Could not create .zig-version file: {}\n", .{err});
        return;
    };
    defer file.close();

    _ = file.writeAll(version) catch |err| {
        try output.printErr("Error: Could not write to .zig-version file: {}\n", .{err});
        return;
    };

    try output.printOut("Local Zig version set to: {s}\n", .{version});
    try output.printOut("Created .zig-version file in current directory\n", .{});
}

/// Read the local .zig-version file if it exists
pub fn getLocalVersion(allocator: std.mem.Allocator) !?[]u8 {
    const file = std.fs.cwd().openFile(".zig-version", .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024);

    // Trim whitespace from the version string
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");

    if (trimmed.len == 0) {
        allocator.free(contents);
        return null;
    }

    // Create a copy of just the trimmed content
    const result = try allocator.dupe(u8, trimmed);
    allocator.free(contents);
    return result;
}

/// Find local version by walking up directories
pub fn findLocalVersion(allocator: std.mem.Allocator) !?[]u8 {
    var current_dir = std.fs.cwd();
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var should_close_current = false;

    // Start from current directory and walk up to find .zig-version
    while (true) {
        // Try to read .zig-version in current directory
        if (getLocalVersionInDir(allocator, current_dir)) |version| {
            // Close current dir if it's not cwd before returning
            if (should_close_current) {
                current_dir.close();
            }
            return version;
        } else |err| switch (err) {
            error.FileNotFound => {}, // Continue searching up
            else => {
                // Close current dir if it's not cwd before returning error
                if (should_close_current) {
                    current_dir.close();
                }
                return err;
            },
        }

        // Get current directory path
        const current_path = current_dir.realpath(".", &path_buf) catch {
            // Close current dir if it's not cwd before breaking
            if (should_close_current) {
                current_dir.close();
            }
            break;
        };

        // Check if we've reached the root directory
        if (std.mem.eql(u8, current_path, "/") or
            (current_path.len >= 3 and current_path[1] == ':' and current_path[2] == '\\'))
        {
            // Close current dir if it's not cwd before breaking
            if (should_close_current) {
                current_dir.close();
            }
            break; // Windows or Unix root
        }

        // Move up one directory
        const parent_dir = current_dir.openDir("..", .{}) catch {
            // Close current dir if it's not cwd before breaking
            if (should_close_current) {
                current_dir.close();
            }
            break;
        };

        // Close the current directory if it's not cwd
        if (should_close_current) {
            current_dir.close();
        }

        current_dir = parent_dir;
        should_close_current = true; // Now we need to close subsequent dirs
    }

    return null;
}

fn getLocalVersionInDir(allocator: std.mem.Allocator, dir: std.fs.Dir) ![]u8 {
    const file = try dir.openFile(".zig-version", .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024);

    // Trim whitespace from the version string
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");

    if (trimmed.len == 0) {
        allocator.free(contents);
        return error.FileNotFound;
    }

    // Create a copy of just the trimmed content
    const result = try allocator.dupe(u8, trimmed);
    allocator.free(contents);
    return result;
}
