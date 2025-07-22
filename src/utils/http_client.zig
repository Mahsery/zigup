const std = @import("std");
const errors = @import("errors.zig");
const ZigupError = errors.ZigupError;
const output = @import("output.zig");

/// Reusable HTTP client with common operations
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    /// Download data from URL and return as string
    pub fn fetchString(self: *Self, url: []const u8) ![]u8 {
        try validateUrl(url);

        var buf: [8192]u8 = undefined;
        var req = self.client.open(.GET, try std.Uri.parse(url), .{
            .server_header_buffer = &buf,
        }) catch |err| {
            return errors.fromSystemError(err);
        };
        defer req.deinit();

        req.send() catch |err| {
            return errors.fromSystemError(err);
        };
        req.finish() catch |err| {
            return errors.fromSystemError(err);
        };
        req.wait() catch |err| {
            return errors.fromSystemError(err);
        };

        if (req.response.status != .ok) {
            try output.printErr("HTTP Error: {}\n", .{req.response.status});
            return ZigupError.HttpRequestFailed;
        }

        const body = req.reader().readAllAlloc(self.allocator, 1024 * 1024) catch |err| {
            return errors.fromSystemError(err);
        };

        return body;
    }

    /// Download file from URL to specified path
    pub fn downloadFile(self: *Self, url: []const u8, file_path: []const u8) !void {
        try validateUrl(url);

        var buf: [8192]u8 = undefined;
        var req = self.client.open(.GET, try std.Uri.parse(url), .{
            .server_header_buffer = &buf,
        }) catch |err| {
            return errors.fromSystemError(err);
        };
        defer req.deinit();

        req.send() catch |err| {
            return errors.fromSystemError(err);
        };
        req.finish() catch |err| {
            return errors.fromSystemError(err);
        };
        req.wait() catch |err| {
            return errors.fromSystemError(err);
        };

        if (req.response.status != .ok) {
            try output.printErr("HTTP Error: {}\n", .{req.response.status});
            return ZigupError.HttpRequestFailed;
        }

        // Ensure parent directory exists
        if (std.fs.path.dirname(file_path)) |parent_dir| {
            std.fs.cwd().makePath(parent_dir) catch |err| {
                return errors.fromSystemError(err);
            };
        }

        // Create file and write content
        var file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
            return errors.fromSystemError(err);
        };
        defer file.close();

        // Stream download to file
        var buffer: [4096]u8 = undefined;
        while (true) {
            const bytes_read = req.reader().read(&buffer) catch |err| {
                return errors.fromSystemError(err);
            };
            if (bytes_read == 0) break;

            file.writeAll(buffer[0..bytes_read]) catch |err| {
                return errors.fromSystemError(err);
            };
        }
    }

    /// Fetch JSON data and return as string for further processing
    pub fn fetchJson(self: *Self, url: []const u8) ![]u8 {
        const data = try self.fetchString(url);

        // Basic JSON validation
        if (data.len == 0 or (data[0] != '{' and data[0] != '[')) {
            self.allocator.free(data);
            return ZigupError.JsonParseError;
        }

        return data;
    }

    /// Check if URL is reachable (HEAD request)
    pub fn checkUrl(self: *Self, url: []const u8) !bool {
        try validateUrl(url);

        var buf: [8192]u8 = undefined;
        var req = self.client.open(.HEAD, try std.Uri.parse(url), .{
            .server_header_buffer = &buf,
        }) catch {
            return false;
        };
        defer req.deinit();

        req.send() catch {
            return false;
        };
        req.finish() catch {
            return false;
        };
        req.wait() catch {
            return false;
        };

        return req.response.status == .ok;
    }
};

/// Validate URL format
fn validateUrl(url: []const u8) !void {
    if (url.len == 0) return ZigupError.InvalidUrl;

    if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) {
        return ZigupError.InvalidUrl;
    }

    // Basic validation for suspicious characters
    for (url) |c| {
        switch (c) {
            0...31, 127...255 => return ZigupError.InvalidUrl, // Control characters
            ' ', '"', '<', '>', '\\', '^', '`', '{', '|', '}' => return ZigupError.InvalidUrl, // Unsafe characters
            else => {},
        }
    }

    // Check for minimum length and basic structure
    if (url.len < 10) return ZigupError.InvalidUrl; // Minimum: "http://a.b"

    const without_protocol = if (std.mem.startsWith(u8, url, "https://"))
        url[8..]
    else
        url[7..]; // http://

    if (std.mem.indexOf(u8, without_protocol, ".") == null) {
        return ZigupError.InvalidUrl; // No domain
    }
}
