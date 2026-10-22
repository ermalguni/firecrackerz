const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn putGuestBootSource(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BootSourceRequest) !results.Result(void) {
    const body = try backend.encodeBootSource(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/boot-source", body);
}
