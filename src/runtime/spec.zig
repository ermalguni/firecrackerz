const models = @import("../engine/root.zig").models;

/// Configuration borrowed for the entire boot call. Artifact paths remain caller
/// owned and are resolved by Firecracker; runtime never copies or deletes them.
/// Writable drives may be modified by the guest, including before a failed boot
/// returns. Use private images when those writes must be isolated.
pub const BootSpec = struct {
    machine: models.MachineConfigurationRequest,
    boot_source: models.BootSourceRequest,
    drives: []const models.DriveRequest = &.{},
    /// Applied in order after drives. TAPs must already exist and remain caller
    /// owned; runtime never creates or removes host networking.
    network_interfaces: []const models.NetworkInterfaceRequest = &.{},
};
