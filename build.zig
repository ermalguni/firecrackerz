const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dusty = b.dependency("dusty", .{
        .target = target,
        .optimize = optimize,
        .use_tls = false,
        .use_zlib = false,
    });
    const mod = b.addModule("firecrackerz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("dusty", dusty.module("dusty"));

    const tests = b.addTest(.{ .root_module = mod });
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const check = b.step("check", "Compile the library and examples");
    check.dependOn(&tests.step);
    b.default_step.dependOn(check);

    const codegen_step = b.step("codegen", "Generate version-specific Firecracker API models");
    inline for (.{ "v1_17", "v1_18" }) |version| {
        const openapi_codegen = b.addSystemCommand(&.{"openapi2zig"});
        openapi_codegen.addArgs(&.{
            "generate",
            "-i",
            "spec/" ++ version ++ "/firecracker.json",
            "-o",
            "src/versions/" ++ version ++ "/models.zig",
            "--models-only",
        });
        codegen_step.dependOn(&openapi_codegen.step);
    }

    const protocol = b.addExecutable(.{
        .name = "protocol",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "firecrackerz", .module = mod }},
        }),
    });
    check.dependOn(&protocol.step);
    const protocol_run = b.addSystemCommand(&.{ "python3", "tests/protocol.py" });
    protocol_run.addArtifactArg(protocol);
    b.step("protocol", "Exercise connection behavior over a local Unix socket").dependOn(&protocol_run.step);
    b.step("discovery-test", "Exercise discovery and connection failures").dependOn(&protocol_run.step);

    const configure = b.addExecutable(.{
        .name = "configure-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/configure.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "firecrackerz", .module = mod }},
        }),
    });
    check.dependOn(&configure.step);
    const configure_run = b.addRunArtifact(configure);
    configure_run.addPassthruArgs();
    b.step("configure-test", "Write/read a disposable instance (-- SOCKET EXECUTABLE --disposable)").dependOn(&configure_run.step);

    const boot_source = b.addExecutable(.{
        .name = "boot-source-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/boot_source.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "firecrackerz", .module = mod }},
        }),
    });
    check.dependOn(&boot_source.step);
    const boot_source_run = b.addRunArtifact(boot_source);
    boot_source_run.addPassthruArgs();
    b.step("boot-source-test", "Configure a disposable boot source (-- SOCKET EXECUTABLE KERNEL INITRD --disposable)").dependOn(&boot_source_run.step);

    const drive = b.addExecutable(.{
        .name = "drive-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/drive.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "firecrackerz", .module = mod }},
        }),
    });
    check.dependOn(&drive.step);
    const drive_run = b.addRunArtifact(drive);
    drive_run.addPassthruArgs();
    b.step("drive-test", "Configure a disposable root drive (-- SOCKET EXECUTABLE IMAGE --disposable)").dependOn(&drive_run.step);

    const examples = b.step("examples", "Build library usage examples");
    inline for (.{ "inspect", "configure_and_start", "observability" }) |name| {
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/" ++ name ++ ".zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "firecrackerz", .module = mod }},
            }),
        });
        check.dependOn(&exe.step);
        examples.dependOn(&b.addInstallArtifact(exe, .{}).step);
        const run = b.addRunArtifact(exe);
        run.addPassthruArgs();
        b.step(name, "Run the " ++ name ++ " example").dependOn(&run.step);
        if (comptime std.mem.eql(u8, name, "inspect")) {
            b.step("integration", "Inspect a disposable instance (pass -- SOCKET EXECUTABLE)").dependOn(&run.step);
        }
    }
}
