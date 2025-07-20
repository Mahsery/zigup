const std = @import("std");
const builtin = @import("builtin");
const zimdjson = @import("zimdjson");

const GITHUB_RELEASES_URL = "https://api.github.com/repos/Mahsery/zigup/releases";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("ZigUp Installer\n", .{});
    std.debug.print("===============\n\n", .{});

    // Get platform-specific binary name
    const binary_name = getBinaryName();
    const install_dir = try getInstallDir(allocator);
    defer allocator.free(install_dir);

    std.debug.print("Installing ZigUp to: {s}\n", .{install_dir});

    // Create install directory
    std.fs.cwd().makePath(install_dir) catch |err| switch (err) {
        error.AccessDenied => {
            std.debug.print("Error: Permission denied creating directory: {s}\n", .{install_dir});
            return;
        },
        else => return err,
    };

    // Download latest release info
    const download_url = try getLatestReleaseUrl(allocator, binary_name);
    defer allocator.free(download_url);

    std.debug.print("Downloading from: {s}\n", .{download_url});

    // Download zigup binary
    const binary_path = try std.fs.path.join(allocator, &.{ install_dir, getBinaryFileName() });
    defer allocator.free(binary_path);

    try downloadFile(allocator, download_url, binary_path);

    // Make executable on Unix
    if (builtin.os.tag != .windows) {
        const file = std.fs.cwd().openFile(binary_path, .{ .mode = .read_write }) catch return;
        defer file.close();
        file.chmod(0o755) catch {};
    }

    std.debug.print("Successfully downloaded zigup!\n\n", .{});

    // Setup PATH
    try setupPath(allocator, install_dir);

    std.debug.print("Installation complete!\n", .{});
    std.debug.print("Run 'zigup update' to get started.\n", .{});
}

fn getBinaryName() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "zigup.exe",
        .linux => "zigup-linux",
        .macos => "zigup-macos",
        else => "zigup",
    };
}

fn getBinaryFileName() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "zigup.exe",
        else => "zigup",
    };
}

fn getInstallDir(allocator: std.mem.Allocator) ![]u8 {
    const home = switch (builtin.os.tag) {
        .windows => std.process.getEnvVarOwned(allocator, "USERPROFILE") catch return error.NoHomeDir,
        else => std.process.getEnvVarOwned(allocator, "HOME") catch return error.NoHomeDir,
    };
    defer allocator.free(home);

    return try std.fs.path.join(allocator, &.{ home, ".local", "bin" });
}

fn getLatestReleaseUrl(allocator: std.mem.Allocator, binary_name: []const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var buf: [8192]u8 = undefined;
    var req = try client.open(.GET, try std.Uri.parse(GITHUB_RELEASES_URL), .{
        .server_header_buffer = &buf,
        .headers = .{
            .user_agent = .{ .override = "zigup-installer/1.0" },
        },
    });
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    const body = try req.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);

    // Parse JSON properly using zimdjson
    const Parser = zimdjson.dom.StreamParser(.default);
    var parser = Parser.init;
    defer parser.deinit(allocator);
    var json_slice = std.io.fixedBufferStream(body);
    const document = try parser.parseFromReader(allocator, json_slice.reader().any());
    
    // Get the first release from the releases array
    const releases_array = try document.asArray();
    var releases_iter = releases_array.iterator();
    const first_release = releases_iter.next() orelse return error.NoReleasesFound;
    
    // Get the assets array from the first release
    const assets = first_release.at("assets");
    
    // Look through each asset for our binary using iterator
    const assets_array = try assets.asArray();
    var iter = assets_array.iterator();
    while (iter.next()) |asset| {
        const name = try asset.at("name").asString();
        if (std.mem.eql(u8, name, binary_name)) {
            const download_url = try asset.at("browser_download_url").asString();
            return try allocator.dupe(u8, download_url);
        }
    }
    
    return error.BinaryNotFound;
}

fn downloadFile(allocator: std.mem.Allocator, url: []const u8, destination: []const u8) !void {
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

fn setupPath(allocator: std.mem.Allocator, install_dir: []const u8) !void {
    switch (builtin.os.tag) {
        .windows => try setupWindowsPath(install_dir),
        else => try setupUnixPath(allocator, install_dir),
    }
}

fn setupWindowsPath(install_dir: []const u8) !void {
    // Check if already in PATH
    const current_path = std.process.getEnvVarOwned(std.heap.page_allocator, "PATH") catch return;
    defer std.heap.page_allocator.free(current_path);

    if (std.mem.indexOf(u8, current_path, install_dir) != null) {
        std.debug.print("Directory already in PATH: {s}\n", .{install_dir});
        return;
    }

    std.debug.print("Adding to PATH: {s}\n", .{install_dir});
    std.debug.print("Note: You may need to restart your terminal for PATH changes to take effect.\n", .{});

    // Try to modify user PATH (requires no admin privileges)
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const setx_cmd = try std.fmt.allocPrint(allocator, "setx PATH \"{s};%PATH%\"", .{install_dir});
    
    var process = std.process.Child.init(&[_][]const u8{ "cmd", "/c", setx_cmd }, allocator);
    process.stdout_behavior = .Ignore;
    process.stderr_behavior = .Ignore;
    const result = process.spawnAndWait() catch {
        std.debug.print("Warning: Could not automatically update PATH.\n", .{});
        std.debug.print("Please manually add {s} to your PATH.\n", .{install_dir});
        return;
    };

    if (result == .Exited and result.Exited == 0) {
        std.debug.print("PATH updated successfully!\n", .{});
    } else {
        std.debug.print("Warning: PATH update may have failed.\n", .{});
        std.debug.print("Please manually add {s} to your PATH if needed.\n", .{install_dir});
    }
}

fn setupUnixPath(allocator: std.mem.Allocator, install_dir: []const u8) !void {
    // Check if already in PATH
    const current_path = std.process.getEnvVarOwned(allocator, "PATH") catch return;
    defer allocator.free(current_path);

    if (std.mem.indexOf(u8, current_path, install_dir) != null) {
        std.debug.print("Directory already in PATH: {s}\n", .{install_dir});
        return;
    }

    // Detect shell and provide instructions
    const shell = std.process.getEnvVarOwned(allocator, "SHELL") catch {
        std.debug.print("Could not detect shell. Please manually add to PATH:\n", .{});
        std.debug.print("  export PATH=\"{s}:$PATH\"\n", .{install_dir});
        return;
    };
    defer allocator.free(shell);

    const shell_name = std.fs.path.basename(shell);
    
    std.debug.print("To complete installation, add {s} to your PATH:\n\n", .{install_dir});
    
    if (std.mem.eql(u8, shell_name, "fish")) {
        std.debug.print("Add to ~/.config/fish/config.fish:\n", .{});
        std.debug.print("  set -gx PATH {s} $PATH\n", .{install_dir});
    } else {
        const config_file = if (std.mem.eql(u8, shell_name, "zsh")) "~/.zshrc" else "~/.bashrc";
        std.debug.print("Add to {s}:\n", .{config_file});
        std.debug.print("  export PATH=\"{s}:$PATH\"\n", .{install_dir});
    }
    
    std.debug.print("\nThen restart your terminal or run: source <config-file>\n", .{});
}