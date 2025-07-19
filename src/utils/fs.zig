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
    
    // Extract TAR with path traversal protection
    try extractTarWithValidation(allocator, dest_dir, decompressor.reader());
}

/// Extract TAR archive with path traversal validation
fn extractTarWithValidation(allocator: std.mem.Allocator, dest_dir: std.fs.Dir, reader: anytype) !void {
    var file_name_buffer: [256]u8 = undefined;
    var link_name_buffer: [256]u8 = undefined;
    var tar_iterator = std.tar.iterator(reader, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });
    
    while (try tar_iterator.next()) |entry| {
        // Validate the entry path for security
        const safe_path = try validateAndSanitizePath(allocator, entry.name);
        defer allocator.free(safe_path);
        
        // Skip if path is unsafe
        if (safe_path.len == 0) {
            std.debug.print("Warning: Skipping unsafe path in archive: {s}\n", .{entry.name});
            continue;
        }
        
        switch (entry.kind) {
            .file => {
                // Create any necessary parent directories
                if (std.fs.path.dirname(safe_path)) |parent_dir| {
                    dest_dir.makePath(parent_dir) catch {};
                }
                
                // Create and write the file
                const file = try dest_dir.createFile(safe_path, .{});
                defer file.close();
                
                var buf: [8192]u8 = undefined;
                while (true) {
                    const bytes_read = try entry.reader().readAll(&buf);
                    if (bytes_read == 0) break;
                    try file.writeAll(buf[0..bytes_read]);
                }
                
                // Set executable bit if needed (basic implementation)
                if (std.mem.endsWith(u8, safe_path, "zig")) {
                    file.chmod(0o755) catch {};
                }
            },
            .directory => {
                dest_dir.makePath(safe_path) catch {};
            },
            else => {
                // Skip symlinks, devices, etc. for security
                std.debug.print("Warning: Skipping unsupported entry type in archive: {s}\n", .{entry.name});
            },
        }
    }
}

/// Validate and sanitize a tar entry path to prevent path traversal attacks
fn validateAndSanitizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // Reject absolute paths
    if (std.fs.path.isAbsolute(path)) {
        return allocator.dupe(u8, ""); // Return empty string to indicate rejection
    }
    
    // Reject paths with traversal attempts
    if (std.mem.indexOf(u8, path, "..") != null) {
        return allocator.dupe(u8, ""); // Return empty string to indicate rejection
    }
    
    // Strip the first component (equivalent to strip_components = 1)
    var it = std.mem.splitScalar(u8, path, '/');
    _ = it.first(); // Skip first component
    
    var sanitized = std.ArrayList(u8).init(allocator);
    defer sanitized.deinit();
    
    var first = true;
    while (it.next()) |component| {
        // Skip empty components and single dots
        if (component.len == 0 or std.mem.eql(u8, component, ".")) {
            continue;
        }
        
        // Reject any remaining traversal attempts
        if (std.mem.eql(u8, component, "..")) {
            return allocator.dupe(u8, ""); // Return empty string to indicate rejection
        }
        
        if (!first) {
            try sanitized.append('/');
        }
        try sanitized.appendSlice(component);
        first = false;
    }
    
    return sanitized.toOwnedSlice();
}

/// Download a file from URL to local filesystem
pub fn downloadFile(allocator: std.mem.Allocator, url: []const u8, destination: []const u8) !void {
    try validateUrl(url);
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

pub fn validateUrl(url: []const u8) !void {
    const uri = std.Uri.parse(url) catch return error.InvalidUrl;
    
    if (!std.mem.eql(u8, uri.scheme, "https")) {
        return error.UnsafeUrlScheme;
    }
    
    if (uri.host) |host| {
        const host_str = switch (host) {
            .raw => |raw| raw,
            .percent_encoded => |encoded| encoded,
        };
        if (!std.mem.eql(u8, host_str, "ziglang.org")) {
            return error.UntrustedDomain;
        }
    } else {
        return error.MissingHost;
    }
}