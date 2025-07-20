/// ZigUp - Zig Version Manager
/// A command-line tool for managing multiple Zig installations
const std = @import("std");
const clap = @import("clap");

const update = @import("commands/update.zig");
const list = @import("commands/list.zig");
const install = @import("commands/install.zig");
const default = @import("commands/default.zig");
const remove = @import("commands/remove.zig");
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
    try stdout.print("    remove <ver>     Remove an installed Zig version\n\n", .{});
    try stdout.print("EXAMPLES:\n", .{});
    try stdout.print("    zigup update\n", .{});
    try stdout.print("    zigup install 0.14.1\n", .{});
    try stdout.print("    zigup default nightly\n", .{});
    try stdout.print("    zigup list\n", .{});
    try stdout.print("    zigup remove 0.13.0\n", .{});
}

fn validateCommand(command: []const u8) !void {
    const valid_commands = [_][]const u8{ "update", "list", "install", "default", "remove" };
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
