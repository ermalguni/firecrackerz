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
    b.step("protocol", "Exercise both API contracts over a local Unix socket").dependOn(&protocol_run.step);

    const fixture = b.addExecutable(.{
        .name = "discovery-fixture",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/discovery_fixture.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const discovery_process = b.addExecutable(.{
        .name = "discovery-process",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/discovery_process.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "firecrackerz", .module = mod }},
        }),
    });
    check.dependOn(&discovery_process.step);
    check.dependOn(&fixture.step);
    const discovery_run = b.addRunArtifact(discovery_process);
    discovery_run.addArtifactArg(fixture);
    b.step("discovery-test", "Exercise executable discovery, limits, and deadlines").dependOn(&discovery_run.step);

    const integration = b.addExecutable(.{
        .name = "integration",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "firecrackerz", .module = mod }},
        }),
    });
    check.dependOn(&integration.step);
    const integration_run = b.addRunArtifact(integration);
    integration_run.addPassthruArgs();
    b.step("integration", "Exercise a disposable v1.17.0 API socket (pass -- SOCKET)").dependOn(&integration_run.step);

    const examples = b.step("examples", "Build library usage examples");
    inline for (.{ "discover", "inspect", "configure_and_start" }) |name| {
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
    }
}
