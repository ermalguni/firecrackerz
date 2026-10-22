const std = @import("std");
const version = @import("version.zig");
const models = @import("../models.zig");
const v1_17 = @import("../versions/v1_17/adapter.zig");

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
            .v1_17 => v1_17.decodeVersion(allocator, body),
        };
    }

    pub fn decodeInstanceInfo(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.InstanceInfo {
        return switch (self) {
            .v1_17 => v1_17.decodeInstanceInfo(allocator, body),
        };
    }

    pub fn decodeMachineConfiguration(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.MachineConfiguration {
        return switch (self) {
            .v1_17 => v1_17.decodeMachineConfiguration(allocator, body),
        };
    }

    pub fn decodeVmConfiguration(self: Backend, allocator: std.mem.Allocator, body: []const u8) !models.FullVmConfiguration {
        return switch (self) {
            .v1_17 => v1_17.decodeVmConfiguration(allocator, body),
        };
    }

    pub fn encodeMachineConfiguration(self: Backend, allocator: std.mem.Allocator, request: models.MachineConfigurationRequest) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeMachineConfiguration(allocator, request),
        };
    }

    pub fn encodeMachineConfigurationUpdate(self: Backend, allocator: std.mem.Allocator, request: models.MachineConfigurationUpdate) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeMachineConfigurationUpdate(allocator, request),
        };
    }

    pub fn encodeCpuConfiguration(self: Backend, allocator: std.mem.Allocator, request: models.CpuConfiguration) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeCpuConfiguration(allocator, request),
        };
    }

    pub fn encodeBootSource(self: Backend, allocator: std.mem.Allocator, request: models.BootSourceRequest) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeBootSource(allocator, request),
        };
    }

    pub fn encodeDrive(self: Backend, allocator: std.mem.Allocator, request: models.DriveRequest) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeDrive(allocator, request),
        };
    }

    pub fn encodeNetworkInterface(self: Backend, allocator: std.mem.Allocator, request: models.NetworkInterfaceRequest) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeNetworkInterface(allocator, request),
        };
    }

    pub fn encodeLogger(self: Backend, allocator: std.mem.Allocator, request: models.LoggerRequest) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeLogger(allocator, request),
        };
    }

    pub fn encodeMetrics(self: Backend, allocator: std.mem.Allocator, request: models.MetricsRequest) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeMetrics(allocator, request),
        };
    }

    pub fn encodeSnapshotCreate(self: Backend, allocator: std.mem.Allocator, request: models.SnapshotCreateRequest) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeSnapshotCreate(allocator, request),
        };
    }

    pub fn encodeSnapshotLoad(self: Backend, allocator: std.mem.Allocator, request: models.SnapshotLoadRequest) ![]u8 {
        return switch (self) {
            .v1_17 => v1_17.encodeSnapshotLoad(allocator, request),
        };
    }
};
