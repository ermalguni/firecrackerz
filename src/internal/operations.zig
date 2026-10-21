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
