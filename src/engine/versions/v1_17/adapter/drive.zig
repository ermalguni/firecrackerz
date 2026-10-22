const std = @import("std");
const wire = @import("../models.zig");
const models = @import("../../../models.zig");
const rate_limiter = @import("shared/rate_limiter.zig");

pub fn encodeDrive(allocator: std.mem.Allocator, request: models.DriveRequest) ![]u8 {
    const value: wire.Drive = .{
        .drive_id = request.drive_id,
        .is_root_device = request.is_root_device,
        .partuuid = request.partuuid,
        .cache_type = request.cache_type,
        .is_read_only = request.is_read_only,
        .discard = request.discard,
        .path_on_host = request.path_on_host,
        .rate_limiter = rate_limiter.encodeRateLimiter(request.rate_limiter),
        .io_engine = request.io_engine,
        .blk_size = request.blk_size,
        .topology = if (request.topology) |topology| .{
            .physical_block_exp = topology.physical_block_exp,
            .alignment_offset = topology.alignment_offset,
            .min_io_size = topology.min_io_size,
            .opt_io_size = topology.opt_io_size,
        } else null,
        .socket = request.socket,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeDriveUpdate(allocator: std.mem.Allocator, request: models.DriveUpdate) ![]u8 {
    const value: wire.PartialDrive = .{
        .drive_id = request.drive_id,
        .path_on_host = request.path_on_host,
        .rate_limiter = rate_limiter.encodeRateLimiter(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}
