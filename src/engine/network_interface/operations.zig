const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn putGuestNetworkInterface(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.NetworkInterfaceRequest) !results.Result(void) {
    const body = try backend.encodeNetworkInterface(allocator, request);
    defer allocator.free(body);
    // Keep the interface ID within one escaped path segment.
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.iface_id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/network-interfaces/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/network-interfaces/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    return http.putEmpty(allocator, transport, path, body);
}

pub fn patchGuestNetworkInterface(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.NetworkInterfaceUpdate) !results.Result(void) {
    const body = try backend.encodeNetworkInterfaceUpdate(allocator, request);
    defer allocator.free(body);
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.iface_id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/network-interfaces/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/network-interfaces/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    return http.patchEmpty(allocator, transport, path, body);
}
