const std = @import("std");
const engine = @import("../../engine/root.zig");
const Supervisor = @import("../../internal/supervisor.zig");
const BootSpec = @import("../spec.zig").BootSpec;
const configuration = @import("configuration.zig");

/// Race configuration/start against the remaining launch deadline and child
/// exit. This monitor is the sole waiter until all concurrent work is canceled.
pub fn run(io: std.Io, client: *engine.Client, process: *Supervisor, spec: BootSpec, deadline: std.Io.Timeout) !engine.Result(void) {
    try configuration.checkpoint(io, deadline);
    var response: ?engine.Result(void) = null;
    defer if (response) |*result| result.deinit();
    const Completion = union(enum) {
        configured: anyerror!void,
        exited: anyerror!void,
        timeout: std.Io.Cancelable!void,
    };
    var completions: [3]Completion = undefined;
    var select = std.Io.Select(Completion).init(io, &completions);
    defer select.cancelDiscard();
    try select.concurrent(.configured, configureAndStart, .{ io, client, spec, deadline, &response });
    try select.concurrent(.exited, monitor, .{ io, process });
    try select.concurrent(.timeout, std.Io.Timeout.sleep, .{ deadline, io });
    const completion = try select.await();
    select.cancelDiscard();
    // Poll only after the monitor has stopped. Prefer a known child exit over
    // the transport error caused by that exit.
    if (try process.poll(io) != null) return error.ProcessExited;
    switch (completion) {
        .configured => |result| try result,
        .exited => |result| {
            try result;
            return error.ProcessExited;
        },
        .timeout => |result| {
            try result;
            return error.StartupTimeout;
        },
    }
    try configuration.checkpoint(io, deadline);
    const result = response.?;
    response = null;
    return result;
}

fn configureAndStart(io: std.Io, client: *engine.Client, spec: BootSpec, deadline: std.Io.Timeout, response: *?engine.Result(void)) !void {
    const configured = try configuration.apply(io, client, spec, deadline);
    if (configured == .fault) {
        response.* = configured;
        return;
    }
    try configuration.checkpoint(io, deadline);
    response.* = try client.startInstance();
}

fn monitor(io: std.Io, process: *Supervisor) !void {
    while (try process.poll(io) == null) {
        try io.sleep(.fromMilliseconds(10), .awake);
    }
}
