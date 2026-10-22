const std = @import("std");
const engine = @import("../../engine/root.zig");
const BootSpec = @import("../spec.zig").BootSpec;

/// No retries or compensation writes: the owner discards a partially configured
/// instance on failure. Every returned fault transfers ownership to the caller.
pub fn apply(io: std.Io, client: *engine.Client, spec: BootSpec, deadline: std.Io.Timeout) !engine.Result(void) {
    try checkpoint(io, deadline);
    const machine = try client.putMachineConfiguration(spec.machine);
    if (machine == .fault) return machine;
    try checkpoint(io, deadline);
    const source = try client.putGuestBootSource(spec.boot_source);
    if (source == .fault) return source;
    for (spec.drives) |drive| {
        try checkpoint(io, deadline);
        const result = try client.putGuestDrive(drive);
        if (result == .fault) return result;
    }
    for (spec.network_interfaces) |interface| {
        try checkpoint(io, deadline);
        const result = try client.putGuestNetworkInterface(interface);
        if (result == .fault) return result;
    }
    return .{ .success = {} };
}

pub fn checkpoint(io: std.Io, deadline: std.Io.Timeout) !void {
    try io.checkCancel();
    if (deadline.toDurationFromNow(io).?.raw.nanoseconds <= 0)
        return error.StartupTimeout;
}
