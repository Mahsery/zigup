/// ZigUp - Zig Version Manager
/// A command-line tool for managing multiple Zig installations
const std = @import("std");
const clap = @import("clap");

const update = @import("commands/update.zig");
const list = @import("commands/list.zig");
const install = @import("commands/install.zig");
const default = @import("commands/default.zig");
const remove = @import("commands/remove.zig");
const use = @import("commands/use.zig");
const validation = @import("utils/validation.zig");

const params = clap.parseParamsComptime(
    \\-h, --help             Display this help and exit.
    \\-v, --version          Display version and exit.
    \\<str>...
    \\
);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parsers = comptime .{
        .str = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| switch (err) {
        error.MissingValue => {
            try diag.report(std.io.getStdErr().writer(), err);
            return;
        },
        else => return err,
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try showHelp();
        return;
    }

    if (res.args.version != 0) {
        const version = @embedFile("version");
        try std.io.getStdOut().writer().print("zigup {s}\n", .{std.mem.trim(u8, version, " \n\r\t")});
        return;
    }

    if (res.positionals[0].len == 0) {
        try std.io.getStdErr().writer().print("Error: No command provided\n\n", .{});
        try showHelp();
        return;
    }

    const command = res.positionals[0][0];
    const args = res.positionals[0][1..];

    validateCommand(command) catch {
        try std.io.getStdErr().writer().print("Error: Unknown command '{s}'\n\n", .{command});
        try showHelp();
        return;
    };
    validateArguments(args) catch {
        try std.io.getStdErr().writer().print("Error: Invalid arguments provided\n", .{});
        return;
    };

    if (std.mem.eql(u8, command, "update")) {
        if (args.len > 0 and std.mem.eql(u8, args[0], "list")) {
            if (args.len > 1) {
                std.debug.print("Error: 'zigup update list' does not accept additional arguments\n", .{});
                std.debug.print("Usage: zigup update list\n", .{});
                return;
            }
            try update.showCachedVersions(allocator);
        } else {
            try update.run(allocator, args);
        }
    } else if (std.mem.eql(u8, command, "list")) {
        try list.run(allocator, args);
    } else if (std.mem.eql(u8, command, "install")) {
        try install.run(allocator, args);
    } else if (std.mem.eql(u8, command, "default")) {
        try default.run(allocator, args);
    } else if (std.mem.eql(u8, command, "remove")) {
        try remove.run(allocator, args);
    } else if (std.mem.eql(u8, command, "use")) {
        try use.run(allocator, args);
    } else if (std.mem.eql(u8, command, "self")) {
        if (args.len == 0 or !std.mem.eql(u8, args[0], "update")) {
            std.debug.print("Error: 'self' requires 'update' subcommand\n", .{});
            std.debug.print("Usage: zigup self update\n", .{});
            return;
        }
        try selfUpdate(allocator);
    } else {
        try std.io.getStdErr().writer().print("Error: Unknown command '{s}'\n\n", .{command});
        try showHelp();
    }
}

fn showHelp() !void {
    const stdout = std.io.getStdOut().writer();
    const version = @embedFile("version");
    try stdout.print("ZigUp - Zig Version Manager v{s}\n\n", .{std.mem.trim(u8, version, " \n\r\t")});
    try stdout.print("USAGE:\n", .{});
    try stdout.print("    zigup [OPTIONS] <COMMAND> [ARGS]\n\n", .{});
    try stdout.print("OPTIONS:\n", .{});
    try stdout.print("    -h, --help       Display this help and exit\n", .{});
    try stdout.print("    -v, --version    Display version and exit\n\n", .{});
    try stdout.print("COMMANDS:\n", .{});
    try stdout.print("    update           Fetch and cache version information\n", .{});
    try stdout.print("    update list      Show cached available versions\n", .{});
    try stdout.print("    list             Show installed Zig versions\n", .{});
    try stdout.print("    install <ver>    Download and install a Zig version\n", .{});
    try stdout.print("    default <ver>    Set default Zig version (auto-installs if needed)\n", .{});
    try stdout.print("    use <ver>        Set local Zig version for current project\n", .{});
    try stdout.print("    remove <ver>     Remove an installed Zig version\n", .{});
    try stdout.print("    self update      Update zigup to the latest version\n\n", .{});
    try stdout.print("EXAMPLES:\n", .{});
    try stdout.print("    zigup update\n", .{});
    try stdout.print("    zigup install 0.14.1\n", .{});
    try stdout.print("    zigup default nightly\n", .{});
    try stdout.print("    zigup use 0.14.1\n", .{});
    try stdout.print("    zigup list\n", .{});
    try stdout.print("    zigup remove 0.13.0\n", .{});
}

