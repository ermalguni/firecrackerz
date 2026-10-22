const std = @import("std");
const BootSourceRequest = @import("../boot_source/models.zig").BootSourceRequest;
const MachineConfigurationRequest = @import("../machine/models.zig").MachineConfigurationRequest;
const DriveRequest = @import("../drive/models.zig").DriveRequest;
const NetworkInterfaceRequest = @import("../network_interface/models.zig").NetworkInterfaceRequest;
const CpuConfiguration = @import("../cpu/models.zig").CpuConfiguration;
const BalloonConfiguration = @import("../balloon/models.zig").BalloonConfiguration;
const VsockConfiguration = @import("../devices/models.zig").VsockConfiguration;
const EntropyConfiguration = @import("../devices/models.zig").EntropyConfiguration;
const MmdsConfiguration = @import("../mmds/models.zig").MmdsConfiguration;
const LoggerRequest = @import("../observability/models.zig").LoggerRequest;
const MetricsRequest = @import("../observability/models.zig").MetricsRequest;
const PmemConfiguration = @import("../devices/models.zig").PmemConfiguration;
const MemoryHotplugConfiguration = @import("../memory_hotplug/models.zig").MemoryHotplugConfiguration;

/// Owned full resource configuration. Nested values borrow this result's arena;
/// release only the enclosing result. Missing and null resources remain null.
/// Snapshot restores may omit boot_source, machine_config.smt and cpu_template.
pub const FullVmConfiguration = struct {
    boot_source: ?BootSourceRequest,
    machine_config: ?MachineConfigurationRequest,
    drives: ?[]const DriveRequest,
    network_interfaces: ?[]const NetworkInterfaceRequest,
    cpu_config: ?CpuConfiguration,
    balloon: ?BalloonConfiguration,
    vsock: ?VsockConfiguration,
    entropy: ?EntropyConfiguration,
    mmds_config: ?MmdsConfiguration,
    logger: ?LoggerRequest,
    metrics: ?MetricsRequest,
    pmem: ?[]const PmemConfiguration,
    memory_hotplug: ?MemoryHotplugConfiguration,
    arena: *std.heap.ArenaAllocator,

    pub fn deinit(self: *FullVmConfiguration) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }
};
