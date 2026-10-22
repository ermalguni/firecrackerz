const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn putGuestVsock(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.VsockConfiguration) !results.Result(void) {
    const body = try backend.encodeVsock(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/vsock", body);
}

pub fn putEntropy(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.EntropyConfiguration) !results.Result(void) {
    const body = try backend.encodeEntropy(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/entropy", body);
}

pub fn putSerial(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.SerialConfiguration) !results.Result(void) {
    const body = try backend.encodeSerial(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/serial", body);
}

pub fn putGuestPmem(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.PmemConfiguration) !results.Result(void) {
    const body = try backend.encodePmem(allocator, request);
    defer allocator.free(body);
    // Escape only the device ID, keeping it within a single path segment.
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/pmem/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/pmem/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    return http.putEmpty(allocator, transport, path, body);
}

pub fn patchGuestPmem(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.PmemUpdate) !results.Result(void) {
    const body = try backend.encodePmemUpdate(allocator, request);
    defer allocator.free(body);
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/pmem/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/pmem/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    return http.patchEmpty(allocator, transport, path, body);
}
