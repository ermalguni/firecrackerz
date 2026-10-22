const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// Owns a private directory and the API socket created inside it by the child.
/// Borrowed kernel, rootfs, and other artifacts must remain outside this directory.
/// This is a trusted-local-host facility, not a defense against concurrent
/// filesystem mutation by another process running as the same user.
pub const Workspace = struct {
    allocator: Allocator,
    path: []const u8,
    socket_path: []const u8,
    parent_dir: Io.Dir,
    dir: Io.Dir,
    cleaned: bool = false,

    const socket_name = "api.sock";
    const name_template = "fc-00000000000000000000000000000000";
    const collision_attempts = 16;

    /// Creates a fresh 0700 directory beneath an existing parent. The parent may
    /// be relative; both returned paths are absolute and owned by this value.
    /// Existing names are never reused, even when they name an empty directory.
    pub fn create(allocator: Allocator, io: Io, parent: []const u8) !Workspace {
        if (parent.len == 0 or std.mem.findScalar(u8, parent, 0) != null)
            return error.InvalidWorkspaceParent;

        const parent_dir = try Io.Dir.cwd().openDir(io, parent, .{});
        errdefer parent_dir.close(io);

        var parent_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
        const parent_len = try parent_dir.realPath(io, &parent_buffer);
        const canonical_parent = std.mem.trimEnd(u8, parent_buffer[0..parent_len], "/");
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ canonical_parent, name_template });
        errdefer allocator.free(path);
        const socket_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, socket_name });
        errdefer allocator.free(socket_path);
        // Filesystem Unix socket addresses need space for the terminating NUL.
        if (socket_path.len >= Io.net.UnixAddress.max_len) return error.NameTooLong;

        const name = std.fs.path.basename(path);
        for (0..collision_attempts) |_| {
            var random_bytes: [16]u8 = undefined;
            try io.randomSecure(&random_bytes);
            const hex = std.fmt.bytesToHex(random_bytes, .lower);
            @memcpy(path[path.len - hex.len ..], &hex);
            @memcpy(socket_path[0..path.len], path);
            parent_dir.createDir(io, name, .fromMode(0o700)) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => return err,
            };

            // After mkdir, rollback must not itself be interrupted by cancellation.
            const protection = io.swapCancelProtection(.blocked);
            defer _ = io.swapCancelProtection(protection);
            const dir = parent_dir.openDir(io, name, .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch |err| {
                try parent_dir.deleteDir(io, name);
                return err;
            };
            errdefer dir.close(io);
            // Restore owner permissions if the process umask removed any bits.
            dir.setPermissions(io, .fromMode(0o700)) catch |err| {
                try parent_dir.deleteDir(io, name);
                return err;
            };
            return .{
                .allocator = allocator,
                .path = path,
                .socket_path = socket_path,
                .parent_dir = parent_dir,
                .dir = dir,
            };
        }
        return error.WorkspaceCollision;
    }

    /// Removes only api.sock (if it is a socket) and the empty owned directory.
    /// Stop and reap the child before calling. Unexpected entries are preserved.
    /// Failure retains all handles and paths so callers can resolve the problem
    /// and retry. Successful cleanup is idempotent and closes the handles.
    pub fn cleanup(self: *Workspace, io: Io) !void {
        if (self.cleaned) return;
        const owned_stat = try self.dir.stat(io);
        if (owned_stat.nlink != 0) {
            const name = std.fs.path.basename(self.path);
            const named_stat = self.parent_dir.statFile(io, name, .{ .follow_symlinks = false }) catch |err| switch (err) {
                error.FileNotFound => return error.WorkspaceMoved,
                else => return err,
            };
            if (named_stat.kind != .directory or named_stat.inode != owned_stat.inode)
                return error.WorkspaceReplaced;

            const socket_stat = self.dir.statFile(io, socket_name, .{ .follow_symlinks = false }) catch |err| switch (err) {
                error.FileNotFound => null,
                else => return err,
            };
            if (socket_stat) |stat| {
                if (stat.kind != .unix_domain_socket) return error.UnexpectedWorkspaceEntry;
                self.dir.deleteFile(io, socket_name) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => return err,
                };
            }
            try self.parent_dir.deleteDir(io, name);
        }
        self.dir.close(io);
        self.parent_dir.close(io);
        self.cleaned = true;
    }

    /// Releases memory only. Explicit, successful cleanup is required first.
    pub fn deinit(self: *Workspace) void {
        std.debug.assert(self.cleaned);
        self.allocator.free(self.socket_path);
        self.allocator.free(self.path);
        self.* = undefined;
    }
};

