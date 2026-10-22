const std = @import("std");
const fc = @import("firecrackerz").engine;

/// Mutates a caller-supplied disposable, pre-boot instance only.
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4 or !std.mem.eql(u8, args[3], "--disposable")) {
        std.debug.print("Usage: {s} SOCKET EXECUTABLE --disposable (writes configuration)\n", .{args[0]});
        return error.InvalidArguments;
    }
    var connected = try fc.Client.connect(init.gpa, init.io, .{
        .socket_path = args[1],
        .binary = .{ .executable = args[2] },
    });
    defer connected.deinit();
    switch (connected) {
        .fault => return error.ConnectionRejected,
        .success => |*client| {
            var configured = try client.putMachineConfiguration(.{
                .vcpu_count = 2,
                .mem_size_mib = 256,
                .track_dirty_pages = true,
                .huge_pages = "Transparent",
            });
            defer configured.deinit();
            try expectSuccess(&configured);
            try checkConfiguration(client, 2, 256, true, "Transparent");
            std.debug.print("PASS configured values and optional settings read back\n", .{});

            var patched = try client.patchMachineConfiguration(.{ .mem_size_mib = 384 });
            defer patched.deinit();
            try expectSuccess(&patched);
            try checkConfiguration(client, 2, 384, true, "Transparent");
            std.debug.print("PASS PATCH memory preserves omitted CPU and optional settings\n", .{});

            var cleared = try client.patchMachineConfiguration(.{ .track_dirty_pages = false });
            defer cleared.deinit();
            try expectSuccess(&cleared);
            try checkConfiguration(client, 2, 384, false, "Transparent");
            std.debug.print("PASS PATCH explicit false changes only dirty-page tracking\n", .{});

            var invalid_patch = try client.patchMachineConfiguration(.{ .vcpu_count = 0, .mem_size_mib = 1024 });
            defer invalid_patch.deinit();
            switch (invalid_patch) {
                .success => return error.InvalidPatchAccepted,
                .fault => |fault| if (fault.status != 400) return error.UnexpectedFaultStatus,
            }
            try checkConfiguration(client, 2, 384, false, "Transparent");
            std.debug.print("PASS invalid PATCH leaves every prior setting intact\n", .{});

            var replaced = try client.putMachineConfiguration(.{ .vcpu_count = 4, .mem_size_mib = 512 });
            defer replaced.deinit();
            try expectSuccess(&replaced);
            try checkConfiguration(client, 4, 512, false, "None");
            std.debug.print("PASS omitted optional settings reset on PUT\n", .{});

            var invalid = try client.putMachineConfiguration(.{ .vcpu_count = 0, .mem_size_mib = 1024 });
            defer invalid.deinit();
            switch (invalid) {
                .success => return error.InvalidConfigurationAccepted,
                .fault => |fault| {
                    if (fault.status != 400) return error.UnexpectedFaultStatus;
                    const parsed = try std.json.parseFromSlice(struct { fault_message: []const u8 }, init.gpa, fault.body, .{});
                    defer parsed.deinit();
                    std.debug.print("PASS invalid configuration rejected: HTTP {d}: {s}\n", .{ fault.status, parsed.value.fault_message });
                },
            }
            try checkConfiguration(client, 4, 512, false, "None");
            std.debug.print("PASS rejected update leaves prior configuration intact\n", .{});

            const x86 = @import("builtin").cpu.arch == .x86_64;
            var cpu = try client.putCpuConfiguration(.{
                .kvm_capabilities = &.{"!121"},
                .cpuid_modifiers = if (x86) &.{.{
                    .leaf = "0x1",
                    .subleaf = "0x0",
                    .flags = 0,
                    .modifiers = &.{.{
                        .register = "ecx",
                        .bitmap = "0bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx0",
                    }},
                }} else null,
            });
            defer cpu.deinit();
            try expectSuccess(&cpu);
            std.debug.print("PASS custom CPU template accepted: HTTP 204 (not a guest boot check)\n", .{});

            var invalid_cpu = try client.putCpuConfiguration(.{ .kvm_capabilities = &.{"invalid"} });
            defer invalid_cpu.deinit();
            switch (invalid_cpu) {
                .success => return error.InvalidCpuConfigurationAccepted,
                .fault => |fault| if (fault.status != 400) return error.UnexpectedFaultStatus,
            }
            std.debug.print("PASS malformed CPU template rejected: HTTP 400\n", .{});

            var replaced_cpu = try client.putCpuConfiguration(.{});
            defer replaced_cpu.deinit();
            try expectSuccess(&replaced_cpu);
            std.debug.print("PASS empty replacement CPU template accepted: HTTP 204\n", .{});
        },
    }
}

fn expectSuccess(result: *const fc.Result(void)) !void {
    switch (result.*) {
        .success => {},
        .fault => |fault| {
            std.debug.print("Unexpected HTTP {d}: {s}\n", .{ fault.status, fault.body });
            return error.ConfigurationRejected;
        },
    }
}

fn checkConfiguration(client: *fc.Client, vcpus: i64, memory: i64, dirty: bool, huge_pages: []const u8) !void {
    var result = try client.getMachineConfiguration();
    defer result.deinit();
    switch (result) {
        .fault => return error.ReadbackRejected,
        .success => |config| {
            if (config.vcpu_count != vcpus or config.mem_size_mib != memory or config.track_dirty_pages != dirty or
                !std.mem.eql(u8, config.huge_pages orelse return error.MissingHugePages, huge_pages))
                return error.ConfigurationMismatch;
        },
    }
}
