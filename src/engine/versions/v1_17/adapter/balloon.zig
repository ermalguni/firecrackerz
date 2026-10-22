const std = @import("std");
const wire = @import("../models.zig");
const models = @import("../../../models.zig");

pub fn decodeBalloon(allocator: std.mem.Allocator, body: []const u8) !models.BalloonConfiguration {
    const parsed = try std.json.parseFromSlice(wire.Balloon, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return .{
        .amount_mib = parsed.value.amount_mib,
        .deflate_on_oom = parsed.value.deflate_on_oom,
        .stats_polling_interval_s = parsed.value.stats_polling_interval_s,
        .free_page_hinting = parsed.value.free_page_hinting,
        .free_page_reporting = parsed.value.free_page_reporting,
    };
}

pub fn decodeBalloonStatistics(allocator: std.mem.Allocator, body: []const u8) !models.BalloonStatistics {
    const parsed = try std.json.parseFromSlice(wire.BalloonStats, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return .{
        .target_pages = parsed.value.target_pages,
        .actual_pages = parsed.value.actual_pages,
        .target_mib = parsed.value.target_mib,
        .actual_mib = parsed.value.actual_mib,
        .swap_in = parsed.value.swap_in,
        .swap_out = parsed.value.swap_out,
        .major_faults = parsed.value.major_faults,
        .minor_faults = parsed.value.minor_faults,
        .free_memory = parsed.value.free_memory,
        .total_memory = parsed.value.total_memory,
        .available_memory = parsed.value.available_memory,
        .disk_caches = parsed.value.disk_caches,
        .hugetlb_allocations = parsed.value.hugetlb_allocations,
        .hugetlb_failures = parsed.value.hugetlb_failures,
        .oom_kill = parsed.value.oom_kill,
        .alloc_stall = parsed.value.alloc_stall,
        .async_scan = parsed.value.async_scan,
        .direct_scan = parsed.value.direct_scan,
        .async_reclaim = parsed.value.async_reclaim,
        .direct_reclaim = parsed.value.direct_reclaim,
    };
}

pub fn encodeBalloon(allocator: std.mem.Allocator, request: models.BalloonConfiguration) ![]u8 {
    const value: wire.Balloon = .{
        .amount_mib = request.amount_mib,
        .deflate_on_oom = request.deflate_on_oom,
        .stats_polling_interval_s = request.stats_polling_interval_s,
        .free_page_hinting = request.free_page_hinting,
        .free_page_reporting = request.free_page_reporting,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeBalloonUpdate(allocator: std.mem.Allocator, request: models.BalloonUpdate) ![]u8 {
    const value: wire.BalloonUpdate = .{ .amount_mib = request.amount_mib };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeBalloonStatisticsUpdate(allocator: std.mem.Allocator, request: models.BalloonStatisticsUpdate) ![]u8 {
    const value: wire.BalloonStatsUpdate = .{ .stats_polling_interval_s = request.stats_polling_interval_s };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeBalloonHintingStart(allocator: std.mem.Allocator, request: models.BalloonHintingStartRequest) ![]u8 {
    const value: wire.BalloonStartCmd = .{ .acknowledge_on_stop = request.acknowledge_on_stop };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn decodeBalloonHintingStatus(allocator: std.mem.Allocator, body: []const u8) !models.BalloonHintingStatus {
    const parsed = try std.json.parseFromSlice(wire.BalloonHintingStatus, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return .{ .host_cmd = parsed.value.host_cmd, .guest_cmd = parsed.value.guest_cmd };
}
