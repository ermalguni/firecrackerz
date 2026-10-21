const std = @import("std");
const version = @import("version.zig");
const models = @import("../models.zig");
const v1_17 = @import("../versions/v1_17/adapter.zig");

pub const Backend = union(enum) {
    v1_17,

    pub fn select(runtime: version.Version) !Backend {
        try version.supported(runtime);
        return .v1_17;
    }

    pub fn contract(self: Backend) models.Contract {
        return switch (self) {
            .v1_17 => .v1_17,
        };
    }

    pub fn decodeVersion(self: Backend, allocator: std.mem.Allocator, body: []const u8) !version.Version {
        return switch (self) {
            .v1_17 => v1_17.decodeVersion(allocator, body),
        };
    }
};