fn validateCommand(command: []const u8) !void {
    const valid_commands = [_][]const u8{ "update", "list", "install", "default", "remove", "use", "self" };
    for (valid_commands) |valid_cmd| {
        if (std.mem.eql(u8, command, valid_cmd)) return;
    }
    return error.InvalidCommand;
}

fn validateArguments(args: []const []const u8) !void {
    for (args) |arg| {
        if (arg.len > 256) return error.ArgumentTooLong;
        if (std.mem.indexOf(u8, arg, "\x00") != null) return error.NullByte;
    }
}

fn selfUpdate(allocator: std.mem.Allocator) !void {
    std.debug.print("Checking for zigup updates...\n", .{});
    
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    
    // Get latest release info from GitHub API
    var buf: [8192]u8 = undefined;
    const api_url = "https://api.github.com/repos/Mahsery/zigup/releases/latest";
    var req = try client.open(.GET, try std.Uri.parse(api_url), .{
        .server_header_buffer = &buf,
    });
    defer req.deinit();
    
    try req.send();
    try req.finish();
    try req.wait();
    
    const body = try req.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);
    
    // Parse JSON to get tag name and download URL
    const tag_name = try parseLatestTag(allocator, body);
    defer allocator.free(tag_name);
    
    // Get current version
    const current_version = @embedFile("version");
    const current_trimmed = std.mem.trim(u8, current_version, " \n\r\t");
    
    if (std.mem.eql(u8, current_trimmed, tag_name)) {
        std.debug.print("zigup is already up to date (version {s})\n", .{current_trimmed});
        return;
    }
    
    std.debug.print("New version available: {s} (current: {s})\n", .{tag_name, current_trimmed});
    std.debug.print("Downloading update...\n", .{});
    
    // Determine platform-specific binary name
    const platform_binary = getPlatformBinary();
    const download_url = try std.fmt.allocPrint(allocator, "https://github.com/Mahsery/zigup/releases/latest/download/{s}", .{platform_binary});
    defer allocator.free(download_url);
    
    // Download the new binary to a temp location
    const temp_path = try std.fmt.allocPrint(allocator, "/tmp/zigup-{d}", .{std.time.milliTimestamp()});
    defer allocator.free(temp_path);
    
    const fs_utils = @import("utils/fs.zig");
    try fs_utils.downloadFile(allocator, download_url, temp_path);
    
    // Make it executable
    const temp_file = try std.fs.cwd().openFile(temp_path, .{});
    defer temp_file.close();
    try temp_file.chmod(0o755);
    
    // Get current executable path
    const exe_path = try std.process.getSelfExePath(allocator);
    defer allocator.free(exe_path);
    
    // Replace current executable
    try std.fs.cwd().copyFile(temp_path, std.fs.cwd(), exe_path, .{});
    try std.fs.cwd().deleteFile(temp_path);
    
    std.debug.print("Successfully updated zigup to version {s}\n", .{tag_name});
}

fn parseLatestTag(allocator: std.mem.Allocator, json_body: []const u8) ![]u8 {
    // Simple JSON parsing to extract tag_name
    const tag_start = std.mem.indexOf(u8, json_body, "\"tag_name\":") orelse return error.TagNotFound;
    const quote_start = std.mem.indexOf(u8, json_body[tag_start..], "\"") orelse return error.TagNotFound;
    const value_start = tag_start + quote_start + 1;
    const next_quote = std.mem.indexOf(u8, json_body[value_start..], "\"") orelse return error.TagNotFound;
    const tag_name = json_body[value_start..value_start + next_quote];
    
    // Remove 'v' prefix if present
    const clean_tag = if (std.mem.startsWith(u8, tag_name, "v")) tag_name[1..] else tag_name;
    return try allocator.dupe(u8, clean_tag);
}

fn getPlatformBinary() []const u8 {
    const builtin = @import("builtin");
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => "zigup-linux-x86_64",
            .aarch64 => "zigup-linux-aarch64",
            else => "zigup-linux-x86_64",
        },
        .macos => switch (builtin.cpu.arch) {
            .x86_64 => "zigup-macos-x86_64",
            .aarch64 => "zigup-macos-aarch64",
            else => "zigup-macos-x86_64",
        },
        .windows => switch (builtin.cpu.arch) {
            .x86_64 => "zigup-windows-x86_64.exe",
            else => "zigup-windows-x86_64.exe",
        },
        else => "zigup-linux-x86_64",
    };
}
