const std = @import("std");
const wire = @import("models.zig");
const version = @import("../../internal/version.zig");
const models = @import("../../models.zig");

pub fn decodeVersion(allocator: std.mem.Allocator, body: []const u8) !version.Version {
    const parsed = try std.json.parseFromSlice(wire.FirecrackerVersion, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return version.parse(parsed.value.firecracker_version);
}

pub fn decodeMachineConfiguration(allocator: std.mem.Allocator, body: []const u8) !models.MachineConfiguration {
    const parsed = try std.json.parseFromSlice(wire.MachineConfiguration, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    // Transfer the parse arena, not the wire type. Strings must outlive the HTTP response.
    return .{
        .vcpu_count = parsed.value.vcpu_count,
        .mem_size_mib = parsed.value.mem_size_mib,
        .smt = parsed.value.smt,
        .track_dirty_pages = parsed.value.track_dirty_pages,
        .cpu_template = parsed.value.cpu_template,
        .huge_pages = parsed.value.huge_pages,
        .arena = parsed.arena,
    };
}

pub fn encodeMachineConfiguration(allocator: std.mem.Allocator, request: models.MachineConfigurationRequest) ![]u8 {
    const value: wire.MachineConfiguration = .{
        .vcpu_count = request.vcpu_count,
        .mem_size_mib = request.mem_size_mib,
        .smt = request.smt,
        .track_dirty_pages = request.track_dirty_pages,
        .cpu_template = request.cpu_template,
        .huge_pages = request.huge_pages,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeBootSource(allocator: std.mem.Allocator, request: models.BootSourceRequest) ![]u8 {
    const value: wire.BootSource = .{
        .kernel_image_path = request.kernel_image_path,
        .boot_args = request.boot_args,
        .initrd_path = request.initrd_path,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}
