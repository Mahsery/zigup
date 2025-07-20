//! Use `zig init --strip` next time to generate a project without comments.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});
    const zimdjson = b.dependency("zimdjson", .{});

    // Main zigup executable
    const exe = b.addExecutable(.{
        .name = "zigup",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addImport("zimdjson", zimdjson.module("zimdjson"));

    b.installArtifact(exe);

    // Installer executable
    const installer = b.addExecutable(.{
        .name = "zigup-installer",
        .root_source_file = b.path("src/installer.zig"),
        .target = target,
        .optimize = optimize,
    });

    installer.root_module.addImport("zimdjson", zimdjson.module("zimdjson"));

    b.installArtifact(installer);

    // Install step for zigup (builds and runs installer)
    const install_zigup_step = b.step("install-zigup", "Build and run installer to install zigup");
    const run_installer = b.addRunArtifact(installer);
    run_installer.step.dependOn(b.getInstallStep());
    install_zigup_step.dependOn(&run_installer.step);

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
