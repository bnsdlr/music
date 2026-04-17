const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const build_zig_zon = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
        .target = target,
        .optimize = optimize,
    });

    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const wrapper = b.dependency("libchromaprint", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "music",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    exe.root_module.addImport("sqlite", sqlite.module("sqlite"));
    exe.root_module.addImport("chromaprint", wrapper.module("wrapper"));
    exe.root_module.addImport("build.zig.zon", build_zig_zon);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the server");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module }));

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&exe_tests.step);
}
