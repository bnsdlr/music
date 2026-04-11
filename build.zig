const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const server_lib = b.dependency("server-lib", .{
        .optimize = optimize,
        .target = target,
        .music_brainz_user_agent = "music/0.0.1 ( me@bsdlr.de )",
    });
    const lib_mod = server_lib.module("server-lib");

    const sqlite = server_lib.builder.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    }).module("sqlite");

    const wrapper_mod = server_lib.builder.dependency("libchromaprint", .{
        .target = target,
        .optimize = optimize,
    }).module("wrapper");

    const exe = b.addExecutable(.{
        .name = "music",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    exe.root_module.addImport("lib", lib_mod);
    exe.root_module.addImport("sqlite", sqlite);
    exe.root_module.addImport("chromaprint", wrapper_mod);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the server");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const lib_mod_tests = b.addRunArtifact(b.addTest(.{ .root_module = lib_mod }));
    const exe_tests = b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module }));

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&lib_mod_tests.step);
    test_step.dependOn(&exe_tests.step);
}
