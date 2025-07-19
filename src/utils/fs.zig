const std = @import("std");

/// Create a symbolic link, replacing any existing link at the target path
pub fn createSymlink(target: []const u8, link_path: []const u8) !void {
    std.fs.cwd().deleteFile(link_path) catch {};
    try std.posix.symlink(target, link_path);
}

/// Extract a tar.xz archive to the specified destination directory using native Zig implementation
pub fn extractTarXz(allocator: std.mem.Allocator, archive_path: []const u8, destination: []const u8) !void {
    // Create destination directory
    std.fs.cwd().makePath(destination) catch |err| switch (err) {
        error.AccessDenied => {
            std.debug.print("Error: Permission denied creating directory: {s}\n", .{destination});
            std.debug.print("Please fix directory permissions or run: sudo chown -R $USER:$USER ~/bin\n", .{});
            return error.AccessDenied;
        },
        else => return err,
    };
    
    // Read compressed archive
    const compressed_data = std.fs.cwd().readFileAlloc(allocator, archive_path, 1024 * 1024 * 100) catch |err| {
        std.debug.print("Error: Failed to read archive file: {}\n", .{err});
        return err;
    };
    defer allocator.free(compressed_data);
    
    // Decompress XZ stream
    var decompressed_stream = std.io.fixedBufferStream(compressed_data);
    var decompressor = std.compress.xz.decompress(allocator, decompressed_stream.reader()) catch |err| {
        std.debug.print("Error: Failed to decompress XZ archive: {}\n", .{err});
        return err;
    };
    defer decompressor.deinit();
    
    // Open destination directory
    const dest_dir = std.fs.cwd().openDir(destination, .{}) catch |err| {
        std.debug.print("Error: Failed to open destination directory: {}\n", .{err});
        return err;
    };
    
    // Extract TAR using std.tar with security features
    std.tar.pipeToFileSystem(dest_dir, decompressor.reader(), .{
        .strip_components = 1,
        .mode_mode = .executable_bit_only,
    }) catch |err| {
        std.debug.print("Error: TAR extraction failed: {}\n", .{err});
        return err;
    };
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