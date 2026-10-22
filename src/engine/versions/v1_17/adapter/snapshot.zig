const std = @import("std");
const wire = @import("../models.zig");
const models = @import("../../../models.zig");

pub fn encodeSnapshotCreate(allocator: std.mem.Allocator, request: models.SnapshotCreateRequest) ![]u8 {
    const value: wire.SnapshotCreateParams = .{
        .mem_file_path = request.mem_file_path,
        .snapshot_path = request.snapshot_path,
        .snapshot_type = request.snapshot_type,
        .sync_snapshot_files = request.sync_snapshot_files,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeSnapshotLoad(allocator: std.mem.Allocator, request: models.SnapshotLoadRequest) ![]u8 {
    // The public override entries match this contract's JSON shape. Borrow the
    // slice instead of allocating a second array of generated wire entries.
    const value = .{
        .snapshot_path = request.snapshot_path,
        .mem_backend = if (request.mem_backend) |backend| @as(wire.MemoryBackend, .{
            .backend_type = backend.backend_type,
            .backend_path = backend.backend_path,
        }) else null,
        .mem_file_path = request.mem_file_path,
        .track_dirty_pages = request.track_dirty_pages,
        .enable_diff_snapshots = request.enable_diff_snapshots,
        .resume_vm = request.resume_vm,
        .network_overrides = request.network_overrides,
        .vsock_override = if (request.vsock_override) |vsock| @as(wire.VsockOverride, .{
            .uds_path = vsock.uds_path,
        }) else null,
        .clock_realtime = request.clock_realtime,
        .huge_pages = request.huge_pages,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}
