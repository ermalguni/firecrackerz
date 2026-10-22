const std = @import("std");
const runtime = @import("firecrackerz").runtime;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) {
        std.debug.print("Usage: {s} FIRECRACKER_EXECUTABLE WORKSPACE_PARENT\n", .{args[0]});
        return error.InvalidArguments;
    }
    var vm = runtime.Vm.init(init.gpa, init.io);
    defer vm.deinit();
    defer vm.shutdown(2000) catch |err| {
        // A service must retain the handle and retry/report shutdown failures.
        // This short-lived example fails loudly instead of silently leaking it.
        std.debug.panic("Runtime shutdown failed: {s}", .{@errorName(err)});
    };
    var started = vm.start(.{
        .executable = args[1],
        .workspace_parent = args[2],
    }) catch |err| {
        if (vm.last_exit) |term| std.debug.print("Child {f}\n", .{term});
        return err;
    };
    defer started.deinit();
    switch (started) {
        .fault => |fault| {
            std.debug.print("Handshake HTTP {d}: {s}\n", .{ fault.status, fault.body });
            return error.HandshakeRejected;
        },
        .success => {},
    }
    const client = try vm.client();
    var info = try client.getInstanceInfo();
    defer info.deinit();
    switch (info) {
        .success => |value| std.debug.print("API ready: id={s}, state={s}, version={s}\nWorkspace: {s}\n", .{
            value.id, value.state, value.vmm_version, vm.workspace.?.path,
        }),
        .fault => |fault| {
            std.debug.print("Instance HTTP {d}: {s}\n", .{ fault.status, fault.body });
            return error.InstanceInfoRejected;
        },
    }
    try vm.shutdown(2000);
    std.debug.print("Child reaped; owned workspace removed.\n", .{});
}
