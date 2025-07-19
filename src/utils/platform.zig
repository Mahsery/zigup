const std = @import("std");
const builtin = @import("builtin");

/// Platform-specific configuration and utilities
pub const Platform = struct {
    os: std.Target.Os.Tag,
    
    pub fn current() Platform {
        return Platform{ .os = builtin.os.tag };
    }
    
    /// Get the user's home directory with allocator (cross-platform)
    pub fn getHomeDirAlloc(allocator: std.mem.Allocator) ![]u8 {
        return switch (builtin.os.tag) {
            .windows => std.process.getEnvVarOwned(allocator, "USERPROFILE") catch return error.NoHomeDir,
            else => std.process.getEnvVarOwned(allocator, "HOME") catch return error.NoHomeDir,
        };
    }
    
    /// Get platform-specific installation directory relative to home
    pub fn getInstallDir(allocator: std.mem.Allocator, version: []const u8) ![]u8 {
        const home = try getHomeDirAlloc(allocator);
        defer allocator.free(home);
        return switch (builtin.os.tag) {
            .windows => try std.fs.path.join(allocator, &.{ home, "bin", version }),
            else => try std.fs.path.join(allocator, &.{ home, "bin", version }),
        };
    }
    
    /// Get platform-specific binary directory for symlinks/wrappers
    pub fn getBinDir(allocator: std.mem.Allocator) ![]u8 {
        const home = try getHomeDirAlloc(allocator);
        defer allocator.free(home);
        return switch (builtin.os.tag) {
            .windows => try std.fs.path.join(allocator, &.{ home, ".local", "bin" }),
            else => try std.fs.path.join(allocator, &.{ home, ".local", "bin" }),
        };
    }
    
    /// Get platform-specific cache directory
    pub fn getCacheDir(allocator: std.mem.Allocator) ![]u8 {
        const home = try getHomeDirAlloc(allocator);
        defer allocator.free(home);
        return switch (builtin.os.tag) {
            .windows => try std.fs.path.join(allocator, &.{ home, "AppData", "Local", "zigup" }),
            else => try std.fs.path.join(allocator, &.{ home, ".cache", "zigup" }),
        };
    }
    
    /// Get the executable name with platform-specific extension
    pub fn getExecutableName(allocator: std.mem.Allocator, base_name: []const u8) ![]u8 {
        return switch (builtin.os.tag) {
            .windows => try std.fmt.allocPrint(allocator, "{s}.exe", .{base_name}),
            else => try allocator.dupe(u8, base_name),
        };
    }
    
    /// Get platform-specific archive file extension
    pub fn getArchiveExtension() []const u8 {
        return switch (builtin.os.tag) {
            .windows => ".zip",
            else => ".tar.xz",
        };
    }
    
    /// Create version symlink or wrapper script
    pub fn createVersionLink(allocator: std.mem.Allocator, version_path: []const u8, link_path: []const u8) !void {
        switch (builtin.os.tag) {
            .windows => {
                // Create batch wrapper instead of symlink
                const wrapper_content = try std.fmt.allocPrint(allocator, 
                    "@echo off\r\n\"{s}\" %*\r\n", .{version_path});
                defer allocator.free(wrapper_content);
                
                const wrapper_path = try std.fmt.allocPrint(allocator, "{s}.bat", .{link_path});
                defer allocator.free(wrapper_path);
                
                try std.fs.cwd().writeFile(.{ .sub_path = wrapper_path, .data = wrapper_content });
            },
            else => {
                // Use atomic symlink replacement on Unix systems to prevent TOCTOU attacks
                const temp_link = try std.fmt.allocPrint(allocator, "{s}.tmp.{d}", .{ link_path, std.time.milliTimestamp() });
                defer allocator.free(temp_link);
                
                // Create symlink with temporary name first
                try std.posix.symlink(version_path, temp_link);
                
                // Atomically replace the old symlink
                std.fs.cwd().rename(temp_link, link_path) catch |err| {
                    // Clean up temp link if rename fails
                    std.fs.cwd().deleteFile(temp_link) catch {};
                    return err;
                };
            },
        }
    }
    
    /// Remove version symlink or wrapper script
    pub fn removeVersionLink(link_path: []const u8) !void {
        switch (builtin.os.tag) {
            .windows => {
                // Remove batch wrapper
                var buf: [256]u8 = undefined;
                const wrapper_path = try std.fmt.bufPrint(buf[0..], "{s}.bat", .{link_path});
                
                std.fs.cwd().deleteFile(wrapper_path) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => return err,
                };
            },
            else => {
                // Remove symlink
                std.fs.cwd().deleteFile(link_path) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => return err,
                };
            },
        }
    }
    
    /// Get platform-specific PATH environment instructions
    pub fn getPathInstructions(allocator: std.mem.Allocator, bin_dir: []const u8) ![]u8 {
        return switch (builtin.os.tag) {
            .windows => try std.fmt.allocPrint(allocator, 
                "Add to PATH (run as Administrator):\r\n  setx PATH \"{s};%PATH%\"", .{bin_dir}),
            else => try std.fmt.allocPrint(allocator, 
                "Add to PATH:\n  export PATH=\"{s}:$PATH\"", .{bin_dir}),
        };
    }
    
    /// Get platform string for ziglang.org downloads
    pub fn getPlatformString() []const u8 {
        return switch (builtin.os.tag) {
            .windows => switch (builtin.cpu.arch) {
                .x86_64 => "x86_64-windows",
                .aarch64 => "aarch64-windows",
                else => "x86_64-windows", // fallback
            },
            .linux => switch (builtin.cpu.arch) {
                .x86_64 => "x86_64-linux",
                .aarch64 => "aarch64-linux",
                else => "x86_64-linux", // fallback
            },
            .macos => switch (builtin.cpu.arch) {
                .x86_64 => "x86_64-macos",
                .aarch64 => "aarch64-macos",
                else => "x86_64-macos", // fallback
            },
            else => "x86_64-linux", // fallback for unknown platforms
        };
    }
};