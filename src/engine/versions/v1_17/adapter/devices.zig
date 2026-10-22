const std = @import("std");
const wire = @import("../models.zig");
const models = @import("../../../models.zig");
const rate_limiter = @import("shared/rate_limiter.zig");

pub fn encodeVsock(allocator: std.mem.Allocator, request: models.VsockConfiguration) ![]u8 {
    const value: wire.Vsock = .{
        .guest_cid = request.guest_cid,
        .uds_path = request.uds_path,
        .vsock_id = request.vsock_id,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeEntropy(allocator: std.mem.Allocator, request: models.EntropyConfiguration) ![]u8 {
    const value: wire.EntropyDevice = .{
        .rate_limiter = rate_limiter.encodeRateLimiter(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeSerial(allocator: std.mem.Allocator, request: models.SerialConfiguration) ![]u8 {
    const value: wire.SerialDevice = .{
        .serial_out_path = request.serial_out_path,
        .rate_limiter = rate_limiter.encodeTokenBucket(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodePmem(allocator: std.mem.Allocator, request: models.PmemConfiguration) ![]u8 {
    const value: wire.Pmem = .{
        .id = request.id,
        .path_on_host = request.path_on_host,
        .root_device = request.root_device,
        .read_only = request.read_only,
        .rate_limiter = rate_limiter.encodeRateLimiter(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodePmemUpdate(allocator: std.mem.Allocator, request: models.PmemUpdate) ![]u8 {
    const value: wire.PartialPmem = .{
        .id = request.id,
        .rate_limiter = rate_limiter.encodeRateLimiter(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}
