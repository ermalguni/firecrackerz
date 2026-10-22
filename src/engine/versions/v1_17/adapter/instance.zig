const std = @import("std");
const wire = @import("../models.zig");
const version = @import("../../../internal/version.zig");
const models = @import("../../../models.zig");

pub fn decodeVersion(allocator: std.mem.Allocator, body: []const u8) !version.Version {
    const parsed = try std.json.parseFromSlice(wire.FirecrackerVersion, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return version.parse(parsed.value.firecracker_version);
}

pub fn decodeInstanceInfo(allocator: std.mem.Allocator, body: []const u8) !models.InstanceInfo {
    const parsed = try std.json.parseFromSlice(wire.InstanceInfo, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    return .{
        .id = parsed.value.id,
        .state = parsed.value.state,
        .vmm_version = parsed.value.vmm_version,
        .app_name = parsed.value.app_name,
        .arena = parsed.arena,
    };
}
