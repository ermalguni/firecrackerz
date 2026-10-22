const std = @import("std");
const fc = @import("firecrackerz").engine;

/// Configures a disposable pre-boot instance; never sends InstanceStart.
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5 or !std.mem.eql(u8, args[4], "--disposable")) {
        std.debug.print("Usage: {s} SOCKET EXECUTABLE IMAGE --disposable\n", .{args[0]});
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
            // A file-backed drive also requires its path and read-only setting.
            const minimal: fc.models.DriveRequest = .{
                .drive_id = "rootfs",
                .is_root_device = true,
                .path_on_host = args[3],
                .is_read_only = true,
            };
            try expectStatus(client, minimal, 204);
            // Reusing the ID replaces the root drive instead of adding a second one.
            var explicit = minimal;
            explicit.cache_type = "Writeback";
            explicit.io_engine = "Sync";
            explicit.discard = false;
            explicit.blk_size = 512;
            explicit.rate_limiter = .{
                .bandwidth = .{ .size = 1048576, .refill_time = 1000 },
                .ops = .{ .size = 1000, .refill_time = 1000, .one_time_burst = 100 },
            };
            explicit.topology = .{
                .physical_block_exp = 0,
                .alignment_offset = 0,
                .min_io_size = 1,
                .opt_io_size = 0,
            };
            try expectStatus(client, explicit, 204);
            // A child of the regular image file cannot be a valid backing path.
            const missing_image = try std.fmt.allocPrint(init.gpa, "{s}/missing", .{args[3]});
            defer init.gpa.free(missing_image);
            var invalid_path = minimal;
            invalid_path.path_on_host = missing_image;
            try expectStatus(client, invalid_path, 400);
            var invalid_config = minimal;
            invalid_config.blk_size = -1;
            try expectStatus(client, invalid_config, 400);
            // Leave the disposable instance with a valid, minimal root drive.
            try expectStatus(client, minimal, 204);
            std.debug.print("PASS drive creation, replacement, invalid path, and invalid configuration; minimal root drive restored; guest not started\n", .{});
        },
    }
}

fn expectStatus(client: *fc.Client, request: fc.models.DriveRequest, status: u16) !void {
    var result = try client.putGuestDrive(request);
    defer result.deinit();
    switch (result) {
        .success => if (status != 204) return error.InvalidDriveAccepted,
        .fault => |fault| {
            std.debug.print("Drive HTTP {d}: {s}\n", .{ fault.status, fault.body });
            if (fault.status != status) return error.UnexpectedDriveFault;
        },
    }
}
