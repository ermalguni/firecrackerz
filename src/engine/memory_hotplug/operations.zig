const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn putMemoryHotplug(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MemoryHotplugConfiguration) !results.Result(void) {
    const body = try backend.encodeMemoryHotplug(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/hotplug/memory", body);
}

pub fn patchMemoryHotplug(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MemoryHotplugUpdate) !results.Result(void) {
    const body = try backend.encodeMemoryHotplugUpdate(allocator, request);
    defer allocator.free(body);
    return http.patchEmpty(allocator, transport, "/hotplug/memory", body);
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
