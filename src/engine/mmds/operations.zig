const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn putMmdsConfiguration(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MmdsConfiguration) !results.Result(void) {
    const body = try backend.encodeMmdsConfiguration(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/mmds/config", body);
}

pub fn getMmds(allocator: std.mem.Allocator, transport: *Transport) !results.Result(models.MmdsContents) {
    var response = try transport.get("/mmds");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    // Arbitrary JSON has no version-specific wire conversion. Own every string,
    // including number lexemes, before releasing the transport response.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response.body, .{
        .allocate = .alloc_always,
        .parse_numbers = false,
    });
    return .{ .success = .{ .value = parsed.value, .arena = parsed.arena } };
}

pub fn putMmds(allocator: std.mem.Allocator, transport: *Transport, json: []const u8) !results.Result(void) {
    return http.putEmpty(allocator, transport, "/mmds", json);
}

pub fn patchMmds(allocator: std.mem.Allocator, transport: *Transport, json: []const u8) !results.Result(void) {
    return http.patchEmpty(allocator, transport, "/mmds", json);
}
