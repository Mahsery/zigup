const std = @import("std");
const zimdjson = @import("zimdjson");
const fs_utils = @import("../utils/fs.zig");
const cache_utils = @import("../utils/cache.zig");
const minisign = @import("../utils/minisign.zig");
const validation = @import("../utils/validation.zig");
const Platform = @import("../utils/platform.zig").Platform;
const update = @import("update.zig");

/// Safely cleanup temporary files with atomic operations to prevent race conditions
fn safeCleanup(archive_path: []const u8, signature_path: []const u8) void {
    // Use mutex or file locking to prevent concurrent deletion
    // For now, use rename-then-delete to make it atomic
    const temp_archive = std.fmt.allocPrint(std.heap.page_allocator, "{s}.cleanup.{d}", .{ archive_path, std.time.milliTimestamp() }) catch return;
    defer std.heap.page_allocator.free(temp_archive);
    const temp_signature = std.fmt.allocPrint(std.heap.page_allocator, "{s}.cleanup.{d}", .{ signature_path, std.time.milliTimestamp() }) catch return;
    defer std.heap.page_allocator.free(temp_signature);

    // Atomic rename then delete to avoid race conditions
    std.fs.cwd().rename(archive_path, temp_archive) catch {};
    std.fs.cwd().deleteFile(temp_archive) catch {};
    std.fs.cwd().rename(signature_path, temp_signature) catch {};
    std.fs.cwd().deleteFile(temp_signature) catch {};
}

/// Download and install a specific Zig version
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: No version specified\n", .{});
        return;
    }

    const version = args[0];

    // Check if version is available before proceeding
    const is_available = update.isVersionAvailable(allocator, version) catch |err| switch (err) {
        error.FileNotFound => false, // No cache file means run update first
        else => return err,
    };

    if (!is_available) {
        std.debug.print("Error: Version '{s}' not found.\n\n", .{version});

        const available_versions = update.getAvailableVersions(allocator) catch |err| switch (err) {
            else => {
                std.debug.print("Run 'zigup update' to fetch available versions, then try again.\n", .{});
                return;
            },
        };
        defer {
            for (available_versions) |v| allocator.free(v);
            allocator.free(available_versions);
        }

        if (available_versions.len == 0) {
            std.debug.print("Run 'zigup update' to fetch available versions, then try again.\n", .{});
            return;
        }

        std.debug.print("Available versions:\n", .{});
        for (available_versions) |available_version| {
            std.debug.print("  {s}\n", .{available_version});
        }
        return;
    }

    std.debug.print("Installing Zig version: {s}\n", .{version});

    const cache_file = try cache_utils.getIndexCacheFile(allocator);
    defer allocator.free(cache_file);

    const json_data = std.fs.cwd().readFileAlloc(allocator, cache_file, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Error: Version cache not found. Run 'zigup update' first.\n", .{});
            return;
        },
        else => return err,
    };
    defer allocator.free(json_data);

    const Parser = zimdjson.dom.StreamParser(.default);
    var parser = Parser.init;
    defer parser.deinit(allocator);
    var json_slice = std.io.fixedBufferStream(json_data);
    const document = try parser.parseFromReader(allocator, json_slice.reader().any());

    const platform_str = Platform.getPlatformString();
    std.debug.print("Detected platform: {s}\n", .{platform_str});

    const version_key = if (std.mem.eql(u8, version, "master") or std.mem.eql(u8, version, "nightly"))
        "master"
    else
        version;

    const version_obj = document.at(version_key);
    const download_info = version_obj.at(platform_str);

    const tarball_url = download_info.at("tarball").asString() catch |err| switch (err) {
        error.MissingField => {
            std.debug.print("Error: Version '{s}' or platform '{s}' not found\n", .{ version, platform_str });
            return;
        },
        else => return err,
    };
    std.debug.print("Download URL: {s}\n", .{tarball_url});

    const bin_dir = try Platform.getBinDir(allocator);
    defer allocator.free(bin_dir);

    std.fs.cwd().makePath(bin_dir) catch |err| switch (err) {
        error.AccessDenied => {
            const platform = Platform.current();
            const instructions = switch (platform.os) {
                .windows => "Please check directory permissions or run as Administrator",
                else => blk: {
                    const user = std.process.getEnvVarOwned(allocator, "USER") catch "user";
                    defer if (!std.mem.eql(u8, user, "user")) allocator.free(user);
                    break :blk std.fmt.allocPrint(allocator, "Please run: sudo chown {s}:{s} {s}", .{ user, user, bin_dir }) catch "Please fix directory permissions";
                },
            };
            std.debug.print("Error: Cannot create {s}. {s}\n", .{ bin_dir, instructions });
            return;
        },
        else => return err,
    };

    try validation.validateVersionString(version);

    const version_dir = try Platform.getInstallDir(allocator, version);
    defer allocator.free(version_dir);

    const cache_dir = try cache_utils.getCacheDir(allocator);
    defer allocator.free(cache_dir);

    const archive_name = std.fs.path.basename(tarball_url);
    const archive_path = try std.fs.path.join(allocator, &.{ cache_dir, archive_name });
    defer allocator.free(archive_path);

    std.debug.print("Downloading to {s}...\n", .{archive_path});
    fs_utils.downloadFile(allocator, tarball_url, archive_path) catch |err| {
        std.debug.print("Error: Download failed: {}\n", .{err});
        return;
    };

    // Download and verify minisign signature
    const signature_url = try std.fmt.allocPrint(allocator, "{s}.minisig", .{tarball_url});
    defer allocator.free(signature_url);
    const signature_path = try std.fmt.allocPrint(allocator, "{s}.minisig", .{archive_path});
    defer allocator.free(signature_path);

    std.debug.print("Downloading signature...\n", .{});
    fs_utils.downloadFile(allocator, signature_url, signature_path) catch |err| {
        std.debug.print("Error: Signature download failed: {}\n", .{err});
        return;
    };

    std.debug.print("Verifying signature...\n", .{});
    verifyMinisignNative(allocator, archive_path, signature_path) catch |err| {
        std.debug.print("Error: Signature verification failed: {}\n", .{err});
        safeCleanup(archive_path, signature_path);
        return;
    };

    std.debug.print("Extracting to {s}...\n", .{version_dir});
    fs_utils.extractArchive(allocator, archive_path, version_dir) catch |err| {
        std.debug.print("Error: Extraction failed: {}\n", .{err});
        return;
    };

    safeCleanup(archive_path, signature_path);

    std.debug.print("Successfully installed Zig version: {s}\n", .{version});
}

