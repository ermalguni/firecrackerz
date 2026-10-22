const std = @import("std");

/// Owned live instance information, independent of the client and HTTP response.
/// State is the server string (Not started, Running, or Paused in v1.17).
/// Running does not establish guest/application readiness.
pub const InstanceInfo = struct {
    id: []const u8,
    state: []const u8,
    vmm_version: []const u8,
    app_name: []const u8,
    arena: *std.heap.ArenaAllocator,

    pub fn deinit(self: *InstanceInfo) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }
};
