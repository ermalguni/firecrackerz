const std = @import("std");
const fc = @import("firecrackerz").engine;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) {
        std.debug.print("Usage: {s} SOCKET FIRECRACKER_EXECUTABLE\n", .{args[0]});
        return error.InvalidArguments;
    }
    var result = try fc.Client.connect(init.gpa, init.io, .{
        .socket_path = args[1],
        .binary = .{ .executable = args[2] },
    });
    defer result.deinit();
    switch (result) {
        .success => |*client| {
            const info = client.info();
            const v = info.running_version;
            std.debug.print("Connected: {s}; Firecracker {d}.{d}.{d}; contract {s}\n", .{
                info.executable_path, v.major, v.minor, v.patch, @tagName(info.contract),
            });
            var instance = try client.getInstanceInfo();
            defer instance.deinit();
            switch (instance) {
                .success => |value| std.debug.print(
                    "Instance: id={s}; state={s}; vmm_version={s}; app_name={s}\n",
                    .{ value.id, value.state, value.vmm_version, value.app_name },
                ),
                .fault => |fault| {
                    std.debug.print("Instance information HTTP {d}: {s}\n", .{ fault.status, fault.body });
                    return error.InstanceInfoRejected;
                },
            }
            var configuration = try client.getMachineConfiguration();
            defer configuration.deinit();
            switch (configuration) {
                .success => |config| std.debug.print(
                    "Machine: vcpus={d}; memory_mib={d}; smt={?}; track_dirty_pages={?}; cpu_template={s}; huge_pages={s}\n",
                    .{ config.vcpu_count, config.mem_size_mib, config.smt, config.track_dirty_pages, config.cpu_template orelse "(absent)", config.huge_pages orelse "(absent)" },
                ),
                .fault => |fault| {
                    std.debug.print("Machine configuration HTTP {d}: {s}\n", .{ fault.status, fault.body });
                    return error.MachineConfigurationRejected;
                },
            }
            var exported = try client.getVmConfiguration();
            defer exported.deinit();
            switch (exported) {
                .success => |config| std.debug.print(
                    "VM configuration: kernel={s}; drives={d}; network_interfaces={d}\n",
                    .{
                        if (config.boot_source) |boot| boot.kernel_image_path else "(absent)",
                        if (config.drives) |drives| drives.len else 0,
                        if (config.network_interfaces) |interfaces| interfaces.len else 0,
                    },
                ),
                .fault => |fault| {
                    std.debug.print("VM configuration HTTP {d}: {s}\n", .{ fault.status, fault.body });
                    return error.VmConfigurationRejected;
                },
            }
        },
        .fault => |fault| {
            std.debug.print("Firecracker HTTP {d}: {s}\n", .{ fault.status, fault.body });
            return error.HandshakeRejected;
        },
    }
}
