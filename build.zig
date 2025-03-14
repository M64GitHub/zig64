const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add zig64 module
    const mod_zig64 = b.addModule("zig64", .{
        .root_source_file = b.path("src/zig64.zig"),
    });

    // Example loadprg
    const exe_loadprg = b.addExecutable(.{
        .name = "loadPrg-example",
        .root_source_file = b.path(
            "src/examples/loadprg_example.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    exe_loadprg.root_module.addImport("zig64", mod_zig64);
    b.installArtifact(exe_loadprg);

    const run_cmd_loadprg = b.addRunArtifact(exe_loadprg);
    run_cmd_loadprg.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd_loadprg.addArgs(args);
    }
    const run_step_loadprg = b.step(
        "run-loadprg",
        "Run the loadprg example",
    );
    run_step_loadprg.dependOn(&run_cmd_loadprg.step);

    // Example cpu-writebyte
    const exe_writebyte = b.addExecutable(.{
        .name = "loadPrg-example",
        .root_source_file = b.path(
            "src/examples/cpu-writebyte_example.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    exe_writebyte.root_module.addImport("zig64", mod_zig64);
    b.installArtifact(exe_writebyte);

    const run_cmd_writebyte = b.addRunArtifact(exe_writebyte);
    run_cmd_writebyte.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd_writebyte.addArgs(args);
    }
    const run_step_writebyte = b.step(
        "run-writebyte",
        "Run the cpu-writebyte example",
    );
    run_step_writebyte.dependOn(&run_cmd_writebyte.step);

    // CPU Test
    const test_exe = b.addTest(.{
        .root_source_file = b.path(
            "src/test/test-cpu.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    test_exe.root_module.addImport("zig64", mod_zig64);

    const test_run = b.addRunArtifact(test_exe);
    test_run.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Build and run tests");
    test_step.dependOn(&test_run.step);
}
