const std = @import("std");

/// Stable numeric runtime version; semantic-version build metadata is ignored.
pub const Version = struct { major: u32, minor: u32, patch: u32 };

pub const Contract = enum { v1_17 };

/// Borrowed metadata: strings remain valid until Client.deinit.
pub const ConnectionInfo = struct {
    executable_path: []const u8,
    detected_version: Version,
    running_version: Version,
    contract: Contract,
};

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

/// Pre-boot boot source. Strings are borrowed for the call. Paths are resolved
/// by Firecracker in its filesystem namespace, not by this client.
pub const BootSourceRequest = struct {
    kernel_image_path: []const u8,
    boot_args: ?[]const u8 = null,
    initrd_path: ?[]const u8 = null,
};
