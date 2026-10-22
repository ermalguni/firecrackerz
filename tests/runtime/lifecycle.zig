const std = @import("std");
const fc = @import("firecrackerz");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) return error.InvalidArguments;
    const mode = args[3];
    if (std.mem.startsWith(u8, mode, "boot-"))
        return runBoot(init, args[1], args[2], mode);
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

fn runBoot(init: std.process.Init, executable: []const u8, parent: []const u8, mode: []const u8) !void {
    var vm = fc.runtime.Vm.init(init.gpa, init.io);
    defer vm.deinit();
    defer assertNoChildren();
    const allocator = init.arena.allocator();
    const kernel = try std.fmt.allocPrint(allocator, "{s}/kernel image", .{parent});
    const initrd = try std.fmt.allocPrint(allocator, "{s}/initrd", .{parent});
    const rootfs = try std.fmt.allocPrint(allocator, "{s}/root disk", .{parent});
    const data = try std.fmt.allocPrint(allocator, "{s}/data disk", .{parent});
    const drives = [_]fc.engine.models.DriveRequest{
        .{ .drive_id = "rootfs", .is_root_device = true, .is_read_only = true, .path_on_host = rootfs },
        .{ .drive_id = "data", .is_root_device = false, .is_read_only = false, .path_on_host = data },
    };
    const spec: fc.runtime.BootSpec = .{
        .machine = .{ .vcpu_count = 2, .mem_size_mib = 256, .smt = false, .track_dirty_pages = true },
        .boot_source = .{ .kernel_image_path = kernel, .initrd_path = initrd, .boot_args = "console=ttyS0 reboot=k panic=1 pci=off" },
        .drives = &drives,
        .network_interfaces = if (std.mem.eql(u8, mode, "boot-no-network")) &.{} else &.{
            .{ .iface_id = "eth0", .host_dev_name = "caller-tap0", .guest_mac = "02:00:00:00:00:01" },
            .{ .iface_id = "eth1", .host_dev_name = "caller-tap1", .mtu = 1500 },
        },
    };
    const cancel = std.mem.eql(u8, mode, "boot-cancel") or std.mem.eql(u8, mode, "boot-nic-cancel");
    const options: fc.runtime.StartOptions = .{
        .executable = executable,
        .workspace_parent = parent,
        .startup_timeout_ms = if (cancel) 10000 else 700,
        .request_timeout_ms = 5000,
    };
    const result = if (cancel) blk: {
        var future = try init.io.concurrent(fc.runtime.Vm.boot, .{ &vm, options, spec });
        errdefer {
            if (future.cancel(init.io)) |value| {
                var response = value;
                response.deinit();
            } else |_| {}
        }
        const marker = try std.fmt.allocPrint(allocator, "{s}/config-entered", .{parent});
        // Synchronize cancellation with an in-flight configuration request,
        // rather than accidentally canceling preflight or socket readiness.
        var attempts: usize = 0;
        while (true) : (attempts += 1) {
            _ = std.Io.Dir.cwd().statFile(init.io, marker, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    if (attempts == 300) return error.ConfigurationNotReached;
                    try init.io.sleep(.fromMilliseconds(10), .awake);
                    continue;
                },
                else => return err,
            };
            break;
        }
        break :blk future.cancel(init.io);
    } else vm.boot(options, spec);
    var booted = result catch |err| {
        const child_exit = std.mem.eql(u8, mode, "boot-exit") or std.mem.eql(u8, mode, "boot-rollback");
        const expected: []const u8 = if (cancel) "Canceled" else if (child_exit) "ProcessExited or EndOfStream" else if (std.mem.eql(u8, mode, "boot-timeout") or std.mem.eql(u8, mode, "boot-budget") or std.mem.eql(u8, mode, "boot-nic-timeout")) "StartupTimeout" else return err;
        // Socket EOF can become visible before waitid reports process exit.
        // Preserve that original transport failure rather than delaying cleanup.
        const matched = if (child_exit) err == error.ProcessExited or err == error.EndOfStream else std.mem.eql(u8, @errorName(err), expected);
        if (!matched) {
            std.debug.print("Expected {s}, got {s}\n", .{ expected, @errorName(err) });
            return error.UnexpectedBootError;
        }
        if (err == error.ProcessExited) {
            switch (vm.last_exit orelse return error.MissingExitStatus) {
                .exited => |code| if (code != 23) return error.WrongExitCode,
                else => return error.WrongExitKind,
            }
        }
        try finishBootFailure(&vm, std.mem.eql(u8, mode, "boot-rollback"));
        std.debug.print("PASS {s}\n", .{mode});
        return;
    };
    defer booted.deinit();
    switch (booted) {
        .fault => |fault| {
            if (!std.mem.startsWith(u8, mode, "boot-reject-") and !std.mem.eql(u8, mode, "boot-fault-rollback"))
                return error.UnexpectedFault;
            if (fault.status != 422 or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"boot rejected\"}"))
                return error.WrongFault;
            try finishBootFailure(&vm, std.mem.eql(u8, mode, "boot-fault-rollback"));
        },
        .success => {
            if (!std.mem.eql(u8, mode, "boot-success") and !std.mem.eql(u8, mode, "boot-no-network")) return error.UnexpectedSuccess;
            if (vm.workspace == null or vm.process == null or vm.connection == null or vm.cleanup_error != null)
                return error.MissingBootOwnership;
            const client = try vm.client();
            var info = try client.getInstanceInfo();
            defer info.deinit();
            switch (info) {
                .success => |value| if (!std.mem.eql(u8, value.state, "Running")) return error.UnexpectedInstanceState,
                .fault => return error.InstanceInfoRejected,
            }
            if (vm.boot(options, spec)) |value| {
                var unexpected = value;
                unexpected.deinit();
                return error.ReconfiguredRunningInstance;
            } else |err| {
                if (err != error.AlreadyStarted) return err;
            }
            try vm.shutdown(1000);
            try vm.shutdown(1000);
        },
    }
    std.debug.print("PASS {s}\n", .{mode});
}

fn finishBootFailure(vm: *fc.runtime.Vm, retained_workspace: bool) !void {
    if (vm.process != null or vm.connection != null) return error.LiveBootResources;
    if (retained_workspace) {
        if (vm.cleanup_error == null or vm.workspace == null)
            return error.LostRollbackOwnership;
        var dir = try std.Io.Dir.cwd().openDir(vm.io, vm.workspace.?.path, .{});
        defer dir.close(vm.io);
        _ = try dir.statFile(vm.io, "borrowed", .{});
        try dir.deleteFile(vm.io, "borrowed");
    } else if (vm.cleanup_error != null or vm.workspace != null) return error.RollbackFailed;
    try vm.shutdown(1000);
    if (vm.workspace != null or vm.cleanup_error != null) return error.RollbackFailed;
    try vm.shutdown(1000);
}

fn assertNoChildren() void {
    const linux = std.os.linux;
    var info: linux.siginfo_t = undefined;
    // This standalone runner owns every successfully spawned child, including
    // version probes. Timeout/cancellation must not abandon a live child or zombie.
    const err = linux.errno(linux.waitid(.ALL, 0, &info, linux.W.EXITED | linux.W.NOHANG, null));
    if (err != .CHILD) std.debug.panic("Leaked child after runtime scenario: {t}", .{err});
}
