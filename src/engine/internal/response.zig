const std = @import("std");
const Transport = @import("transport.zig").Transport;
const results = @import("../result.zig");

pub fn putEmpty(allocator: std.mem.Allocator, transport: *Transport, path: []const u8, body: []const u8) !results.Result(void) {
    var response = try transport.put(path, body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}

pub fn patchEmpty(allocator: std.mem.Allocator, transport: *Transport, path: []const u8, body: []const u8) !results.Result(void) {
    var response = try transport.patch(path, body);
    defer response.deinit();
    if (response.status != 204) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = {} };
}
