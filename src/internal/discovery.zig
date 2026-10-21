const std = @import("std");
const builtin = @import("builtin");
const version = @import("version.zig");

pub const Binary = union(enum) {
    executable: []const u8,
    /// A caller-supplied colon-separated PATH; the executable name is firecracker.
    /// Empty entries designate the current directory, as in POSIX PATH lookup.
    search_path: []const u8,
};

pub const Discovered = struct {
    executable_path: []const u8,
    version: version.Version,

    pub fn deinit(self: *Discovered, allocator: std.mem.Allocator) void {
        allocator.free(self.executable_path);
        self.* = undefined;
    }
};

const output_limit = 4096;

/// Resolves a local executable and probes it without invoking a shell. The
/// returned absolute path is owned. Discovery never launches a running VMM.
pub fn discover(allocator: std.mem.Allocator, io: std.Io, binary: Binary, timeout_ms: u32) !Discovered {
    if (timeout_ms == 0) return error.Timeout;
    const deadline = (std.Io.Timeout{ .duration = .{
        .raw = .fromMilliseconds(timeout_ms),
        .clock = .awake,
    } }).toDeadline(io);
    const path = try resolve(allocator, io, binary);
    errdefer allocator.free(path);

    // Timing pipe reads is insufficient: a child can close its pipes before
    // exiting. Race the entire probe, including child.wait, against the deadline.
    const Completion = union(enum) {
        probe: @typeInfo(@TypeOf(probe)).@"fn".return_type.?,
        timeout: std.Io.Cancelable!void,
    };
    var completions: [2]Completion = undefined;
    var select = std.Io.Select(Completion).init(io, &completions);
    defer select.cancelDiscard();
    try select.concurrent(.probe, probe, .{ allocator, io, path, deadline });
    try select.concurrent(.timeout, std.Io.Timeout.sleep, .{ deadline, io });
    const detected = switch (try select.await()) {
        .probe => |result| try result,
        .timeout => |result| {
            try result;
            return error.Timeout;
        },
    };
    return .{ .executable_path = path, .version = detected };
}

fn resolve(allocator: std.mem.Allocator, io: std.Io, binary: Binary) ![]const u8 {
    switch (binary) {
        .executable => |path| return resolveCandidate(allocator, io, path),
        .search_path => |path| {
            if (std.mem.findScalar(u8, path, 0) != null) return error.InvalidExecutablePath;
            var entries = std.mem.splitScalar(u8, path, ':');
            var denied = false;
            while (entries.next()) |entry| {
                const candidate = try std.fs.path.join(allocator, &.{ if (entry.len == 0) "." else entry, "firecracker" });
                defer allocator.free(candidate);
                return resolveCandidate(allocator, io, candidate) catch |err| switch (err) {
                    error.ExecutableNotFound => continue,
                    error.NotExecutable => {
                        denied = true;
                        continue;
                    },
                    else => return err,
                };
            }
            return if (denied) error.NotExecutable else error.ExecutableNotFound;
        },
    }
}

fn resolveCandidate(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    if (path.len == 0 or std.mem.findScalar(u8, path, 0) != null) return error.InvalidExecutablePath;
    const cwd = std.Io.Dir.cwd();
    const stat = cwd.statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return error.ExecutableNotFound,
        error.AccessDenied => return error.NotExecutable,
        else => return err,
    };
    if (stat.kind != .file) return error.NotExecutable;
    cwd.access(io, path, .{ .execute = true }) catch |err| switch (err) {
        error.FileNotFound => return error.ExecutableNotFound,
        error.AccessDenied, error.PermissionDenied => return error.NotExecutable,
        else => return err,
    };
    // Keep the allocation non-sentinel so Discovered can release its []const u8
    // with the exact allocation size on all allocators.
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try cwd.realPathFile(io, path, &buffer);
    return allocator.dupe(u8, buffer[0..len]);
}

