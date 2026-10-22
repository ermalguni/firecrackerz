const std = @import("std");

/// Logger configuration. Strings are borrowed for the call. The destination
/// belongs to Firecracker's filesystem namespace; the client never opens it.
/// Null fields are omitted; Firecracker applies defaults and validates values.
pub const LoggerRequest = struct {
    log_path: ?[]const u8 = null,
    level: ?[]const u8 = null,
    show_level: ?bool = null,
    show_log_origin: ?bool = null,
    module: ?[]const u8 = null,
};

/// Metrics initialization. The path, property map, keys, and values are borrowed
/// during the call. The caller retains ownership of the map and its strings.
pub const MetricsRequest = struct {
    metrics_path: []const u8,
    emit_id: ?bool = null,
    properties: ?std.json.ArrayHashMap([]const u8) = null,
};
