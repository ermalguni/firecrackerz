const std = @import("std");
const fc = @import("firecrackerz").engine;

/// Configures output on an application-owned disposable Firecracker process.
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const flush = args.len == 5 and std.mem.eql(u8, args[3], "--flush");
    if ((!flush and args.len != 6) or !std.mem.eql(u8, args[args.len - 1], "--disposable")) {
        std.debug.print("Usage: {s} SOCKET EXECUTABLE LOG_PATH METRICS_PATH --disposable\n       {s} SOCKET EXECUTABLE --flush --disposable (after starting the VM)\n", .{ args[0], args[0] });
        return error.InvalidArguments;
    }
    var connected = try fc.Client.connect(init.gpa, init.io, .{
        .socket_path = args[1],
        .binary = .{ .executable = args[2] },
    });
    defer connected.deinit();
    switch (connected) {
        .fault => |fault| {
            std.debug.print("Connection HTTP {d}: {s}\n", .{ fault.status, fault.body });
            return error.ConnectionRejected;
        },
        .success => |*client| {
            if (flush) {
                var flushed = try client.flushMetrics();
                defer flushed.deinit();
                try requireSuccess(&flushed, "Metrics flush");
                std.debug.print("Metrics flush accepted; read the configured output in Firecracker's filesystem namespace.\n", .{});
                return;
            }
            var logger = try client.putLogger(.{
                .log_path = args[3],
                .level = "Debug",
                .show_level = true,
                .show_log_origin = true,
            });
            defer logger.deinit();
            try requireSuccess(&logger, "Logger");

            var properties: std.json.ArrayHashMap([]const u8) = .{};
            defer properties.deinit(init.gpa);
            try properties.map.put(init.gpa, "source", "firecrackerz");
            var metrics = try client.putMetrics(.{
                .metrics_path = args[4],
                .emit_id = true,
                .properties = properties,
            });
            defer metrics.deinit();
            try requireSuccess(&metrics, "Metrics");

            std.debug.print("Logging and metrics configured. Start the VM before invoking --flush.\n", .{});
        },
    }
}

fn requireSuccess(result: *const fc.Result(void), operation: []const u8) !void {
    switch (result.*) {
        .success => {},
        .fault => |fault| {
            std.debug.print("{s} HTTP {d}: {s}\n", .{ operation, fault.status, fault.body });
            return error.OperationRejected;
        },
    }
}
