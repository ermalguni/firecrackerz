const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn putCpuConfiguration(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.CpuConfiguration) !results.Result(void) {
    const body = try backend.encodeCpuConfiguration(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/cpu-config", body);
}
