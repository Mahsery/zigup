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
const ZigupError = @import("utils/errors.zig").ZigupError;
const HttpClient = @import("utils/http_client.zig").HttpClient;

const Command = enum {
    update,
    list,
    install,
    default,
    remove,
    use,
    self_update,
    
    fn fromString(str: []const u8) ?Command {
        const CommandMap = struct {
            name: []const u8,
            cmd: Command,
        };
        
        const commands = [_]CommandMap{
            .{ .name = "update", .cmd = .update },
            .{ .name = "list", .cmd = .list },
            .{ .name = "install", .cmd = .install },
            .{ .name = "default", .cmd = .default },
            .{ .name = "remove", .cmd = .remove },
            .{ .name = "use", .cmd = .use },
            .{ .name = "self", .cmd = .self_update },
        };
        
        for (commands) |entry| {
            if (std.mem.eql(u8, str, entry.name)) return entry.cmd;
        }
        return null;
    }
};

const params = clap.parseParamsComptime(
    \\-h, --help             Display this help and exit.
    \\-v, --version          Display version and exit.
    \\    --all              Show all (used with update list).
    \\<str>...
    \\
);

const update_params = clap.parseParamsComptime(
    \\-h, --help             Display help for update command.
    \\    --all              Show all available versions (use with list).
    \\<str>...
    \\
);

const self_params = clap.parseParamsComptime(
    \\-h, --help             Display help for self command.
    \\    update             Update zigup to latest version.
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

    const command_str = res.positionals[0][0];
    const args = res.positionals[0][1..];

    const command = Command.fromString(command_str) orelse {
        try std.io.getStdErr().writer().print("Error: Unknown command '{s}'\n\n", .{command_str});
        try showHelp();
        return;
    };

    try validateArguments(args);

    switch (command) {
        .update => try handleUpdateCommand(allocator, args, res.args.all != 0),
        .list => try list.run(allocator, args),
        .install => try install.run(allocator, args),
        .default => try default.run(allocator, args),
        .remove => try remove.run(allocator, args),
        .use => try use.run(allocator, args),
        .self_update => try handleSelfCommand(allocator, args),
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
    try stdout.print("    update list      Show cached available versions (top 5)\n", .{});
    try stdout.print("    update list --all Show all cached available versions\n", .{});
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


fn validateArguments(args: []const []const u8) !void {
    for (args) |arg| {
        if (arg.len > 256) return ZigupError.ArgumentTooLong;
        if (std.mem.indexOf(u8, arg, "\x00") != null) return ZigupError.InvalidArgument;
    }
}

fn selfUpdate(allocator: std.mem.Allocator) !void {
    std.debug.print("Checking for zigup updates...\n", .{});
    
    var http_client = HttpClient.init(allocator);
    defer http_client.deinit();
    
    // Get latest release info from GitHub API
    const api_url = "https://api.github.com/repos/Mahsery/zigup/releases/latest";
    const body = http_client.fetchJson(api_url) catch |err| {
        std.debug.print("Error: Failed to fetch release information: {}\n", .{err});
        return ZigupError.HttpRequestFailed;
    };
    defer allocator.free(body);
    
    // Parse JSON to get tag name and download URL
    const tag_name = parseLatestTag(allocator, body) catch |err| {
        std.debug.print("Error: Failed to parse release tag: {}\n", .{err});
        return ZigupError.TagNotFound;
    };
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
    
    http_client.downloadFile(download_url, temp_path) catch |err| {
        std.debug.print("Error: Failed to download update: {}\n", .{err});
        return ZigupError.DownloadFailed;
    };
    
    // Make it executable
    const temp_file = try std.fs.cwd().openFile(temp_path, .{});
    defer temp_file.close();
    try temp_file.chmod(0o755);
    
    // Get current executable path
    var exe_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&exe_path_buf);
    
    // Replace current executable
    try std.fs.cwd().copyFile(temp_path, std.fs.cwd(), exe_path, .{});
    try std.fs.cwd().deleteFile(temp_path);
    
    std.debug.print("Successfully updated zigup to version {s}\n", .{tag_name});
}

fn parseLatestTag(allocator: std.mem.Allocator, json_body: []const u8) ![]u8 {
    // Simple JSON parsing to extract tag_name
    const tag_start = std.mem.indexOf(u8, json_body, "\"tag_name\":") orelse return ZigupError.TagNotFound;
    const quote_start = std.mem.indexOf(u8, json_body[tag_start..], "\"") orelse return ZigupError.TagNotFound;
    const value_start = tag_start + quote_start + 1;
    const next_quote = std.mem.indexOf(u8, json_body[value_start..], "\"") orelse return ZigupError.TagNotFound;
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

fn handleUpdateCommand(allocator: std.mem.Allocator, args: []const []const u8, show_all: bool) !void {
    if (args.len == 0) {
        try update.run(allocator, args);
        return;
    }

    // Handle update subcommands
    if (args.len > 0 and std.mem.eql(u8, args[0], "list")) {
        if (show_all) {
            try update.showCachedVersionsWithLimit(allocator, null);
        } else {
            try update.showCachedVersions(allocator);
        }
    } else {
        try update.run(allocator, args);
    }
}

fn handleSelfCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: 'self' requires a subcommand\n", .{});
        try showSelfHelp();
        return;
    }

    var diag = clap.Diagnostic{};
    var self_res = clap.parse(clap.Help, &self_params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| switch (err) {
        error.MissingValue => {
            try diag.report(std.io.getStdErr().writer(), err);
            return;
        },
        else => return err,
    };
    defer self_res.deinit();

    if (self_res.args.help != 0) {
        try showSelfHelp();
        return;
    }

    // Check for 'update' subcommand
    if (std.mem.eql(u8, args[0], "update")) {
        try selfUpdate(allocator);
    } else {
        std.debug.print("Error: Unknown self subcommand '{s}'\n", .{args[0]});
        try showSelfHelp();
    }
}

fn showUpdateHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("zigup update - Fetch and cache version information\n\n", .{});
    try stdout.print("USAGE:\n", .{});
    try stdout.print("    zigup update [SUBCOMMAND]\n\n", .{});
    try stdout.print("SUBCOMMANDS:\n", .{});
    try stdout.print("    list    Show cached available versions\n", .{});
}

fn showSelfHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("zigup self - Manage zigup itself\n\n", .{});
    try stdout.print("USAGE:\n", .{});
    try stdout.print("    zigup self <SUBCOMMAND>\n\n", .{});
    try stdout.print("SUBCOMMANDS:\n", .{});
    try stdout.print("    update    Update zigup to the latest version\n", .{});
}
