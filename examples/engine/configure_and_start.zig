const std = @import("std");
const fc = @import("firecrackerz").engine;

/// Starts an existing, application-owned disposable Firecracker process.
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if ((args.len != 6 and args.len != 7) or !std.mem.eql(u8, args[args.len - 1], "--disposable")) {
        std.debug.print("Usage: {s} SOCKET EXECUTABLE KERNEL ROOTFS [TAP] --disposable (configures and starts the guest)\n", .{args[0]});
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
            var machine = try client.putMachineConfiguration(.{
                .vcpu_count = 1,
                .mem_size_mib = 128,
            });
            defer machine.deinit();
            try requireSuccess(&machine, "Machine configuration");

            var boot = try client.putGuestBootSource(.{
                .kernel_image_path = args[3],
                .boot_args = "console=ttyS0 reboot=k panic=0",
            });
            defer boot.deinit();
            try requireSuccess(&boot, "Boot source");

            var drive = try client.putGuestDrive(.{
                .drive_id = "rootfs",
                .is_root_device = true,
                .path_on_host = args[4],
                .is_read_only = true,
            });
            defer drive.deinit();
            try requireSuccess(&drive, "Root drive");

            if (args.len == 7) {
                var network = try client.putGuestNetworkInterface(.{
                    .iface_id = "eth0",
                    .host_dev_name = args[5],
                });
                defer network.deinit();
                try requireSuccess(&network, "Network interface");
            }

            var started = try client.startInstance();
            defer started.deinit();
            try requireSuccess(&started, "Instance start");
            std.debug.print("Start accepted; guest readiness is not verified. The Firecracker process remains application-owned.\n", .{});
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
