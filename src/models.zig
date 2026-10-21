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

/// Pre-boot drive creation/replacement. Strings are borrowed for the call.
/// Paths and sockets belong to Firecracker's filesystem namespace.
/// Virtio-block requires path_on_host and is_read_only; vhost-user uses socket.
/// Firecracker validates device-specific combinations and values.
pub const DriveRequest = struct {
    drive_id: []const u8,
    is_root_device: bool,
    partuuid: ?[]const u8 = null,
    cache_type: ?[]const u8 = null,
    is_read_only: ?bool = null,
    discard: ?bool = null,
    path_on_host: ?[]const u8 = null,
    rate_limiter: ?RateLimiter = null,
    io_engine: ?[]const u8 = null,
    blk_size: ?i64 = null,
    topology: ?BlockTopology = null,
    socket: ?[]const u8 = null,
};

pub const RateLimiter = struct {
    bandwidth: ?TokenBucket = null,
    ops: ?TokenBucket = null,
};

pub const TokenBucket = struct {
    size: i64,
    refill_time: i64,
    one_time_burst: ?i64 = null,
};

pub const BlockTopology = struct {
    physical_block_exp: ?i64 = null,
    alignment_offset: ?i64 = null,
    min_io_size: ?i64 = null,
    opt_io_size: ?i64 = null,
};
