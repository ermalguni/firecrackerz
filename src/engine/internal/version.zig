const std = @import("std");

pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
};

/// Parses a semantic version, not a command banner. Build metadata does not
/// participate in compatibility; prerelease contracts are never supported.
pub fn parse(text: []const u8) !Version {
    const metadata_start = std.mem.findScalar(u8, text, '+');
    const core = text[0 .. metadata_start orelse text.len];
    if (std.mem.findScalar(u8, core, '-') != null) return error.PrereleaseVersion;
    if (metadata_start) |start| {
        var identifiers = std.mem.splitScalar(u8, text[start + 1 ..], '.');
        while (identifiers.next()) |identifier| {
            if (identifier.len == 0) return error.InvalidVersion;
            for (identifier) |byte| {
                if (!std.ascii.isAlphanumeric(byte) and byte != '-') return error.InvalidVersion;
            }
        }
    }
    var components = std.mem.splitScalar(u8, core, '.');
    const major = try parseComponent(components.next() orelse return error.InvalidVersion);
    const minor = try parseComponent(components.next() orelse return error.InvalidVersion);
    const patch = try parseComponent(components.next() orelse return error.InvalidVersion);
    if (components.next() != null) return error.InvalidVersion;
    return .{ .major = major, .minor = minor, .patch = patch };
}

fn parseComponent(text: []const u8) !u32 {
    if (text.len == 0 or (text.len > 1 and text[0] == '0')) return error.InvalidVersion;
    for (text) |byte| {
        if (!std.ascii.isDigit(byte)) return error.InvalidVersion;
    }
    return std.fmt.parseInt(u32, text, 10) catch return error.InvalidVersion;
}

/// This registry deliberately accepts one exact runtime release, not a family.
pub fn supported(v: Version) !void {
    if (!eql(v, .{ .major = 1, .minor = 17, .patch = 0 })) return error.UnsupportedVersion;
}

pub fn eql(a: Version, b: Version) bool {
    return a.major == b.major and a.minor == b.minor and a.patch == b.patch;
}

test "only the pinned release is supported, with build metadata ignored" {
    for ([_][]const u8{ "1.17.0", "1.17.0+build.007", "1.17.0+local-build" }) |text| {
        const parsed = try parse(text);
        try supported(parsed);
        try std.testing.expect(eql(parsed, .{ .major = 1, .minor = 17, .patch = 0 }));
    }
    for ([_][]const u8{ "0.17.0", "1.16.0", "1.17.1", "1.18.0", "2.17.0" }) |text| {
        try std.testing.expectError(error.UnsupportedVersion, supported(try parse(text)));
    }
}

test "prereleases are rejected even with build metadata" {
    for ([_][]const u8{ "1.17.0-dev", "1.17.0-rc.1", "1.17.0-dev+abcdef" }) |text| {
        try std.testing.expectError(error.PrereleaseVersion, parse(text));
    }
}

test "version grammar rejects banners whitespace missing components and overflow" {
    for ([_][]const u8{
        "",                "v1.17.0",        "Firecracker v1.17.0", "1.17",       "1.17.0.1",
        "1..0",            "1.17.0\n",       " 1.17.0",             "01.17.0",    "1.017.0",
        "1.17.00",         "1.17.0+",        "1.17.0+a..b",         "1.17.0+a+b", "1.17.0+a/b",
        "4294967296.17.0", "1.4294967296.0", "1.17.4294967296",     "+1.17.0",
    }) |text| {
        try std.testing.expectError(error.InvalidVersion, parse(text));
    }
    const largest = try parse("4294967295.4294967295.4294967295");
    try std.testing.expectEqual(std.math.maxInt(u32), largest.patch);
}
