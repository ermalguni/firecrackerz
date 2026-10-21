const std = @import("std");
const Transport = @import("transport.zig").Transport;
const Backend = @import("backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");

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

fn putEmpty(allocator: std.mem.Allocator, transport: *Transport, comptime path: []const u8, body: []const u8) !results.Result(void) {
    var response = try transport.put(path, body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}
