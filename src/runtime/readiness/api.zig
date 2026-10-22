const std = @import("std");
const engine = @import("../../engine/root.zig");
const Supervisor = @import("../../internal/supervisor.zig");

/// Races the complete engine handshake against child exit and one startup
/// deadline. The monitor is the sole child waiter; cancel it before shutdown.
pub fn wait(
    allocator: std.mem.Allocator,
    io: std.Io,
    process: *Supervisor,
    options: engine.ConnectOptions,
    deadline: std.Io.Timeout,
) !engine.Result(engine.Client) {
    if (deadline.toDurationFromNow(io).?.raw.nanoseconds <= 0) return error.StartupTimeout;
    var connection: ?engine.Result(engine.Client) = null;
    defer if (connection) |*result| result.deinit();
    const Completion = union(enum) {
        connected: anyerror!void,
        exited: anyerror!void,
        timeout: std.Io.Cancelable!void,
    };
    var completions: [3]Completion = undefined;
    var select = std.Io.Select(Completion).init(io, &completions);
    defer select.cancelDiscard();
    try select.concurrent(.connected, connect, .{ allocator, io, options, &connection });
    try select.concurrent(.exited, monitor, .{ io, process });
    try select.concurrent(.timeout, std.Io.Timeout.sleep, .{ deadline, io });
    switch (try select.await()) {
        .connected => |result| try result,
        .exited => |result| {
            try result;
            return error.ProcessExited;
        },
        .timeout => |result| {
            try result;
            return error.StartupTimeout;
        },
    }
    // Stop the sole waiter before observing the process from this task.
    select.cancelDiscard();
    if (try process.poll(io) != null) return error.ProcessExited;
    if (deadline.toDurationFromNow(io).?.raw.nanoseconds <= 0) return error.StartupTimeout;
    const result = connection.?;
    connection = null;
    return result;
}

fn connect(allocator: std.mem.Allocator, io: std.Io, options: engine.ConnectOptions, result: *?engine.Result(engine.Client)) !void {
    // Avoid running binary discovery repeatedly while the socket does not exist.
    while (true) {
        _ = std.Io.Dir.cwd().statFile(io, options.socket_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => return err,
        };
        result.* = engine.Client.connect(allocator, io, options) catch |err| switch (err) {
            error.ConnectionRefused, error.FileNotFound => {
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => return err,
        };
        return;
    }
}

fn monitor(io: std.Io, process: *Supervisor) !void {
    while (try process.poll(io) == null) {
        try io.sleep(.fromMilliseconds(10), .awake);
    }
}
