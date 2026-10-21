const std = @import("std");
const wire = @import("models.zig");
const version = @import("../../internal/version.zig");

pub fn decodeVersion(allocator: std.mem.Allocator, body: []const u8) !version.Version {
    const parsed = try std.json.parseFromSlice(wire.FirecrackerVersion, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return version.parse(parsed.value.firecracker_version);
}
