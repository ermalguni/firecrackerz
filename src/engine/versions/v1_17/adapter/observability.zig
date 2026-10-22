const std = @import("std");
const wire = @import("../models.zig");
const models = @import("../../../models.zig");

pub fn encodeLogger(allocator: std.mem.Allocator, request: models.LoggerRequest) ![]u8 {
    const value: wire.Logger = .{
        .log_path = request.log_path,
        .level = request.level,
        .show_level = request.show_level,
        .show_log_origin = request.show_log_origin,
        .module = request.module,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeMetrics(allocator: std.mem.Allocator, request: models.MetricsRequest) ![]u8 {
    // The generated properties field is an untyped json.Value. Serialize the
    // schema's string-only map directly, without allocating a second map.
    const value = .{
        .metrics_path = request.metrics_path,
        .emit_id = request.emit_id,
        .properties = request.properties,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}
