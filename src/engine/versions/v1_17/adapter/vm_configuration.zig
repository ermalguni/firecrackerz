const std = @import("std");
const models = @import("../../../models.zig");

pub fn decodeVmConfiguration(allocator: std.mem.Allocator, body: []const u8) !models.FullVmConfiguration {
    // Nested public values match this contract's JSON shapes. Decode directly
    // into them to avoid allocating and copying a second set of device arrays.
    const Configuration = struct {
        @"boot-source": ?models.BootSourceRequest = null,
        @"machine-config": ?models.MachineConfigurationRequest = null,
        drives: ?[]const models.DriveRequest = null,
        @"network-interfaces": ?[]const models.NetworkInterfaceRequest = null,
        @"cpu-config": ?models.CpuConfiguration = null,
        balloon: ?models.BalloonConfiguration = null,
        vsock: ?models.VsockConfiguration = null,
        entropy: ?models.EntropyConfiguration = null,
        @"mmds-config": ?models.MmdsConfiguration = null,
        logger: ?models.LoggerRequest = null,
        metrics: ?models.MetricsRequest = null,
        pmem: ?[]const models.PmemConfiguration = null,
        @"memory-hotplug": ?models.MemoryHotplugConfiguration = null,
    };
    const parsed = try std.json.parseFromSlice(Configuration, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    const value = parsed.value;
    return .{
        .boot_source = value.@"boot-source",
        .machine_config = value.@"machine-config",
        .drives = value.drives,
        .network_interfaces = value.@"network-interfaces",
        .cpu_config = value.@"cpu-config",
        .balloon = value.balloon,
        .vsock = value.vsock,
        .entropy = value.entropy,
        .mmds_config = value.@"mmds-config",
        .logger = value.logger,
        .metrics = value.metrics,
        .pmem = value.pmem,
        .memory_hotplug = value.@"memory-hotplug",
        .arena = parsed.arena,
    };
}
