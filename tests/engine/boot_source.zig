const std = @import("std");
const fc = @import("firecrackerz").engine;

/// Configures a disposable pre-boot instance; never sends InstanceStart.
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 6 or !std.mem.eql(u8, args[5], "--disposable")) {
        std.debug.print("Usage: {s} SOCKET EXECUTABLE KERNEL INITRD --disposable\n", .{args[0]});
        return error.InvalidArguments;
    }
    var connected = try fc.Client.connect(init.gpa, init.io, .{
        .socket_path = args[1],
        .binary = .{ .executable = args[2] },
    });
    defer connected.deinit();
    switch (connected) {
        .fault => return error.ConnectionRejected,
        .success => |*client| {
            try expectStatus(client, .{ .kernel_image_path = args[3] }, 204);
            try expectStatus(client, .{
                .kernel_image_path = args[3],
                .boot_args = "console=ttyS0 reboot=k panic=1",
                .initrd_path = args[4],
            }, 204);
            // Appending a child to a regular image path guarantees it is invalid
            // without relying on a fixed nonexistent host filename.
            const missing_kernel = try std.fmt.allocPrint(init.gpa, "{s}/missing", .{args[3]});
            defer init.gpa.free(missing_kernel);
            try expectStatus(client, .{ .kernel_image_path = missing_kernel }, 400);
            const missing_initrd = try std.fmt.allocPrint(init.gpa, "{s}/missing", .{args[4]});
            defer init.gpa.free(missing_initrd);
            try expectStatus(client, .{ .kernel_image_path = args[3], .initrd_path = missing_initrd }, 400);
            // Explicit empty arguments must not be dropped or treated as absent.
            try expectStatus(client, .{ .kernel_image_path = args[3], .boot_args = "" }, 204);
            std.debug.print("PASS boot source creation, replacement, invalid paths, and empty arguments; guest not started\n", .{});
        },
    }
}

fn expectStatus(client: *fc.Client, request: fc.models.BootSourceRequest, status: u16) !void {
    var result = try client.putGuestBootSource(request);
    defer result.deinit();
    switch (result) {
        .success => if (status != 204) return error.InvalidBootSourceAccepted,
        .fault => |fault| {
            std.debug.print("Boot source HTTP {d}: {s}\n", .{ fault.status, fault.body });
            if (fault.status != status) return error.UnexpectedBootSourceFault;
        },
    }
}
