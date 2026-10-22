const RateLimiter = @import("../shared/rate_limiter.zig").RateLimiter;

/// Pre-boot drive creation/replacement. Strings are borrowed for the call.
/// Paths and sockets belong to Firecracker's filesystem namespace.
/// Virtio-block requires path_on_host and is_read_only; vhost-user uses socket.
/// Firecracker validates device-specific combinations and values.
pub const DriveRequest = struct {
    drive_id: []const u8,
    is_root_device: bool,
    partuuid: ?[]const u8 = null,
    cache_type: ?[]const u8 = null,
    is_read_only: ?bool = null,
    discard: ?bool = null,
    path_on_host: ?[]const u8 = null,
    rate_limiter: ?RateLimiter = null,
    io_engine: ?[]const u8 = null,
    blk_size: ?i64 = null,
    topology: ?BlockTopology = null,
    socket: ?[]const u8 = null,
};

/// Updates an existing drive, including after boot; does not attach a device.
/// Strings are borrowed. Null fields are omitted, not reset.
/// Coordinate backing-file changes with the guest to prevent concurrent I/O.
pub const DriveUpdate = struct {
    drive_id: []const u8,
    path_on_host: ?[]const u8 = null,
    rate_limiter: ?RateLimiter = null,
};

pub const BlockTopology = struct {
    physical_block_exp: ?i64 = null,
    alignment_offset: ?i64 = null,
    min_io_size: ?i64 = null,
    opt_io_size: ?i64 = null,
};
