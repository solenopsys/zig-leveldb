const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const leveldb_mod = b.addModule("leveldb", .{
        .root_source_file = .{ .cwd_relative = "src/leveldb.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "leveldb-example",
        .root_source_file = .{ .cwd_relative = "src/example.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("leveldb", leveldb_mod);

    exe.root_module.linkSystemLibrary("leveldb", .{});
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("leveldb", leveldb_mod);
    unit_tests.root_module.linkSystemLibrary("leveldb", .{});
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
