const std = @import("std");

/// Owned response. Optional fields preserve absence rather than invent defaults.
/// Strings remain valid until deinit; storage is independent of the client.
pub const MachineConfiguration = struct {
    vcpu_count: i64,
    mem_size_mib: i64,
    smt: ?bool,
    track_dirty_pages: ?bool,
    cpu_template: ?[]const u8,
    huge_pages: ?[]const u8,
    arena: *std.heap.ArenaAllocator,

    pub fn deinit(self: *MachineConfiguration) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }
};

/// Pre-boot replacement configuration, not a partial update. Strings are borrowed
/// for the call; null optional fields are omitted and reset to server defaults.
pub const MachineConfigurationRequest = struct {
    vcpu_count: i64,
    mem_size_mib: i64,
    smt: ?bool = null,
    track_dirty_pages: ?bool = null,
    cpu_template: ?[]const u8 = null,
    huge_pages: ?[]const u8 = null,
};

/// Pre-boot partial update. Null fields are omitted, preserving current values.
/// Explicit false, zero, and empty strings are sent for server validation.
/// Strings are borrowed for the call.
pub const MachineConfigurationUpdate = struct {
    vcpu_count: ?i64 = null,
    mem_size_mib: ?i64 = null,
    smt: ?bool = null,
    track_dirty_pages: ?bool = null,
    cpu_template: ?[]const u8 = null,
    huge_pages: ?[]const u8 = null,
};
