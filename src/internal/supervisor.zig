//! Linux child ownership and sequential supervision. Do not copy a live
//! supervisor, wait on its child elsewhere, or enable SIGCHLD auto-reaping.
//! Unreaped children retain their PID, so signaling never races PID reuse under
//! this ownership contract. These operations require a native Linux Io backend.
const std = @import("std");
const linux = std.os.linux;
const Supervisor = @This();

pub const Term = std.process.Child.Term;

child: std.process.Child,
term: ?Term = null,

/// Nonblocking, cancelable observation. Reaps an exited child exactly once and
/// caches its actual termination status. Errors leave ownership unchanged.
/// A null result means no terminal status was observed, not that the child will
/// remain alive. Do not directly wait on or signal `child` after this call.
pub fn poll(self: *Supervisor, io: std.Io) !?Term {
    if (self.term) |term| return term;
    try io.checkCancel();
    return self.reap(io, linux.W.NOHANG);
}

/// Sends TERM, allows half of `timeout_ms` for graceful exit, then sends KILL.
/// The remaining half is reserved for reaping; both phases share one monotonic
/// deadline. A zero timeout returns InvalidTimeout without touching the child.
/// Returns the exact exit status, including an exit observed before signaling.
/// Timeout, cancellation, and OS errors retain ownership of an unreaped child:
/// the caller must retry shutdown or use forceKill before releasing its owner.
/// Scheduling delays can overrun the deadline; no blocking wait is performed.
pub fn shutdown(self: *Supervisor, io: std.Io, timeout_ms: u32) !Term {
    if (timeout_ms == 0) return error.InvalidTimeout;
    if (self.term) |term| return term;
    const started = std.Io.Clock.awake.now(io);
    const budget = std.Io.Duration.fromMilliseconds(timeout_ms);
    const deadline = started.addDuration(budget);
    const grace = started.addDuration(.fromNanoseconds(@divTrunc(budget.nanoseconds, 2)));

    if (try self.poll(io)) |term| return term;
    try self.signal(io, .TERM);
    var killed = false;
    while (true) {
        if (try self.poll(io)) |term| return term;
        const now = std.Io.Clock.awake.now(io);
        if (!killed and now.compare(.gte, grace)) {
            try self.signal(io, .KILL);
            killed = true;
        }
        if (now.compare(.gte, deadline)) return error.Timeout;
        const next_phase = if (killed) deadline else grace;
        const wake = std.Io.Timestamp.fromNanoseconds(@min(
            next_phase.nanoseconds,
            now.nanoseconds + std.time.ns_per_ms * 10,
        ));
        try wake.withClock(.awake).wait(io);
    }
}

/// Uncancelable startup-failure unwind. Sends KILL and reaps, recording the
/// actual status when available. Unlike shutdown this may block indefinitely
/// (for example, a child in uninterruptible kernel sleep). Unexpected OS errors
/// use Child.kill's best-effort cleanup; its API cannot provide an exit status.
/// This is not a substitute for explicit, fallible shutdown during normal use.
pub fn forceKill(self: *Supervisor, io: std.Io) void {
    if (self.term != null or self.child.id == null) return;
    const protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(protection);

    if (self.poll(io) catch |err| switch (err) {
        error.ChildNotOwned => {
            // Ownership was violated or SIGCHLD auto-reaping was enabled.
            // Never signal the possibly reused PID.
            self.release(io);
            return;
        },
        else => null,
    }) |_| return;

    // Zig's current Threaded Child.kill sends TERM, so send KILL ourselves
    // before using its cleanup fallback for a child that may ignore TERM.
    self.signal(io, .KILL) catch {
        self.child.kill(io);
        return;
    };
    while (true) {
        if (self.reap(io, 0) catch |err| {
            if (err == error.ChildNotOwned) {
                self.release(io);
            } else {
                self.child.kill(io);
            }
            return;
        }) |_| return;
    }
}

fn signal(self: *Supervisor, io: std.Io, sig: linux.SIG) !void {
    const pid = self.child.id orelse return error.ChildNotOwned;
    while (true) {
        try io.checkCancel();
        switch (linux.errno(linux.kill(pid, sig))) {
            .SUCCESS, .SRCH => return, // An exiting child is still ours to reap.
            .INTR => continue,
            .PERM => return error.PermissionDenied,
            else => return error.Unexpected,
        }
    }
}

fn reap(self: *Supervisor, io: std.Io, flags: u32) !?Term {
    const pid = self.child.id orelse return error.ChildNotOwned;
    var info: linux.siginfo_t = undefined;
    // Linux sets this to zero for WNOHANG when nothing is ready. Initialize it
    // as well so that the no-event case does not depend on kernel version.
    info.fields.common.first.piduid.pid = 0;
    var usage: linux.rusage = undefined;
    const usage_ptr = if (self.child.request_resource_usage_statistics) &usage else null;
    switch (linux.errno(linux.waitid(.PID, pid, &info, linux.W.EXITED | flags, usage_ptr))) {
        .SUCCESS => {},
        .INTR => {
            try io.checkCancel();
            return null;
        },
        .CHILD => return error.ChildNotOwned,
        .ACCES, .PERM => return error.PermissionDenied,
        else => return error.Unexpected,
    }
    if (info.fields.common.first.piduid.pid == 0) return null;
    const code: linux.CLD = @fromBackingInt(info.code);
    const status: u32 = @bitCast(info.fields.common.second.sigchld.status);
    const term: Term = switch (code) {
        .EXITED => .{ .exited = @truncate(status) },
        .KILLED, .DUMPED => .{ .signal = @fromBackingInt(@intCast(status)) },
        // A traced stop is not termination and must not release PID ownership.
        else => return null,
    };
    self.term = term;
    if (usage_ptr) |p| self.child.resource_usage_statistics.rusage = p.*;
    self.release(io);
    return term;
}

fn release(self: *Supervisor, io: std.Io) void {
    // Clear the PID before any subsequent work: a successful waitid reaped it.
    self.child.id = null;
    if (self.child.stdin) |file| {
        file.close(io);
        self.child.stdin = null;
    }
    if (self.child.stdout) |file| {
        file.close(io);
        self.child.stdout = null;
    }
    if (self.child.stderr) |file| {
        file.close(io);
        self.child.stderr = null;
    }
}
