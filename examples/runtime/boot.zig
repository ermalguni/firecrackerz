const std = @import("std");
const runtime = @import("firecrackerz").runtime;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if ((args.len != 6 and args.len != 8) or !std.mem.eql(u8, args[5], "--disposable")) {
        std.debug.print("Usage: {s} EXECUTABLE WORKSPACE_PARENT KERNEL ROOTFS --disposable [TAP GUEST_MAC] (boots and stops the guest; TAP remains caller-owned)\n", .{args[0]});
        return error.InvalidArguments;
    }
    var vm = runtime.Vm.init(init.gpa, init.io);
    defer vm.deinit();
    defer vm.shutdown(2000) catch |err| {
        // A service must retain the handle and retry/report shutdown failures.
        std.debug.panic("Runtime shutdown failed: {s}", .{@errorName(err)});
    };
    var booted = vm.boot(.{
        .executable = args[1],
        .workspace_parent = args[2],
    }, .{
        .machine = .{ .vcpu_count = 1, .mem_size_mib = 128 },
        .boot_source = .{
            .kernel_image_path = args[3],
            .boot_args = "console=ttyS0 reboot=k panic=0 root=/dev/vda ro",
        },
        .drives = &.{.{
            .drive_id = "rootfs",
            .is_root_device = true,
            .path_on_host = args[4],
            .is_read_only = true,
        }},
        .network_interfaces = if (args.len == 8) &.{.{
            .iface_id = "eth0",
            .host_dev_name = args[6],
            .guest_mac = args[7],
        }} else &.{},
    }) catch |err| {
        if (vm.last_exit) |term| std.debug.print("Child {f}\n", .{term});
        if (vm.cleanup_error) |cleanup_err| std.debug.print("Cleanup failed: {s}\n", .{@errorName(cleanup_err)});
        return err;
    };
    defer booted.deinit();
    switch (booted) {
        .fault => |fault| {
            std.debug.print("Boot HTTP {d}: {s}\n", .{ fault.status, fault.body });
            if (vm.cleanup_error) |err| std.debug.print("Cleanup failed: {s}\n", .{@errorName(err)});
            return error.BootRejected;
        },
        .success => {},
    }
    const client = try vm.client();
    var info = try client.getInstanceInfo();
    defer info.deinit();
    switch (info) {
        .success => |value| std.debug.print("Start accepted: id={s}, state={s}, version={s}\nWorkspace: {s}\nGuest readiness is not verified.\n", .{
            value.id, value.state, value.vmm_version, vm.workspace.?.path,
        }),
        .fault => |fault| {
            std.debug.print("Instance HTTP {d}: {s}\n", .{ fault.status, fault.body });
            return error.InstanceInfoRejected;
        },
    }
    try vm.shutdown(2000);
    std.debug.print("Child reaped; owned workspace removed. Borrowed kernel and rootfs retained.\n", .{});
}