fn probe(allocator: std.mem.Allocator, io: std.Io, path: []const u8, deadline: std.Io.Timeout) !version.Version {
    var child = try std.process.spawn(io, .{
        .exe = .{ .path = .cwd() },
        .argv = &.{ path, "--version" },
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    // kill also reaps the child and closes all pipes; after wait it is a no-op.
    defer child.kill(io);
    var streams: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(allocator, io, streams.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    const stdout = reader.reader(0);
    const stderr = reader.reader(1);
    while (reader.fill(1, deadline)) |_| {
        if (stdout.bufferedLen() + stderr.bufferedLen() > output_limit)
            return error.OutputTooLong;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
    try reader.checkAnyError();
    switch (try child.wait(io)) {
        .exited => |code| if (code != 0) return error.ProcessFailed,
        else => return error.ProcessFailed,
    }
    const detected = try parseOutput(stdout.buffered());
    try version.supported(detected);
    return detected;
}

fn parseOutput(stdout: []const u8) !version.Version {
    // Firecracker can emit a shutdown diagnostic after the version banner.
    // Only the first line is the version; all collected diagnostics are bounded.
    const line_end = std.mem.findScalar(u8, stdout, '\n') orelse stdout.len;
    const line = std.mem.trim(u8, stdout[0..line_end], " \t\r");
    const prefix = "Firecracker v";
    if (!std.mem.startsWith(u8, line, prefix)) return error.InvalidVersionOutput;
    return version.parse(line[prefix.len..]) catch |err| switch (err) {
        error.InvalidVersion => return error.InvalidVersionOutput,
        else => return err,
    };
}

test "version output requires a Firecracker banner" {
    const valid = try parseOutput("Firecracker v1.17.0+local\r\nshutdown diagnostic\n");
    try std.testing.expect(version.eql(valid, .{ .major = 1, .minor = 17, .patch = 0 }));
    for ([_][]const u8{ "", "1.17.0", "v1.17.0", "Other v1.17.0", "Firecracker v", "Firecracker v1.17.0 junk" }) |text| {
        try std.testing.expectError(error.InvalidVersionOutput, parseOutput(text));
    }
    try std.testing.expectError(error.PrereleaseVersion, parseOutput("Firecracker v1.17.0-dev\n"));
}

fn writeTestExecutable(dir: std.Io.Dir, name: []const u8, body: []const u8) !void {
    const io = std.testing.io;
    const file = try dir.createFile(io, name, .{ .permissions = .executable_file });
    defer file.close(io);
    try file.writeStreamingAll(io, "#!/bin/sh\n");
    try file.writeStreamingAll(io, body);
    try file.setPermissions(io, .fromMode(0o700));
}

fn testExecutablePath(dir: std.Io.Dir, name: []const u8) ![]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try dir.realPathFile(std.testing.io, name, &buffer);
    return std.testing.allocator.dupe(u8, buffer[0..len]);
}

test "explicit executable preserves spaces and passes exactly --version" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestExecutable(tmp.dir, "fire cracker;literal", "[ \"$#\" = 1 ] && [ \"$1\" = --version ] || exit 2\nprintf 'Firecracker v1.17.0+test\\n'\nprintf 'diagnostic\\n' >&2\n");
    const path = try testExecutablePath(tmp.dir, "fire cracker;literal");
    defer std.testing.allocator.free(path);
    var found = try discover(std.testing.allocator, std.testing.io, .{ .executable = path }, 2000);
    defer found.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(path, found.executable_path);
    try version.supported(found.version);
}

test "PATH search skips absent and non-executable candidates" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "denied", .default_dir);
    try tmp.dir.createDir(std.testing.io, "valid", .default_dir);
    try writeTestExecutable(tmp.dir, "denied/firecracker", "exit 3\n");
    const denied_file = try tmp.dir.openFile(std.testing.io, "denied/firecracker", .{});
    defer denied_file.close(std.testing.io);
    try denied_file.setPermissions(std.testing.io, .fromMode(0o600));
    try writeTestExecutable(tmp.dir, "valid/firecracker", "printf 'Firecracker v1.17.0\\n'\n");
    const root = try testExecutablePath(tmp.dir, ".");
    defer std.testing.allocator.free(root);
    const path = try std.fmt.allocPrint(std.testing.allocator, "{s}/missing:{s}/denied:{s}/valid", .{ root, root, root });
    defer std.testing.allocator.free(path);
    var found = try discover(std.testing.allocator, std.testing.io, .{ .search_path = path }, 2000);
    defer found.deinit(std.testing.allocator);
    const expected = try testExecutablePath(tmp.dir, "valid/firecracker");
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, found.executable_path);
}

test "discovery reports process version output and deadline failures" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const cases = .{
        .{ "exit 7\n", error.ProcessFailed },
        .{ "printf 'garbage\\n'\n", error.InvalidVersionOutput },
        .{ "printf 'Firecracker v1.17.1\\n'\n", error.UnsupportedVersion },
        .{ "printf 'Firecracker v1.17.0-dev\\n'\n", error.PrereleaseVersion },
        .{ "printf '%4097s' ''\n", error.OutputTooLong },
        .{ "printf '%4097s' '' >&2\n", error.OutputTooLong },
        .{ "printf '%3000s' ''; printf '%3000s' '' >&2\n", error.OutputTooLong },
        .{ "exec /bin/sleep 10\n", error.Timeout },
        .{ "exec 1>&- 2>&-; exec /bin/sleep 10\n", error.Timeout },
    };
    inline for (cases) |case| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        try writeTestExecutable(tmp.dir, "firecracker", case[0]);
        const path = try testExecutablePath(tmp.dir, "firecracker");
        defer std.testing.allocator.free(path);
        try std.testing.expectError(case[1], discover(std.testing.allocator, std.testing.io, .{ .executable = path }, 250));
    }
}

test "invalid paths missing executables and zero deadline fail without a child" {
    try std.testing.expectError(error.InvalidExecutablePath, discover(std.testing.allocator, std.testing.io, .{ .executable = "" }, 1000));
    try std.testing.expectError(error.InvalidExecutablePath, discover(std.testing.allocator, std.testing.io, .{ .search_path = "bad\x00path" }, 1000));
    try std.testing.expectError(error.Timeout, discover(std.testing.allocator, std.testing.io, .{ .executable = "irrelevant" }, 0));
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try testExecutablePath(tmp.dir, ".");
    defer std.testing.allocator.free(root);
    try std.testing.expectError(error.ExecutableNotFound, discover(std.testing.allocator, std.testing.io, .{ .search_path = root }, 1000));
    try std.testing.expectError(error.NotExecutable, discover(std.testing.allocator, std.testing.io, .{ .executable = root }, 1000));
}
