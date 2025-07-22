const std = @import("std");
const builtin = @import("builtin");
const zimdjson = @import("zimdjson");

const GITHUB_RELEASES_URL = "https://api.github.com/repos/Mahsery/zigup/releases?per_page=1";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing installer API calls...\n", .{});

    // Test what binary name we're looking for
    const binary_name = getBinaryName();
    std.debug.print("Looking for binary: '{s}'\n", .{binary_name});

    // Test API call
    std.debug.print("Fetching from: {s}\n", .{GITHUB_RELEASES_URL});

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var buf: [8192]u8 = undefined;
    var req = client.open(.GET, try std.Uri.parse(GITHUB_RELEASES_URL), .{
        .server_header_buffer = &buf,
        .headers = .{
            .user_agent = .{ .override = "zigup-installer-test/1.0" },
        },
    }) catch |err| {
        std.debug.print("Failed to open request: {}\n", .{err});
        return;
    };
    defer req.deinit();

    req.send() catch |err| {
        std.debug.print("Failed to send request: {}\n", .{err});
        return;
    };
    req.finish() catch |err| {
        std.debug.print("Failed to finish request: {}\n", .{err});
        return;
    };
    req.wait() catch |err| {
        std.debug.print("Failed to wait for request: {}\n", .{err});
        return;
    };

    std.debug.print("HTTP Status: {}\n", .{req.response.status});

    const body = req.reader().readAllAlloc(allocator, 1024 * 1024) catch |err| {
        std.debug.print("Failed to read response: {}\n", .{err});
        return;
    };
    defer allocator.free(body);

    std.debug.print("Response length: {} bytes\n", .{body.len});

    // Try to parse JSON
    std.debug.print("Parsing JSON...\n", .{});

    const Parser = zimdjson.dom.StreamParser(.default);
    var parser = Parser.init;
    defer parser.deinit(allocator);
    var json_slice = std.io.fixedBufferStream(body);
    const document = parser.parseFromReader(allocator, json_slice.reader().any()) catch |err| {
        std.debug.print("JSON parsing failed: {}\n", .{err});
        std.debug.print("First 500 chars of response:\n{s}\n", .{body[0..@min(500, body.len)]});
        return;
    };

    // Get the first release from the releases array
    const releases_array = document.asArray() catch |err| {
        std.debug.print("Failed to get releases array: {}\n", .{err});
        return;
    };

    var releases_iter = releases_array.iterator();
    const first_release = releases_iter.next() orelse {
        std.debug.print("No releases found in array\n", .{});
        return;
    };

    std.debug.print("Found first release\n", .{});

    // Get the assets array from the first release
    const assets = first_release.at("assets");
    const assets_array = assets.asArray() catch |err| {
        std.debug.print("Failed to get assets array: {}\n", .{err});
        return;
    };

    std.debug.print("Assets found, listing them...\n", .{});

    // List all available assets
    var iter = assets_array.iterator();
    var asset_count: u32 = 0;
    while (iter.next()) |asset| {
        const name = asset.at("name").asString() catch "unknown";
        std.debug.print("  Asset {}: '{s}'\n", .{ asset_count, name });
        asset_count += 1;

        // Check if this matches what we're looking for
        if (std.mem.eql(u8, name, binary_name)) {
            std.debug.print("  ✓ MATCH FOUND!\n", .{});
            const download_url = asset.at("browser_download_url").asString() catch "unknown";
            std.debug.print("  Download URL: {s}\n", .{download_url});
            return;
        }
    }

    std.debug.print("❌ No matching asset found for '{s}'\n", .{binary_name});
}

fn getBinaryName() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "zigup-windows-x86_64.exe",
        .linux => "zigup-linux-x86_64",
        .macos => "zigup-macos-aarch64",
        else => "zigup-linux-x86_64",
    };
}
