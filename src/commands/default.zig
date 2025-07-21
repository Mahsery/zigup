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

    // For nightly, fetch latest version info and check for updates
    if (std.mem.eql(u8, version, "nightly")) {
        std.debug.print("Checking for nightly updates...\n", .{});
        update.run(allocator, &[_][]const u8{}) catch |err| {
            std.debug.print("Warning: Could not check for updates: {}\n", .{err});
        };
        
        // Check if we need to update the installed nightly
        const needs_update = try needsNightlyUpdate(allocator);
        if (needs_update) {
            std.debug.print("Newer nightly version available, updating...\n", .{});
            install.run(allocator, &[_][]const u8{"nightly"}) catch |err| {
                std.debug.print("Warning: Could not update nightly: {}\n", .{err});
            };
        }
    }

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

fn needsNightlyUpdate(allocator: std.mem.Allocator) !bool {
    const zimdjson = @import("zimdjson");
    const cache_utils = @import("../utils/cache.zig");
    
    // Get the cached version info
    const cache_file = try cache_utils.getIndexCacheFile(allocator);
    defer allocator.free(cache_file);
    
    const json_data = std.fs.cwd().readFileAlloc(allocator, cache_file, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return true, // No cache means update needed
        else => return err,
    };
    defer allocator.free(json_data);
    
    const Parser = zimdjson.dom.StreamParser(.default);
    var parser = Parser.init;
    defer parser.deinit(allocator);
    var json_slice = std.io.fixedBufferStream(json_data);
    const document = try parser.parseFromReader(allocator, json_slice.reader().any());
    
    const master_obj = document.at("master");
    const platform_str = Platform.getPlatformString();
    const download_info = master_obj.at(platform_str);
    const latest_url = download_info.at("tarball").asString() catch return false;
    
    // Extract version from URL (e.g., zig-x86_64-linux-0.15.0-dev.1175+e4abdf5a1.tar.xz)
    const filename = std.fs.path.basename(latest_url);
    const version_start = std.mem.indexOf(u8, filename, "0.") orelse return true;
    const version_end = std.mem.indexOf(u8, filename[version_start..], ".tar") orelse return true;
    const latest_version = filename[version_start..version_start + version_end];
    
    // Check if we have this version installed
    const version_dir = try Platform.getInstallDir(allocator, "nightly");
    defer allocator.free(version_dir);
    
    // Check if the directory exists and contains the expected version
    var dir = std.fs.cwd().openDir(version_dir, .{}) catch return true; // Dir doesn't exist, update needed
    defer dir.close();
    
    // Look for zig executable that matches the version
    var walker = dir.walk(allocator) catch return true;
    defer walker.deinit();
    
    while (walker.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, "/zig")) {
            // Check if parent directory name contains the version
            const parent_dir = std.fs.path.dirname(entry.path) orelse continue;
            if (std.mem.indexOf(u8, parent_dir, latest_version) != null) {
                return false; // Found matching version, no update needed
            }
        }
    }
    
    return true; // No matching version found, update needed
}
