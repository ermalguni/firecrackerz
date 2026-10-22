const std = @import("std");

/// Owned MMDS JSON tree. Nested strings, keys, and containers borrow the arena.
/// Numbers are number_string values to avoid loss of precision during parsing.
pub const MmdsContents = struct {
    value: std.json.Value,
    arena: *std.heap.ArenaAllocator,

    pub fn deinit(self: *MmdsContents) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }
};

pub const MmdsConfiguration = struct {
    network_interfaces: []const []const u8,
    version: ?[]const u8 = null,
    imds_compat: ?bool = null,
    ipv4_address: ?[]const u8 = null,
};
