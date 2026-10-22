const std = @import("std");
const version = @import("version.zig");
const models = @import("../models.zig");
const instance = @import("../versions/v1_17/adapter/instance.zig");
const machine = @import("../versions/v1_17/adapter/machine.zig");
const cpu = @import("../versions/v1_17/adapter/cpu.zig");
const boot_source = @import("../versions/v1_17/adapter/boot_source.zig");
const drive = @import("../versions/v1_17/adapter/drive.zig");
const network_interface = @import("../versions/v1_17/adapter/network_interface.zig");
const balloon = @import("../versions/v1_17/adapter/balloon.zig");
const memory_hotplug = @import("../versions/v1_17/adapter/memory_hotplug.zig");
const mmds = @import("../versions/v1_17/adapter/mmds.zig");
const snapshot = @import("../versions/v1_17/adapter/snapshot.zig");
const observability = @import("../versions/v1_17/adapter/observability.zig");
const devices = @import("../versions/v1_17/adapter/devices.zig");
const vm_configuration = @import("../versions/v1_17/adapter/vm_configuration.zig");

pub const Backend = union(enum) {
    v1_17,

    pub fn select(runtime: version.Version) !Backend {
        try version.supported(runtime);
        return .v1_17;
    }

    pub fn contract(self: Backend) models.Contract {
        return switch (self) {
            .v1_17 => .v1_17,
        };
    }

    pub fn decodeVersion(self: Backend, allocator: std.mem.Allocator, body: []const u8) !version.Version {
        return switch (self) {
            .v1_17 => instance.decodeVersion(allocator, body),
        };
    }

    pub fn decodeInstanceInfo(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.InstanceInfo {
        return switch (self) {
            .v1_17 => instance.decodeInstanceInfo(allocator, body),
        };
    }

    pub fn decodeMachineConfiguration(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.MachineConfiguration {
        return switch (self) {
            .v1_17 => machine.decodeMachineConfiguration(allocator, body),
        };
    }

    pub fn decodeVmConfiguration(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.FullVmConfiguration {
        return switch (self) {
            .v1_17 => vm_configuration.decodeVmConfiguration(allocator, body),
        };
    }

    pub fn encodeMachineConfiguration(self: Backend, allocator: std.mem.Allocator, request: models.MachineConfigurationRequest) ![]u8 {
        return switch (self) {
            .v1_17 => machine.encodeMachineConfiguration(allocator, request),
        };
    }

    pub fn encodeMachineConfigurationUpdate(self: Backend, allocator: std.mem.Allocator, request: models.MachineConfigurationUpdate) ![]u8 {
        return switch (self) {
            .v1_17 => machine.encodeMachineConfigurationUpdate(allocator, request),
        };
    }

    pub fn encodeCpuConfiguration(self: Backend, allocator: std.mem.Allocator, request: models.CpuConfiguration) ![]u8 {
        return switch (self) {
            .v1_17 => cpu.encodeCpuConfiguration(allocator, request),
        };
    }

    pub fn encodeBootSource(self: Backend, allocator: std.mem.Allocator, request: models.BootSourceRequest) ![]u8 {
        return switch (self) {
            .v1_17 => boot_source.encodeBootSource(allocator, request),
        };
    }

    pub fn encodeDrive(self: Backend, allocator: std.mem.Allocator, request: models.DriveRequest) ![]u8 {
        return switch (self) {
            .v1_17 => drive.encodeDrive(allocator, request),
        };
    }

    pub fn encodeDriveUpdate(self: Backend, allocator: std.mem.Allocator, request: models.DriveUpdate) ![]u8 {
        return switch (self) {
            .v1_17 => drive.encodeDriveUpdate(allocator, request),
        };
    }

    pub fn encodeVsock(self: Backend, allocator: std.mem.Allocator, request: models.VsockConfiguration) ![]u8 {
        return switch (self) {
            .v1_17 => devices.encodeVsock(allocator, request),
        };
    }

    pub fn encodeEntropy(self: Backend, allocator: std.mem.Allocator, request: models.EntropyConfiguration) ![]u8 {
        return switch (self) {
            .v1_17 => devices.encodeEntropy(allocator, request),
        };
    }

    pub fn encodeSerial(self: Backend, allocator: std.mem.Allocator, request: models.SerialConfiguration) ![]u8 {
        return switch (self) {
            .v1_17 => devices.encodeSerial(allocator, request),
        };
    }

    pub fn encodePmem(self: Backend, allocator: std.mem.Allocator, request: models.PmemConfiguration) ![]u8 {
        return switch (self) {
            .v1_17 => devices.encodePmem(allocator, request),
        };
    }

    pub fn encodePmemUpdate(self: Backend, allocator: std.mem.Allocator, request: models.PmemUpdate) ![]u8 {
        return switch (self) {
            .v1_17 => devices.encodePmemUpdate(allocator, request),
        };
    }

    pub fn encodeNetworkInterface(self: Backend, allocator: std.mem.Allocator, request: models.NetworkInterfaceRequest) ![]u8 {
        return switch (self) {
            .v1_17 => network_interface.encodeNetworkInterface(allocator, request),
        };
    }

    pub fn encodeNetworkInterfaceUpdate(self: Backend, allocator: std.mem.Allocator, request: models.NetworkInterfaceUpdate) ![]u8 {
        return switch (self) {
            .v1_17 => network_interface.encodeNetworkInterfaceUpdate(allocator, request),
        };
    }

    pub fn decodeBalloon(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.BalloonConfiguration {
        return switch (self) {
            .v1_17 => balloon.decodeBalloon(allocator, body),
        };
    }

    pub fn decodeBalloonStatistics(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.BalloonStatistics {
        return switch (self) {
            .v1_17 => balloon.decodeBalloonStatistics(allocator, body),
        };
    }

    pub fn encodeBalloon(self: Backend, allocator: std.mem.Allocator, request: models.BalloonConfiguration) ![]u8 {
        return switch (self) {
            .v1_17 => balloon.encodeBalloon(allocator, request),
        };
    }

    pub fn encodeBalloonUpdate(self: Backend, allocator: std.mem.Allocator, request: models.BalloonUpdate) ![]u8 {
        return switch (self) {
            .v1_17 => balloon.encodeBalloonUpdate(allocator, request),
        };
    }

    pub fn encodeBalloonStatisticsUpdate(self: Backend, allocator: std.mem.Allocator, request: models.BalloonStatisticsUpdate) ![]u8 {
        return switch (self) {
            .v1_17 => balloon.encodeBalloonStatisticsUpdate(allocator, request),
        };
    }

    pub fn encodeBalloonHintingStart(self: Backend, allocator: std.mem.Allocator, request: models.BalloonHintingStartRequest) ![]u8 {
        return switch (self) {
            .v1_17 => balloon.encodeBalloonHintingStart(allocator, request),
        };
    }

    pub fn decodeBalloonHintingStatus(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.BalloonHintingStatus {
        return switch (self) {
            .v1_17 => balloon.decodeBalloonHintingStatus(allocator, body),
        };
    }

    pub fn encodeMemoryHotplug(self: Backend, allocator: std.mem.Allocator, request: models.MemoryHotplugConfiguration) ![]u8 {
        return switch (self) {
            .v1_17 => memory_hotplug.encodeMemoryHotplug(allocator, request),
        };
    }

    pub fn encodeMemoryHotplugUpdate(self: Backend, allocator: std.mem.Allocator, request: models.MemoryHotplugUpdate) ![]u8 {
        return switch (self) {
            .v1_17 => memory_hotplug.encodeMemoryHotplugUpdate(allocator, request),
        };
    }

    pub fn decodeMemoryHotplugStatus(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.MemoryHotplugStatus {
        return switch (self) {
            .v1_17 => memory_hotplug.decodeMemoryHotplugStatus(allocator, body),
        };
    }

    pub fn encodeMmdsConfiguration(self: Backend, allocator: std.mem.Allocator, request: models.MmdsConfiguration) ![]u8 {
        return switch (self) {
            .v1_17 => mmds.encodeMmdsConfiguration(allocator, request),
        };
    }

    pub fn encodeLogger(self: Backend, allocator: std.mem.Allocator, request: models.LoggerRequest) ![]u8 {
        return switch (self) {
            .v1_17 => observability.encodeLogger(allocator, request),
        };
    }

    pub fn encodeMetrics(self: Backend, allocator: std.mem.Allocator, request: models.MetricsRequest) ![]u8 {
        return switch (self) {
            .v1_17 => observability.encodeMetrics(allocator, request),
        };
    }

    pub fn encodeSnapshotCreate(self: Backend, allocator: std.mem.Allocator, request: models.SnapshotCreateRequest) ![]u8 {
        return switch (self) {
            .v1_17 => snapshot.encodeSnapshotCreate(allocator, request),
        };
    }

    pub fn encodeSnapshotLoad(self: Backend, allocator: std.mem.Allocator, request: models.SnapshotLoadRequest) ![]u8 {
        return switch (self) {
            .v1_17 => snapshot.encodeSnapshotLoad(allocator, request),
        };
    }
};
