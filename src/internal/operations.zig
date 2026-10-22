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

pub fn putMachineConfiguration(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MachineConfigurationRequest) !results.Result(void) {
    const body = try backend.encodeMachineConfiguration(allocator, request);
    defer allocator.free(body);
    return putEmpty(allocator, transport, "/machine-config", body);
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
