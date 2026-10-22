const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

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
    return http.putEmpty(allocator, transport, "/machine-config", body);
}

pub fn patchMachineConfiguration(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MachineConfigurationUpdate) !results.Result(void) {
    const body = try backend.encodeMachineConfigurationUpdate(allocator, request);
    defer allocator.free(body);
    return http.patchEmpty(allocator, transport, "/machine-config", body);
}
