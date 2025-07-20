const std = @import("std");
const use = @import("use.zig");
const Platform = @import("../utils/platform.zig").Platform;

/// Create a zig wrapper that respects local .zig-version files
pub fn createWrapper(allocator: std.mem.Allocator) !void {
    const bin_dir = try Platform.getBinDir(allocator);
    defer allocator.free(bin_dir);

    try std.fs.cwd().makePath(bin_dir);

    const wrapper_path = try std.fs.path.join(allocator, &.{ bin_dir, "zig" });
    defer allocator.free(wrapper_path);

    switch (@import("builtin").os.tag) {
        .windows => try createWindowsWrapper(allocator, wrapper_path),
        else => try createUnixWrapper(allocator, wrapper_path),
    }

    std.debug.print("Created zig wrapper at: {s}\n", .{wrapper_path});
}

fn createWindowsWrapper(allocator: std.mem.Allocator, wrapper_path: []const u8) !void {
    const bat_path = try std.fmt.allocPrint(allocator, "{s}.bat", .{wrapper_path});
    defer allocator.free(bat_path);

    const wrapper_content = 
        \\@echo off
        \\setlocal enabledelayedexpansion
        \\
        \\REM Check for .zig-version file in current directory and parent directories
        \\set "current_dir=%cd%"
        \\:search_loop
        \\if exist "%current_dir%\.zig-version" (
        \\    set /p local_version=<"%current_dir%\.zig-version"
        \\    set "local_version=!local_version: =!"
        \\    if not "!local_version!"=="" (
        \\        set "zig_path=%USERPROFILE%\bin\!local_version!\zig.exe"
        \\        if exist "!zig_path!" (
        \\            "!zig_path!" %*
        \\            exit /b %errorlevel%
        \\        )
        \\    )
        \\)
        \\
        \\REM Move up one directory
        \\for %%i in ("%current_dir%") do set "parent_dir=%%~dpi"
        \\set "parent_dir=%parent_dir:~0,-1%"
        \\if "%current_dir%"=="%parent_dir%" goto use_default
        \\set "current_dir=%parent_dir%"
        \\goto search_loop
        \\
        \\:use_default
        \\REM Use default zig if no local version found
        \\set "default_zig=%USERPROFILE%\.local\bin\zig-default.exe"
        \\if exist "%default_zig%" (
        \\    "%default_zig%" %*
        \\) else (
        \\    echo Error: No default zig version set. Run 'zigup default ^<version^>' first.
        \\    exit /b 1
        \\)
    ;

    try std.fs.cwd().writeFile(.{ .sub_path = bat_path, .data = wrapper_content });
}

fn createUnixWrapper(_: std.mem.Allocator, wrapper_path: []const u8) !void {
    // Remove existing file/symlink first
    std.fs.cwd().deleteFile(wrapper_path) catch |err| switch (err) {
        error.FileNotFound => {}, // OK if file doesn't exist
        else => return err,
    };

    const wrapper_content = 
        \\#!/bin/bash
        \\
        \\# Check for .zig-version file in current directory and parent directories
        \\find_local_version() {
        \\    local dir="$PWD"
        \\    while [[ "$dir" != "/" ]]; do
        \\        if [[ -f "$dir/.zig-version" ]]; then
        \\            local version=$(cat "$dir/.zig-version" | tr -d ' \n\r\t')
        \\            if [[ -n "$version" ]]; then
        \\                local zig_path="$HOME/bin/$version/zig"
        \\                if [[ -x "$zig_path" ]]; then
        \\                    exec "$zig_path" "$@"
        \\                fi
        \\            fi
        \\        fi
        \\        dir=$(dirname "$dir")
        \\    done
        \\}
        \\
        \\# Try to find and use local version
        \\find_local_version "$@"
        \\
        \\# Use default zig if no local version found
        \\default_version_file="$HOME/.local/bin/.zig-default-version"
        \\if [[ -f "$default_version_file" ]]; then
        \\    default_version=$(cat "$default_version_file" | tr -d ' \n\r\t')
        \\    default_zig="$HOME/bin/$default_version/zig"
        \\    if [[ -x "$default_zig" ]]; then
        \\        exec "$default_zig" "$@"
        \\    fi
        \\fi
        \\
        \\echo "Error: No default zig version set. Run 'zigup default <version>' first." >&2
        \\exit 1
    ;

    try std.fs.cwd().writeFile(.{ .sub_path = wrapper_path, .data = wrapper_content });
    
    // Make the wrapper executable
    const file = try std.fs.cwd().openFile(wrapper_path, .{});
    defer file.close();
    try file.chmod(0o755);
}

/// Update the default command to write version to file
pub fn updateDefaultCommand(allocator: std.mem.Allocator, version: []const u8) !void {
    const bin_dir = try Platform.getBinDir(allocator);
    defer allocator.free(bin_dir);

    const version_file_path = try std.fs.path.join(allocator, &.{ bin_dir, ".zig-default-version" });
    defer allocator.free(version_file_path);

    const file = try std.fs.cwd().createFile(version_file_path, .{});
    defer file.close();
    try file.writeAll(version);
}