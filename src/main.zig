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
const Platform = @import("utils/platform.zig");
const output = @import("utils/output.zig");

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
    const version = @embedFile("version");
    try output.printOut("ZigUp - Zig Version Manager v{s}\n\n", .{std.mem.trim(u8, version, " \n\r\t")});
    try output.printOut("USAGE:\n", .{});
    try output.printOut("    zigup [OPTIONS] <COMMAND> [ARGS]\n\n", .{});
    try output.printOut("OPTIONS:\n", .{});
    try output.printOut("    -h, --help       Display this help and exit\n", .{});
    try output.printOut("    -v, --version    Display version and exit\n\n", .{});
    try output.printOut("COMMANDS:\n", .{});
    try output.printOut("    update           Fetch and cache version information\n", .{});
    try output.printOut("    update list      Show cached available versions (top 5)\n", .{});
    try output.printOut("    update list --all Show all cached available versions\n", .{});
    try output.printOut("    list             Show installed Zig versions\n", .{});
    try output.printOut("    install <ver>    Download and install a Zig version\n", .{});
    try output.printOut("    default <ver>    Set default Zig version (auto-installs if needed)\n", .{});
    try output.printOut("    use <ver>        Set local Zig version for current project\n", .{});
    try output.printOut("    remove <ver>     Remove an installed Zig version\n", .{});
    try output.printOut("    self update      Update zigup to the latest version\n\n", .{});
    try output.printOut("DIRECTORIES:\n", .{});
    try printDirectoryInfo();
    try output.printOut("\nEXAMPLES:\n", .{});
    try output.printOut("    zigup update\n", .{});
    try output.printOut("    zigup install 0.14.1\n", .{});
    try output.printOut("    zigup default nightly\n", .{});
    try output.printOut("    zigup use 0.14.1\n", .{});
    try output.printOut("    zigup list\n", .{});
    try output.printOut("    zigup remove 0.13.0\n", .{});
}

fn printDirectoryInfo() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Installation directory
    const install_base = Platform.Platform.getBinBaseDir(allocator) catch "~/bin";
    defer if (!std.mem.eql(u8, install_base, "~/bin")) allocator.free(install_base);
    try output.printOut("    Installations:   {s}/<version>/     (Zig versions installed here)\n", .{install_base});

    // Wrapper/symlink directory
    const bin_dir = Platform.Platform.getBinDir(allocator) catch "~/.local/bin";
    defer if (!std.mem.eql(u8, bin_dir, "~/.local/bin")) allocator.free(bin_dir);
    try output.printOut("    Wrapper:         {s}/zig             (Main zig command)\n", .{bin_dir});

    // Cache directory
    const cache_dir = Platform.Platform.getCacheDir(allocator) catch blk: {
        const builtin = @import("builtin");
        break :blk switch (builtin.os.tag) {
            .windows => "~/AppData/Local/zigup",
            else => "~/.cache/zigup",
        };
    };
    defer if (!std.mem.eql(u8, cache_dir, "~/.cache/zigup") and !std.mem.eql(u8, cache_dir, "~/AppData/Local/zigup")) allocator.free(cache_dir);
    try output.printOut("    Cache:           {s}/                (Version info & downloads)\n", .{cache_dir});
    try output.printOut("    Local Config:    ./.zig-version       (Project-specific version)\n", .{});
}

fn validateArguments(args: []const []const u8) !void {
    for (args) |arg| {
        if (arg.len > 256) return ZigupError.ArgumentTooLong;
        if (std.mem.indexOf(u8, arg, "\x00") != null) return ZigupError.InvalidArgument;
    }
}

