const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");

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
