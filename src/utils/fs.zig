const std = @import("std");

/// Create a symbolic link, replacing any existing link at the target path
pub fn createSymlink(target: []const u8, link_path: []const u8) !void {
    std.fs.cwd().deleteFile(link_path) catch {};
    try std.posix.symlink(target, link_path);
}

/// Extract a tar.xz archive to the specified destination directory
pub fn extractTarXz(allocator: std.mem.Allocator, archive_path: []const u8, destination: []const u8) !void {
    std.fs.cwd().makePath(destination) catch |err| switch (err) {
        error.AccessDenied => {
            std.debug.print("Error: Permission denied creating directory: {s}\n", .{destination});
            std.debug.print("Please fix directory permissions or run: sudo chown -R $USER:$USER ~/bin\n", .{});
            return error.AccessDenied;
        },
        else => return err,
    };
    
    var process = std.process.Child.init(&[_][]const u8{
        "tar", "-xf", archive_path, "-C", destination, "--strip-components=1"
    }, allocator);
    
    const result = process.spawnAndWait() catch |err| {
        std.debug.print("Error: Failed to run tar command: {}\n", .{err});
        return err;
    };
    
    switch (result) {
        .Exited => |code| if (code != 0) {
            std.debug.print("Error: tar extraction failed with exit code: {}\n", .{code});
            return error.ExtractionFailed;
        },
        else => {
            std.debug.print("Error: tar command terminated unexpectedly\n", .{});
            return error.ExtractionFailed;
        },
    }
}

/// Download a file from URL to local filesystem
pub fn downloadFile(allocator: std.mem.Allocator, url: []const u8, destination: []const u8) !void {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    
    var buf: [8192]u8 = undefined;
    var req = try client.open(.GET, try std.Uri.parse(url), .{
        .server_header_buffer = &buf,
    });
    defer req.deinit();
    
    try req.send();
    try req.finish();
    try req.wait();
    
    const file = try std.fs.cwd().createFile(destination, .{});
    defer file.close();
    
    const writer = file.writer();
    var buf_reader = std.io.bufferedReader(req.reader());
    
    var buffer: [8192]u8 = undefined;
    while (true) {
        const bytes_read = try buf_reader.reader().read(&buffer);
        if (bytes_read == 0) break;
        try writer.writeAll(buffer[0..bytes_read]);
    }
}