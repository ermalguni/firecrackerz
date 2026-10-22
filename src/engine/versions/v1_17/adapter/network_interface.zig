const std = @import("std");
const wire = @import("../models.zig");
const models = @import("../../../models.zig");
const rate_limiter = @import("shared/rate_limiter.zig");

pub fn encodeNetworkInterface(allocator: std.mem.Allocator, request: models.NetworkInterfaceRequest) ![]u8 {
    const value: wire.NetworkInterface = .{
        .iface_id = request.iface_id,
        .host_dev_name = request.host_dev_name,
        .guest_mac = request.guest_mac,
        .mtu = request.mtu,
        .rx_rate_limiter = rate_limiter.encodeRateLimiter(request.rx_rate_limiter),
        .tx_rate_limiter = rate_limiter.encodeRateLimiter(request.tx_rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeNetworkInterfaceUpdate(allocator: std.mem.Allocator, request: models.NetworkInterfaceUpdate) ![]u8 {
    const value: wire.PartialNetworkInterface = .{
        .iface_id = request.iface_id,
        .rx_rate_limiter = rate_limiter.encodeRateLimiter(request.rx_rate_limiter),
        .tx_rate_limiter = rate_limiter.encodeRateLimiter(request.tx_rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}
