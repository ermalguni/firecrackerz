const std = @import("std");
const Transport = @import("../internal/transport.zig").Transport;
const Backend = @import("../internal/backend.zig").Backend;
const models = @import("../models.zig");
const results = @import("../result.zig");
const http = @import("../internal/response.zig");

pub fn getBalloon(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.BalloonConfiguration) {
    var response = try transport.get("/balloon");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeBalloon(allocator, response.body) };
}

pub fn getBalloonStatistics(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.BalloonStatistics) {
    var response = try transport.get("/balloon/statistics");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeBalloonStatistics(allocator, response.body) };
}

pub fn putBalloon(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BalloonConfiguration) !results.Result(void) {
    const body = try backend.encodeBalloon(allocator, request);
    defer allocator.free(body);
    return http.putEmpty(allocator, transport, "/balloon", body);
}

pub fn patchBalloon(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BalloonUpdate) !results.Result(void) {
    const body = try backend.encodeBalloonUpdate(allocator, request);
    defer allocator.free(body);
    return http.patchEmpty(allocator, transport, "/balloon", body);
}

pub fn patchBalloonStatistics(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BalloonStatisticsUpdate) !results.Result(void) {
    const body = try backend.encodeBalloonStatisticsUpdate(allocator, request);
    defer allocator.free(body);
    return http.patchEmpty(allocator, transport, "/balloon/statistics", body);
}

pub fn startBalloonHinting(allocator: std.mem.Allocator, transport: *Transport, backend: Backend, request: models.BalloonHintingStartRequest) !results.Result(void) {
    const body = try backend.encodeBalloonHintingStart(allocator, request);
    defer allocator.free(body);
    return http.patchEmpty(allocator, transport, "/balloon/hinting/start", body);
}

pub fn stopBalloonHinting(allocator: std.mem.Allocator, transport: *Transport) !results.Result(void) {
    return http.patchEmpty(allocator, transport, "/balloon/hinting/stop", "");
}

pub fn getBalloonHintingStatus(allocator: std.mem.Allocator, transport: *Transport, backend: Backend) !results.Result(models.BalloonHintingStatus) {
    var response = try transport.get("/balloon/hinting/status");
    defer response.deinit();
    if (response.status != 200) return .{ .fault = .{
        .allocator = allocator,
        .status = response.status,
        .body = try allocator.dupe(u8, response.body),
    } };
    return .{ .success = try backend.decodeBalloonHintingStatus(allocator, response.body) };
}
