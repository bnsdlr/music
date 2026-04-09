const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mod = b.addModule("server", .{
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const wrapper_mod = b.dependency("libchromaprint", .{
        .target = target,
        .optimize = optimize,
    }).module("wrapper");
    mod.addImport("chromaprint", wrapper_mod);

    const exe = b.addExecutable(.{
        .name = "music",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    exe.root_module.addImport("lib", mod);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the server");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addRunArtifact(b.addTest(.{ .root_module = mod }));
    const exe_tests = b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module }));

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&mod_tests.step);
    test_step.dependOn(&exe_tests.step);
}
