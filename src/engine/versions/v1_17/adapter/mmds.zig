const std = @import("std");
const wire = @import("../models.zig");
const models = @import("../../../models.zig");

pub fn encodeMmdsConfiguration(allocator: std.mem.Allocator, request: models.MmdsConfiguration) ![]u8 {
    const value: wire.MmdsConfig = .{
        .network_interfaces = request.network_interfaces,
        .version = request.version,
        .imds_compat = request.imds_compat,
        .ipv4_address = request.ipv4_address,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}
