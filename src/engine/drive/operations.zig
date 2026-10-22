const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn putGuestDrive(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.DriveRequest) !results.Result(void) {
    const body = try backend.encodeDrive(allocator, request);
    defer allocator.free(body);
    // Escape one segment, not a whole path: IDs cannot inject routes or queries.
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.drive_id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/drives/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/drives/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    return http.putEmpty(allocator, transport, path, body);
}

pub fn patchGuestDrive(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.DriveUpdate) !results.Result(void) {
    const body = try backend.encodeDriveUpdate(allocator, request);
    defer allocator.free(body);
    var buffer: [512]u8 = undefined;
    const args = .{std.fmt.alt(@as(std.Uri.Component, .{ .raw = request.drive_id }), .formatEscaped)};
    const path = std.mem.print(&buffer, "/drives/{f}", args) catch
        try std.fmt.allocPrint(allocator, "/drives/{f}", args);
    defer if (path.ptr != &buffer) allocator.free(path);
    return http.patchEmpty(allocator, transport, path, body);
}
