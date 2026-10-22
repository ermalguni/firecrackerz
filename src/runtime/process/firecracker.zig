const std = @import("std");
const builtin = @import("builtin");
const Supervisor = @import("../../internal/supervisor.zig");

/// Launches a trusted local executable directly as
/// `executable --api-sock socket_path`. No shell or PATH lookup is used.
/// The child inherits the environment, working directory, stdout, and stderr;
/// stdin is /dev/null. The returned supervisor exclusively owns the child.
/// Preflight cannot eliminate exec-time races. On affected Zig versions, a
/// failed exec inside std.process.spawn can lose the PID before returning.
pub fn spawn(io: std.Io, executable: []const u8, socket_path: []const u8) !Supervisor {
    if (builtin.os.tag != .linux) return error.UnsupportedOperatingSystem;
    if (executable.len == 0 or std.mem.findScalar(u8, executable, 0) != null)
        return error.InvalidExecutable;
    if (socket_path.len == 0 or std.mem.findScalar(u8, socket_path, 0) != null)
        return error.InvalidSocketPath;
    const cwd: std.Io.Dir = .cwd();
    const stat = cwd.statFile(io, executable, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return error.ExecutableNotFound,
        else => return err,
    };
    if (stat.kind != .file) return error.InvalidExecutable;
    try cwd.access(io, executable, .{ .execute = true });
    return .{ .child = try std.process.spawn(io, .{
        .exe = .{ .path = .cwd() },
        .argv = &.{ executable, "--api-sock", socket_path },
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    }) };
}
