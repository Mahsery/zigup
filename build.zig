//! Use `zig init --strip` next time to generate a project without comments.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});
    const zimdjson = b.dependency("zimdjson", .{});

    const exe = b.addExecutable(.{
        .name = "zigup",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addImport("zimdjson", zimdjson.module("zimdjson"));

    b.installArtifact(exe);

    // Add cross-platform zigup install step
    const install_zigup_step = b.step("install-zigup", "Install zigup to local bin directory");
    
    // Create cross-platform installation command
    const builtin = @import("builtin");
    const install_zigup_cmd = switch (builtin.os.tag) {
        .windows => b.addSystemCommand(&[_][]const u8{
            "powershell", "-ExecutionPolicy", "Bypass", "-File", "install.ps1"
        }),
        else => b.addSystemCommand(&[_][]const u8{
            "sh", "install-mac.sh"
        }),
    };
    
    install_zigup_cmd.step.dependOn(b.getInstallStep());
    install_zigup_step.dependOn(&install_zigup_cmd.step);

    const run_step = b.step("run", "Run zigup");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
