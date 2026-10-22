const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

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

pub fn startInstance(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    // Identical for supported contracts. A fixed action needs no request allocation.
    return http.putEmpty(allocator, transport, "/actions", "{\"action_type\":\"InstanceStart\"}");
}

pub fn sendCtrlAltDel(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return http.putEmpty(allocator, transport, "/actions", "{\"action_type\":\"SendCtrlAltDel\"}");
}

pub fn pauseInstance(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return http.patchEmpty(allocator, transport, "/vm", "{\"state\":\"Paused\"}");
}

pub fn resumeInstance(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return http.patchEmpty(allocator, transport, "/vm", "{\"state\":\"Resumed\"}");
}
