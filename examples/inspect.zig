const std = @import("std");
const fc = @import("firecrackerz");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) {
        std.debug.print("Usage: {s} SOCKET FIRECRACKER_EXECUTABLE\n", .{args[0]});
        return error.InvalidArguments;
    }
    var result = try fc.Client.connect(init.gpa, init.io, .{
        .socket_path = args[1],
        .binary = .{ .executable = args[2] },
    });
    defer result.deinit();
    switch (result) {
        .success => |*client| {
            const info = client.info();
            const v = info.running_version;
            std.debug.print("Connected: {s}; Firecracker {d}.{d}.{d}; contract {s}\n", .{
                info.executable_path, v.major, v.minor, v.patch, @tagName(info.contract),
            });
        },
        .fault => |fault| {
            std.debug.print("Firecracker HTTP {d}: {s}\n", .{ fault.status, fault.body });
            return error.HandshakeRejected;
        },
    }
}
