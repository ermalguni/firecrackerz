const RateLimiter = @import("../shared/rate_limiter.zig").RateLimiter;
const TokenBucket = @import("../shared/rate_limiter.zig").TokenBucket;

/// Pre-boot vsock configuration. Request strings are borrowed for the call;
/// uds_path belongs to the Firecracker server's filesystem namespace.
pub const VsockConfiguration = struct {
    guest_cid: i64,
    uds_path: []const u8,
    vsock_id: ?[]const u8 = null,
};

/// Pre-boot entropy device configuration. Null rate limiters are omitted.
pub const EntropyConfiguration = struct {
    rate_limiter: ?RateLimiter = null,
};

/// Serial console configuration. The output path is borrowed for the call and
/// resolved by Firecracker, not opened locally. Null fields are omitted.
/// The limiter is a single token bucket, not a bandwidth/operations pair.
pub const SerialConfiguration = struct {
    serial_out_path: ?[]const u8 = null,
    rate_limiter: ?TokenBucket = null,
};

/// Pre-boot pmem configuration. Borrowed id selects both URL and body;
/// path_on_host is resolved by Firecracker. Null fields are omitted.
pub const PmemConfiguration = struct {
    id: []const u8,
    path_on_host: []const u8,
    root_device: ?bool = null,
    read_only: ?bool = null,
    rate_limiter: ?RateLimiter = null,
};

/// Post-boot pmem rate-limiter update. The borrowed ID selects URL and body.
/// Null omits the limiter; explicit zero-valued token buckets are sent.
pub const PmemUpdate = struct {
    id: []const u8,
    rate_limiter: ?RateLimiter = null,
};
