const std = @import("std");
const fc = @import("firecrackerz");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) return error.InvalidArguments;
    const mode = args[3];
    var vm = fc.runtime.Vm.init(init.gpa, init.io);
    defer vm.deinit();
    defer assertNoChildren();
    const options: fc.runtime.StartOptions = .{
        .executable = args[1],
        .workspace_parent = args[2],
        .startup_timeout_ms = if (std.mem.eql(u8, mode, "cancel")) 10000 else 700,
    };
    const result = if (std.mem.eql(u8, mode, "cancel")) blk: {
        var future = try init.io.concurrent(fc.runtime.Vm.start, .{ &vm, options });
        try init.io.sleep(.fromMilliseconds(200), .awake);
        break :blk future.cancel(init.io);
    } else vm.start(options);
    var started = result catch |err| {
        const expected = if (std.mem.eql(u8, mode, "cancel")) "Canceled" else if (std.mem.eql(u8, mode, "rollback")) "ProcessExited" else mode;
        if (!std.mem.eql(u8, @errorName(err), expected)) {
            std.debug.print("Expected {s}, got {s}\n", .{ expected, @errorName(err) });
            try vm.shutdown(1000);
            return error.UnexpectedStartupError;
        }
        if (err == error.ProcessExited) {
            const term = vm.last_exit orelse return error.MissingExitStatus;
            switch (term) {
                .exited => |code| if (code != 23) return error.WrongExitCode,
                else => return error.WrongExitKind,
            }
        }
        if (std.mem.eql(u8, mode, "rollback")) {
            if (vm.cleanup_error == null or vm.workspace == null or vm.process != null)
                return error.LostRollbackOwnership;
            var dir = try std.Io.Dir.cwd().openDir(init.io, vm.workspace.?.path, .{});
            defer dir.close(init.io);
            _ = try dir.statFile(init.io, "borrowed", .{});
            try dir.deleteFile(init.io, "borrowed");
        } else if (vm.cleanup_error != null) return error.RollbackFailed;
        try vm.shutdown(1000);
        std.debug.print("PASS {s}\n", .{mode});
        return;
    };
    defer started.deinit();
    switch (started) {
        .fault => |fault| {
            if (!std.mem.eql(u8, mode, "fault")) return error.UnexpectedFault;
            if (fault.status != 503 or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"unavailable\"}"))
                return error.WrongFault;
            if (vm.cleanup_error != null) return error.RollbackFailed;
        },
        .success => {
            if (!std.mem.eql(u8, mode, "success") and !std.mem.eql(u8, mode, "kill") and !std.mem.eql(u8, mode, "cleanup") and !std.mem.eql(u8, mode, "shutdown-cancel"))
                return error.UnexpectedSuccess;
            const client = try vm.client();
            var info = try client.getInstanceInfo();
            defer info.deinit();
            switch (info) {
                .success => |value| if (!std.mem.eql(u8, value.state, "Not started")) return error.UnexpectedInstanceState,
                .fault => return error.InstanceInfoRejected,
            }
            if (std.mem.eql(u8, mode, "shutdown-cancel")) {
                var future = try init.io.concurrent(fc.runtime.Vm.shutdown, .{ &vm, @as(u32, 10000) });
                try init.io.sleep(.fromMilliseconds(100), .awake);
                if (future.cancel(init.io)) |_| return error.UnexpectedShutdown else |err| {
                    if (err != error.Canceled) return err;
                }
                if (vm.process == null or vm.workspace == null or vm.connection != null)
                    return error.LostShutdownOwnership;
            }
            if (std.mem.eql(u8, mode, "cleanup")) {
                // Simulates caller-owned unexpected content: runtime must not
                // recursively erase it to make shutdown succeed.
                var dir = try std.Io.Dir.cwd().openDir(init.io, vm.workspace.?.path, .{});
                defer dir.close(init.io);
                const file = try dir.createFile(init.io, "borrowed", .{});
                file.close(init.io);
                if (vm.shutdown(1000)) |_| return error.DeletedBorrowedFile else |_| {}
                if (vm.workspace == null or vm.process != null or vm.cleanup_error == null)
                    return error.LostCleanupOwnership;
                _ = try dir.statFile(init.io, "borrowed", .{});
                try dir.deleteFile(init.io, "borrowed");
            }
        },
    }
    try vm.shutdown(1000);
    if (std.mem.eql(u8, mode, "kill")) {
        switch (vm.last_exit orelse return error.MissingExitStatus) {
            .signal => |signal| if (signal != .KILL) return error.ExpectedKill,
            else => return error.ExpectedSignalExit,
        }
    }
    try vm.shutdown(1000);
    std.debug.print("PASS {s}\n", .{mode});
}

fn assertNoChildren() void {
    const linux = std.os.linux;
    var info: linux.siginfo_t = undefined;
    // This standalone runner owns every successfully spawned child, including
    // version probes. Timeout/cancellation must not abandon a live child or zombie.
    const err = linux.errno(linux.waitid(.ALL, 0, &info, linux.W.EXITED | linux.W.NOHANG, null));
    if (err != .CHILD) std.debug.panic("Leaked child after runtime scenario: {t}", .{err});
}