fn selfUpdate(allocator: std.mem.Allocator) !void {
    try output.printOut("Checking for zigup updates...\n", .{});

    var http_client = HttpClient.init(allocator);
    defer http_client.deinit();

    // Get latest release info from GitHub API (including prereleases)
    const api_url = "https://api.github.com/repos/Mahsery/zigup/releases?per_page=1";
    const body = http_client.fetchJson(api_url) catch |err| {
        try output.printErr("Error: Failed to fetch release information: {}\n", .{err});
        return ZigupError.HttpRequestFailed;
    };
    defer allocator.free(body);

    // Parse JSON to get tag name and download URL
    const tag_name = parseLatestTag(allocator, body) catch |err| {
        try output.printErr("Error: Failed to parse release tag: {}\n", .{err});
        return ZigupError.TagNotFound;
    };
    defer allocator.free(tag_name);

    // Get current version
    const current_version = @embedFile("version");
    const current_trimmed = std.mem.trim(u8, current_version, " \n\r\t");

    if (std.mem.eql(u8, current_trimmed, tag_name)) {
        try output.printOut("zigup is already up to date (version {s})\n", .{current_trimmed});
        return;
    }

    try output.printOut("New version available: {s} (current: {s})\n", .{ tag_name, current_trimmed });
    try output.printOut("Downloading update...\n", .{});

    // Determine platform-specific binary name and build download URL from release tag
    const platform_binary = getPlatformBinary();
    const download_url = try std.fmt.allocPrint(allocator, "https://github.com/Mahsery/zigup/releases/download/v{s}/{s}", .{ tag_name, platform_binary });
    defer allocator.free(download_url);

    // Download the new binary to a temp location
    const temp_path = try std.fmt.allocPrint(allocator, "/tmp/zigup-{d}", .{std.time.milliTimestamp()});
    defer allocator.free(temp_path);

    http_client.downloadFile(download_url, temp_path) catch |err| {
        try output.printErr("Error: Failed to download update: {}\n", .{err});
        return ZigupError.DownloadFailed;
    };

    // Make it executable (Unix-like systems only)
    if (std.fs.has_executable_bit) {
        const temp_file = try std.fs.cwd().openFile(temp_path, .{});
        defer temp_file.close();
        try temp_file.chmod(0o755);
    }

    // Get current executable path
    var exe_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&exe_path_buf);

    // Replace current executable
    try std.fs.cwd().copyFile(temp_path, std.fs.cwd(), exe_path, .{});
    try std.fs.cwd().deleteFile(temp_path);

    try output.printOut("Successfully updated zigup to version {s}\n", .{tag_name});
}

fn parseLatestTag(allocator: std.mem.Allocator, json_body: []const u8) ![]u8 {
    // Parse array response and get first release tag_name
    const tag_start = std.mem.indexOf(u8, json_body, "\"tag_name\":\"") orelse return ZigupError.TagNotFound;
    const value_start = tag_start + 12; // Skip "tag_name":"
    const next_quote = std.mem.indexOf(u8, json_body[value_start..], "\"") orelse return ZigupError.TagNotFound;
    const tag_name = json_body[value_start .. value_start + next_quote];

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
        .macos => "zigup-macos-aarch64",
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
        try output.printErr("Error: 'self' requires a subcommand\n", .{});
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
        try output.printErr("Error: Unknown self subcommand '{s}'\n", .{args[0]});
        try showSelfHelp();
    }
}

fn showUpdateHelp() !void {
    try output.printOut("zigup update - Fetch and cache version information\n\n", .{});
    try output.printOut("USAGE:\n", .{});
    try output.printOut("    zigup update [SUBCOMMAND]\n\n", .{});
    try output.printOut("SUBCOMMANDS:\n", .{});
    try output.printOut("    list    Show cached available versions\n", .{});
}

fn showSelfHelp() !void {
    try output.printOut("zigup self - Manage zigup itself\n\n", .{});
    try output.printOut("USAGE:\n", .{});
    try output.printOut("    zigup self <SUBCOMMAND>\n\n", .{});
    try output.printOut("SUBCOMMANDS:\n", .{});
    try output.printOut("    update    Update zigup to the latest version\n", .{});
}