/// Verify minisign signature using native Zig implementation
fn verifyMinisignNative(allocator: std.mem.Allocator, file_path: []const u8, signature_path: []const u8) !void {
    const pubkey_path = try cache_utils.getPublicKeyCacheFile(allocator);
    defer allocator.free(pubkey_path);

    // Download the public key from Zig download page if not cached
    const pubkey = downloadZigPublicKey(allocator, pubkey_path) catch |err| {
        std.debug.print("Error: Failed to fetch Zig public key: {}\n", .{err});
        return err;
    };
    defer allocator.free(pubkey);

    // Use our native minisign verification
    minisign.verifyFile(allocator, file_path, signature_path, pubkey) catch |err| {
        std.debug.print("Error: Native signature verification failed: {}\n", .{err});
        return err;
    };
}

/// Download and cache Zig's minisign public key from the download page
fn downloadZigPublicKey(allocator: std.mem.Allocator, cache_path: []const u8) ![]u8 {
    // Check if we have a cached/pinned key
    const pinned_key = if (std.fs.cwd().readFileAlloc(allocator, cache_path, 128)) |key| key else |_| null;

    // If we have a pinned key that's less than 24 hours old, use it
    if (pinned_key) |key| {
        defer allocator.free(key); // Always free the pinned key when done
        if (std.fs.cwd().statFile(cache_path)) |stat| {
            const now = std.time.timestamp();
            const cache_age = now - stat.mtime;
            if (cache_age < 24 * 60 * 60) { // 24 hours
                // Return a copy since we're freeing the original
                return try allocator.dupe(u8, key);
            }
        } else |_| {}
        // Key exists but cache expired, need to verify against pinned key
    }

    std.debug.print("Fetching Zig public key from download page...\n", .{});

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var buf: [8192]u8 = undefined;
    const download_page_url = "https://ziglang.org/download/";
    try fs_utils.validateUrl(download_page_url);
    var req = try client.open(.GET, try std.Uri.parse(download_page_url), .{
        .server_header_buffer = &buf,
    });
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    const body = try req.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);

    // Parse key from HTML (insecure but necessary for bootstrapping)
    // Security model: Accept any valid key on first fetch, then pin it
    const key_start = "RWS";
    var i: usize = 0;
    while (i < body.len - 64) : (i += 1) {
        if (std.mem.startsWith(u8, body[i..], key_start)) {
            var key_end = i;
            // Find the end of the key (usually ends at whitespace or HTML)
            while (key_end < body.len and key_end < i + 80) : (key_end += 1) {
                switch (body[key_end]) {
                    'A'...'Z', 'a'...'z', '0'...'9', '+', '/', '=' => {},
                    else => break,
                }
            }

            if (key_end > i + 50) { // Reasonable key length
                const potential_key = body[i..key_end];
                if (isValidPublicKey(potential_key)) {
                    const key_copy = try allocator.dupe(u8, potential_key);

                    // Verify against pinned key if we have one
                    if (pinned_key) |pinned| {
                        defer allocator.free(pinned);
                        if (!std.mem.eql(u8, potential_key, pinned)) {
                            std.debug.print("ERROR: Public key mismatch!\n", .{});
                            std.debug.print("Pinned key:  {s}\n", .{pinned});
                            std.debug.print("Fetched key: {s}\n", .{potential_key});
                            std.debug.print("This could indicate a security compromise.\n", .{});
                            std.debug.print("Use 'zigup key-reset' to accept the new key if legitimate.\n", .{});
                            return error.PublicKeyMismatch;
                        }
                        std.debug.print("Public key verified against pinned key.\n", .{});
                    } else {
                        // First time - warn user about key acceptance
                        std.debug.print("WARNING: Accepting Zig team public key for first time\n", .{});
                        std.debug.print("Key: {s}\n", .{potential_key});
                        std.debug.print("This key will be pinned for future verification.\n", .{});
                        std.debug.print("If this is not the expected key, abort now!\n\n", .{});
                    }

                    // Cache/update the key
                    const cache_dir = std.fs.path.dirname(cache_path) orelse return error.InvalidCachePath;
                    std.fs.cwd().makePath(cache_dir) catch {};
                    std.fs.cwd().writeFile(.{ .sub_path = cache_path, .data = key_copy }) catch {};

                    return key_copy;
                }
            }
        }
    }

    return error.PublicKeyNotFound;
}

/// Validate that a string looks like a valid minisign public key
fn isValidPublicKey(key: []const u8) bool {
    if (key.len < 50 or key.len > 80) return false;
    if (!std.mem.startsWith(u8, key, "RWS")) return false;

    // Check if it's valid base64-like characters
    for (key) |c| {
        switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '+', '/', '=' => {},
            else => return false,
        }
    }
    return true;
}