test "workspace owns a private absolute directory and cleans its socket idempotently" {
    const io = std.testing.io;
    var workspace = try Workspace.create(std.testing.allocator, io, "/tmp");
    defer workspace.deinit();
    defer workspace.cleanup(io) catch unreachable;

    try std.testing.expect(std.fs.path.isAbsolute(workspace.path));
    try std.testing.expect(std.fs.path.isAbsolute(workspace.socket_path));
    const stat = try workspace.dir.stat(io);
    try std.testing.expectEqual(@as(std.posix.mode_t, 0o700), stat.permissions.toMode() & 0o777);
    const address = try Io.net.UnixAddress.init(workspace.socket_path);
    var server = try address.listen(io, .{});
    server.deinit(io);
    try workspace.cleanup(io);
    try workspace.cleanup(io);
    try std.testing.expectError(error.FileNotFound, Io.Dir.cwd().statFile(io, workspace.path, .{}));
}

fn fixedRandom(_: ?*anyopaque, buffer: []u8) Io.RandomSecureError!void {
    @memset(buffer, 0);
}

test "workspace collisions never reuse or delete existing directories" {
    const io = std.testing.io;
    var parent = try Workspace.create(std.testing.allocator, io, "/tmp");
    defer parent.deinit();
    defer parent.cleanup(io) catch unreachable;

    var vtable = io.vtable.*;
    vtable.randomSecure = fixedRandom;
    const fixed_io: Io = .{ .userdata = io.userdata, .vtable = &vtable };
    var first = try Workspace.create(std.testing.allocator, fixed_io, parent.path);
    defer first.deinit();
    defer first.cleanup(io) catch unreachable;
    try first.dir.writeFile(io, .{ .sub_path = "borrowed", .data = "keep" });
    defer first.dir.deleteFile(io, "borrowed") catch unreachable;
    try std.testing.expectError(error.WorkspaceCollision, Workspace.create(std.testing.allocator, fixed_io, parent.path));
    const marker = try first.dir.statFile(io, "borrowed", .{});
    try std.testing.expectEqual(@as(u64, 4), marker.size);
}

test "workspace cleanup preserves unexpected entries and supports retry" {
    const io = std.testing.io;
    var workspace = try Workspace.create(std.testing.allocator, io, "/tmp");
    defer workspace.deinit();
    defer workspace.cleanup(io) catch unreachable;

    try workspace.dir.writeFile(io, .{ .sub_path = "api.sock", .data = "not a socket" });
    try std.testing.expectError(error.UnexpectedWorkspaceEntry, workspace.cleanup(io));
    try std.testing.expect(!workspace.cleaned);
    try std.testing.expectEqual(@as(u64, 12), (try workspace.dir.statFile(io, "api.sock", .{})).size);
    try workspace.dir.deleteFile(io, "api.sock");

    try workspace.dir.writeFile(io, .{ .sub_path = "borrowed-rootfs", .data = "keep" });
    try std.testing.expectError(error.DirNotEmpty, workspace.cleanup(io));
    try std.testing.expect(!workspace.cleaned);
    try std.testing.expectEqual(@as(u64, 4), (try workspace.dir.statFile(io, "borrowed-rootfs", .{})).size);
    try workspace.dir.deleteFile(io, "borrowed-rootfs");
    try workspace.cleanup(io);
}

test "workspace cleanup refuses a replacement directory" {
    const io = std.testing.io;
    var parent = try Workspace.create(std.testing.allocator, io, "/tmp");
    defer parent.deinit();
    defer parent.cleanup(io) catch unreachable;
    var workspace = try Workspace.create(std.testing.allocator, io, parent.path);
    defer workspace.deinit();
    defer workspace.cleanup(io) catch unreachable;

    const name = std.fs.path.basename(workspace.path);
    try parent.dir.rename(name, parent.dir, "saved", io);
    try parent.dir.createDir(io, name, .fromMode(0o700));
    try std.testing.expectError(error.WorkspaceReplaced, workspace.cleanup(io));
    try std.testing.expectEqual(Io.File.Kind.directory, (try parent.dir.statFile(io, name, .{})).kind);
    try parent.dir.deleteDir(io, name);
    try parent.dir.rename("saved", parent.dir, name, io);
    try workspace.cleanup(io);
}

test "workspace rejects overlong socket paths without creating a child" {
    const io = std.testing.io;
    var parent = try Workspace.create(std.testing.allocator, io, "/tmp");
    defer parent.deinit();
    defer parent.cleanup(io) catch unreachable;
    const long_name: []const u8 = &@as([80]u8, @splat('p'));
    try parent.dir.createDir(io, long_name, .fromMode(0o700));
    defer parent.dir.deleteDir(io, long_name) catch unreachable;
    const long_parent = try std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{ parent.path, long_name });
    defer std.testing.allocator.free(long_parent);
    try std.testing.expectError(error.NameTooLong, Workspace.create(std.testing.allocator, io, long_parent));
    // The nonrecursive deferred deletion also proves no random child was left.
}
