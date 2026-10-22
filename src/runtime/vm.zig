const std = @import("std");
const builtin = @import("builtin");
const engine = @import("../engine/root.zig");
const Workspace = @import("artifacts/workspace.zig").Workspace;
const Supervisor = @import("../internal/supervisor.zig");
const firecracker = @import("process/firecracker.zig");
const api = @import("readiness/api.zig");
const BootSpec = @import("spec.zig").BootSpec;
const boot_execution = @import("execution/start.zig");

pub const StartOptions = struct {
    executable: []const u8,
    workspace_parent: []const u8,
    startup_timeout_ms: u32 = 3000,
    request_timeout_ms: u32 = 3000,
};

/// Linux-only owned Firecracker instance. API readiness and accepted guest start
/// are distinct from guest readiness. Do not copy after start/boot.
/// Allocator and Io must outlive this handle. All access is sequential;
/// no external child waiters or SIGCHLD auto-reaping may consume its child.
pub const Vm = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    workspace: ?Workspace = null,
    process: ?Supervisor = null,
    connection: ?engine.Client = null,
    /// Preserved after early exit or shutdown. No automatic restart.
    last_exit: ?std.process.Child.Term = null,
    /// Startup preserves its original error/fault. If rollback cannot remove
    /// owned files, this records why; shutdown can retry without losing ownership.
    cleanup_error: ?anyerror = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Vm {
        return .{ .allocator = allocator, .io = io };
    }

    /// Borrows options only during this call. A success means the version
    /// handshake completed, not guest readiness. HTTP rejection remains an owned
    /// engine fault. Errors and faults kill/reap the child and attempt cleanup;
    /// call shutdown even after failure if cleanup_error is set.
    pub fn start(self: *Vm, options: StartOptions) !engine.Result(void) {
        return self.startUntil(options, startupDeadline(self.io, options));
    }

    /// Launches a fresh instance, configures it, and requests guest start.
    /// Options/spec are borrowed for this call. Success is not guest readiness.
    /// The startup deadline covers launch and all configuration requests. No
    /// writes are retried, including an ambiguously completed InstanceStart.
    /// Failure discards the owned instance, never borrowed artifacts; failed
    /// cleanup retains ownership and diagnostics for shutdown to retry.
    pub fn boot(self: *Vm, options: StartOptions, spec: BootSpec) !engine.Result(void) {
        const deadline = startupDeadline(self.io, options);
        // startUntil owns its own rollback. In particular AlreadyStarted must
        // not destroy a previously launched instance.
        const launched = try self.startUntil(options, deadline);
        if (launched == .fault) return launched;
        errdefer self.rollback();
        const result = try boot_execution.run(self.io, &self.connection.?, &self.process.?, spec, deadline);
        if (result == .fault) self.rollback();
        return result;
    }

    fn startUntil(self: *Vm, options: StartOptions, deadline: std.Io.Timeout) !engine.Result(void) {
        if (builtin.os.tag != .linux) return error.UnsupportedPlatform;
        if (self.workspace != null or self.process != null or self.connection != null)
            return error.AlreadyStarted;
        if (options.startup_timeout_ms == 0 or options.request_timeout_ms == 0)
            return error.InvalidTimeout;
        if (options.executable.len == 0 or std.mem.findScalar(u8, options.executable, 0) != null)
            return error.InvalidExecutablePath;
        self.last_exit = null;
        self.cleanup_error = null;
        errdefer self.rollback();
        try self.io.checkCancel();
        // Validation launches only --version, before acquiring VM resources.
        // The engine owns the supported-version policy; do not duplicate it.
        const executable = engine.Client.validateExecutable(self.allocator, self.io, .{
            .executable = options.executable,
        }, options.startup_timeout_ms) catch |err| switch (err) {
            error.Timeout => return error.StartupTimeout,
            else => return err,
        };
        defer self.allocator.free(executable);
        if (deadline.toDurationFromNow(self.io).?.raw.nanoseconds <= 0)
            return error.StartupTimeout;
        self.workspace = try Workspace.create(self.allocator, self.io, options.workspace_parent);
        self.process = try firecracker.spawn(self.io, executable, self.workspace.?.socket_path);
        const result = try api.wait(self.allocator, self.io, &self.process.?, .{
            .socket_path = self.workspace.?.socket_path,
            .binary = .{ .executable = executable },
            .discovery_timeout_ms = options.startup_timeout_ms,
            .request_timeout_ms = options.request_timeout_ms,
        }, deadline);
        switch (result) {
            .success => |connection| {
                self.connection = connection;
                return .{ .success = {} };
            },
            .fault => |fault| {
                self.rollback();
                return .{ .fault = fault };
            },
        }
    }

    /// Borrowed sequential engine access. The returned pointer is invalid after
    /// shutdown or moving this handle. Direct lifecycle calls do not establish
    /// guest readiness; runtime does not cache guest lifecycle state.
    pub fn client(self: *Vm) !*engine.Client {
        const process = if (self.process) |*value| value else return error.NotStarted;
        if (try process.poll(self.io)) |term| {
            self.last_exit = term;
            return error.ProcessExited;
        }
        return if (self.connection) |*value| value else error.NotStarted;
    }

    /// TERM then KILL within the process deadline. Not a guest graceful-shutdown
    /// protocol. Timeout/cancellation preserves ownership for a later retry.
    /// Files are removed only after reaping. Successful calls are idempotent.
    pub fn shutdown(self: *Vm, timeout_ms: u32) !void {
        if (timeout_ms == 0) return error.InvalidTimeout;
        if (self.connection) |*connection| {
            connection.deinit();
            self.connection = null;
        }
        if (self.process) |*process| {
            self.last_exit = try process.shutdown(self.io, timeout_ms);
            self.process = null;
        }
        if (self.workspace) |*workspace| {
            workspace.cleanup(self.io) catch |err| {
                self.cleanup_error = err;
                return err;
            };
            workspace.deinit();
            self.workspace = null;
        }
        self.cleanup_error = null;
    }

    /// Memory release is separate from shutdown. Must have successfully shut
    /// down, or completed startup rollback, before calling this method.
    pub fn deinit(self: *Vm) void {
        std.debug.assert(self.connection == null and self.process == null and self.workspace == null);
        self.* = undefined;
    }

    fn rollback(self: *Vm) void {
        // Failure must not strand a child when the initiating task is canceled.
        // Force-kill/reap is uncancelable and may outlast the startup deadline.
        const protection = self.io.swapCancelProtection(.blocked);
        defer _ = self.io.swapCancelProtection(protection);
        if (self.connection) |*connection| {
            connection.deinit();
            self.connection = null;
        }
        if (self.process) |*process| {
            process.forceKill(self.io);
            self.last_exit = process.term;
            self.process = null;
        }
        if (self.workspace) |*workspace| {
            workspace.cleanup(self.io) catch |err| {
                self.cleanup_error = err;
                return;
            };
            workspace.deinit();
            self.workspace = null;
        }
    }
};

fn startupDeadline(io: std.Io, options: StartOptions) std.Io.Timeout {
    return (std.Io.Timeout{ .duration = .{
        .raw = .fromMilliseconds(options.startup_timeout_ms),
        .clock = .awake,
    } }).toDeadline(io);
}
