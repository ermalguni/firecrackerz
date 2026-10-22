const std = @import("std");
const Transport = @import("transport.zig").Transport;
const Backend = @import("backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");

pub fn getInstanceInfo(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.InstanceInfo) {
    var response = try transport.get("/");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeInstanceInfo(allocator, response.body) };
}

pub fn getMachineConfiguration(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.MachineConfiguration) {
    var response = try transport.get("/machine-config");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeMachineConfiguration(allocator, response.body) };
}

pub fn getVmConfiguration(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.FullVmConfiguration) {
    var response = try transport.get("/vm/config");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeVmConfiguration(allocator, response.body) };
}

pub fn putMachineConfiguration(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MachineConfigurationRequest) !results.Result(void) {
    const body = try backend.encodeMachineConfiguration(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/machine-config", body);
}

pub fn patchMachineConfiguration(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MachineConfigurationUpdate) !results.Result(void) {
    const body = try backend.encodeMachineConfigurationUpdate(allocator, request);
    defer allocator.free(body);
    var response = try transport.patch("/machine-config", body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}

pub fn putCpuConfiguration(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.CpuConfiguration) !results.Result(void) {
    const body = try backend.encodeCpuConfiguration(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/cpu-config", body);
}

pub fn putGuestBootSource(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BootSourceRequest) !results.Result(void) {
    const body = try backend.encodeBootSource(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/boot-source", body);
}

pub fn putGuestDrive(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.DriveRequest) !results.Result(void) {
    const body = try backend.encodeDrive(allocator, request);
    defer allocator.free(body);
    // Escape one segment, not a whole path: IDs cannot inject routes or queries.
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.drive_id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/drives/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/drives/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    return putEmpty(allocator, transport, path, body);
}

pub fn patchGuestDrive(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.DriveUpdate) !results.Result(void) {
    const body = try backend.encodeDriveUpdate(allocator, request);
    defer allocator.free(body);
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.drive_id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/drives/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/drives/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    var response = try transport.patch(path, body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}

pub fn putGuestNetworkInterface(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.NetworkInterfaceRequest) !results.Result(void) {
    const body = try backend.encodeNetworkInterface(allocator, request);
    defer allocator.free(body);
    // Keep the interface ID within one escaped path segment.
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.iface_id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/network-interfaces/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/network-interfaces/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    return putEmpty(allocator, transport, path, body);
}

pub fn patchGuestNetworkInterface(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.NetworkInterfaceUpdate) !results.Result(void) {
    const body = try backend.encodeNetworkInterfaceUpdate(allocator, request);
    defer allocator.free(body);
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.iface_id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/network-interfaces/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/network-interfaces/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    var response = try transport.patch(path, body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}

pub fn getBalloon(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.BalloonConfiguration) {
    var response = try transport.get("/balloon");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeBalloon(allocator, response.body) };
}

pub fn getBalloonStatistics(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.BalloonStatistics) {
    var response = try transport.get("/balloon/statistics");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeBalloonStatistics(allocator, response.body) };
}

pub fn putBalloon(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BalloonConfiguration) !results.Result(void) {
    const body = try backend.encodeBalloon(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/balloon", body);
}

pub fn patchBalloon(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BalloonUpdate) !results.Result(void) {
    const body = try backend.encodeBalloonUpdate(allocator, request);
    defer allocator.free(body);
    var response = try transport.patch("/balloon", body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}

pub fn patchBalloonStatistics(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BalloonStatisticsUpdate) !results.Result(void) {
    const body = try backend.encodeBalloonStatisticsUpdate(allocator, request);
    defer allocator.free(body);
    var response = try transport.patch("/balloon/statistics", body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}

pub fn startBalloonHinting(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BalloonHintingStartRequest) !results.Result(void) {
    const body = try backend.encodeBalloonHintingStart(allocator, request);
    defer allocator.free(body);
    return patchHinting(allocator, transport, "/balloon/hinting/start", body);
}

pub fn stopBalloonHinting(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return patchHinting(allocator, transport, "/balloon/hinting/stop", "");
}

fn patchHinting(allocator: std.mem.Allocator, transport: *Transport, path: []const u8, body: []const u8) !results.Result(void) {
    var response = try transport.patch(path, body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}

pub fn getBalloonHintingStatus(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.BalloonHintingStatus) {
    var response = try transport.get("/balloon/hinting/status");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeBalloonHintingStatus(allocator, response.body) };
}

pub fn putMemoryHotplug(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MemoryHotplugConfiguration) !results.Result(void) {
    const body = try backend.encodeMemoryHotplug(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/hotplug/memory", body);
}

pub fn patchMemoryHotplug(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MemoryHotplugUpdate) !results.Result(void) {
    const body = try backend.encodeMemoryHotplugUpdate(allocator, request);
    defer allocator.free(body);
    var response = try transport.patch("/hotplug/memory", body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}

pub fn getMemoryHotplug(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.MemoryHotplugStatus) {
    var response = try transport.get("/hotplug/memory");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeMemoryHotplugStatus(allocator, response.body) };
}

pub fn putLogger(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.LoggerRequest) !results.Result(void) {
    const body = try backend.encodeLogger(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/logger", body);
}

pub fn putMetrics(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MetricsRequest) !results.Result(void) {
    const body = try backend.encodeMetrics(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/metrics", body);
}

pub fn flushMetrics(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return putEmpty(allocator, transport, "/actions", "{\"action_type\":\"FlushMetrics\"}");
}

pub fn startInstance(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    // Identical for supported contracts. A fixed action needs no request allocation.
    return putEmpty(allocator, transport, "/actions", "{\"action_type\":\"InstanceStart\"}");
}

pub fn sendCtrlAltDel(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return putEmpty(allocator, transport, "/actions", "{\"action_type\":\"SendCtrlAltDel\"}");
}

pub fn pauseInstance(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return patchVm(allocator, transport, "{\"state\":\"Paused\"}");
}

pub fn resumeInstance(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return patchVm(allocator, transport, "{\"state\":\"Resumed\"}");
}

pub fn createSnapshot(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.SnapshotCreateRequest) !results.Result(void) {
    const body = try backend.encodeSnapshotCreate(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/snapshot/create", body);
}

pub fn loadSnapshot(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.SnapshotLoadRequest) !results.Result(void) {
    const body = try backend.encodeSnapshotLoad(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/snapshot/load", body);
}

fn patchVm(allocator: std.mem.Allocator, transport: *Transport, body: []const u8) !results.Result(void) {
    var response = try transport.patch("/vm", body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}

fn putEmpty(allocator: std.mem.Allocator, transport: *Transport, path: []const u8, body: []const u8) !results.Result(void) {
    var response = try transport.put(path, body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}
