const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn putLogger(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.LoggerRequest) !results.Result(void) {
    const body = try backend.encodeLogger(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/logger", body);
}

pub fn putMetrics(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.MetricsRequest) !results.Result(void) {
    const body = try backend.encodeMetrics(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/metrics", body);
}

pub fn flushMetrics(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return http.putEmpty(allocator, transport, "/actions", "{\"action_type\":\"FlushMetrics\"}");
}
