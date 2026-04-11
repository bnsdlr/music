const std = @import("std");

pub fn build(b: *std.Build) void {
    const music_brainz_user_agent = b.option([]const u8, "music_brainz_user_agent", "User-Agent used for MusicBrainz API, it should be formatted like this: 'Application name/<version> ( contact-email/url )'");

    if (music_brainz_user_agent == null) {
        @panic("add music_brainz_user_agent, use --help for help");
    }

    const options = b.addOptions();
    options.addOption([]const u8, "music_brainz_user_agent", music_brainz_user_agent.?);

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mod = b.addModule("server-lib", .{
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });
    mod.addOptions("build_options", options);

    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("sqlite", sqlite.module("sqlite"));

    const wrapper_mod = b.dependency("libchromaprint", .{
        .target = target,
        .optimize = optimize,
    }).module("wrapper");
    mod.addImport("chromaprint", wrapper_mod);

    const mod_tests = b.addRunArtifact(b.addTest(.{ .root_module = mod }));

    const test_step = b.step("test", "Test the tests");
    test_step.dependOn(&mod_tests.step);
}
