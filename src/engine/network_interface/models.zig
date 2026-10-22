const RateLimiter = @import("../shared/rate_limiter.zig").RateLimiter;

/// Pre-boot network interface creation/replacement. Strings are borrowed for
/// the call. The TAP device must already exist in Firecracker's network namespace.
/// Firecracker validates MAC, MTU, rate limits, and lifecycle restrictions.
pub const NetworkInterfaceRequest = struct {
    iface_id: []const u8,
    host_dev_name: []const u8,
    guest_mac: ?[]const u8 = null,
    mtu: ?i64 = null,
    rx_rate_limiter: ?RateLimiter = null,
    tx_rate_limiter: ?RateLimiter = null,
};

/// Updates rate limiters on an existing interface, including after boot.
/// The ID is borrowed. Null fields are omitted, leaving those limits unchanged.
pub const NetworkInterfaceUpdate = struct {
    iface_id: []const u8,
    rx_rate_limiter: ?RateLimiter = null,
    tx_rate_limiter: ?RateLimiter = null,
};
