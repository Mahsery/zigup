/// ZigUp - Zig Version Manager
/// A command-line tool for managing multiple Zig installations
const std = @import("std");
const clap = @import("clap");

const update = @import("commands/update.zig");
const list = @import("commands/list.zig");
const install = @import("commands/install.zig");
const default = @import("commands/default.zig");

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
        try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        return;
    }

    if (res.args.version != 0) {
        try std.io.getStdOut().writer().print("zigup 0.1.0\n", .{});
        return;
    }

    if (res.positionals[0].len == 0) {
        try std.io.getStdErr().writer().print("Error: No command provided\n", .{});
        try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        return;
    }

    const command = res.positionals[0][0];
    const args = res.positionals[0][1..];

    if (std.mem.eql(u8, command, "update")) {
        if (args.len > 0 and std.mem.eql(u8, args[0], "list")) {
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
    } else {
        try std.io.getStdErr().writer().print("Error: Unknown command '{s}'\n", .{command});
        try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }
}
