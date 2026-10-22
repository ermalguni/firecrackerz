const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn createSnapshot(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.SnapshotCreateRequest) !results.Result(void) {
    const body = try backend.encodeSnapshotCreate(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/snapshot/create", body);
}

pub fn loadSnapshot(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.SnapshotLoadRequest) !results.Result(void) {
    const body = try backend.encodeSnapshotLoad(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/snapshot/load", body);
}
