const std = @import("std");
const wire = @import("../models.zig");
const models = @import("../../../models.zig");

pub fn encodeMemoryHotplug(allocator: std.mem.Allocator, request: models.MemoryHotplugConfiguration) ![]u8 {
    const value: wire.MemoryHotplugConfig = .{
        .total_size_mib = request.total_size_mib,
        .slot_size_mib = request.slot_size_mib,
        .block_size_mib = request.block_size_mib,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeMemoryHotplugUpdate(allocator: std.mem.Allocator, request: models.MemoryHotplugUpdate) ![]u8 {
    const value: wire.MemoryHotplugSizeUpdate = .{ .requested_size_mib = request.requested_size_mib };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn decodeMemoryHotplugStatus(allocator: std.mem.Allocator, body: []const u8) !models.MemoryHotplugStatus {
    const parsed = try std.json.parseFromSlice(wire.MemoryHotplugStatus, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return .{
        .total_size_mib = parsed.value.total_size_mib,
        .slot_size_mib = parsed.value.slot_size_mib,
        .block_size_mib = parsed.value.block_size_mib,
        .plugged_size_mib = parsed.value.plugged_size_mib,
        .requested_size_mib = parsed.value.requested_size_mib,
    };
}
