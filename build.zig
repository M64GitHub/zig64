const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add zig64 module
    const mod_zig64 = b.addModule("zig64", .{
        .root_source_file = b.path("src/zig64.zig"),
    });

    // Example executable
    const exe = b.addExecutable(.{
        .name = "loadPrg-example",
        .root_source_file = b.path("src/examples/loadprg_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zig64", mod_zig64);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the prg");
    run_step.dependOn(&run_cmd.step);

    // CPU Test
    const test_exe = b.addTest(.{
        .root_source_file = b.path("src/test/test-cpu.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_exe.root_module.addImport("zig64", mod_zig64);

    const test_run = b.addRunArtifact(test_exe);
    test_run.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Build and run tests");
    test_step.dependOn(&test_run.step);
}
