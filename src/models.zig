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

/// Owned full resource configuration. Nested values borrow this result's arena;
/// release only the enclosing result. Missing and null resources remain null.
/// Snapshot restores may omit boot_source, machine_config.smt and cpu_template.
pub const FullVmConfiguration = struct {
    boot_source: ?BootSourceRequest,
    machine_config: ?MachineConfigurationRequest,
    drives: ?[]const DriveRequest,
    network_interfaces: ?[]const NetworkInterfaceRequest,
    cpu_config: ?CpuConfiguration,
    balloon: ?BalloonConfiguration,
    vsock: ?VsockConfiguration,
    entropy: ?EntropyConfiguration,
    mmds_config: ?MmdsConfiguration,
    logger: ?LoggerRequest,
    metrics: ?MetricsRequest,
    pmem: ?[]const PmemConfiguration,
    memory_hotplug: ?MemoryHotplugConfiguration,
    arena: *std.heap.ArenaAllocator,

    pub fn deinit(self: *FullVmConfiguration) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }
};

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

pub const BalloonConfiguration = struct {
    amount_mib: i64,
    deflate_on_oom: bool,
    stats_polling_interval_s: ?i64 = null,
    free_page_hinting: ?bool = null,
    free_page_reporting: ?bool = null,
};

/// Changes only the target size of an existing balloon, in MiB.
/// Firecracker validates the value and device/lifecycle restrictions.
pub const BalloonUpdate = struct {
    amount_mib: i64,
};

/// Changes only the balloon statistics interval, in seconds.
/// Firecracker validates values; statistics cannot be toggled after boot.
pub const BalloonStatisticsUpdate = struct {
    stats_polling_interval_s: i64,
};

/// Starts a hinting run. Null leaves automatic acknowledgment to Firecracker.
pub const BalloonHintingStartRequest = struct {
    acknowledge_on_stop: ?bool = null,
};

/// Last host/guest hinting commands, not a completion or readiness guarantee.
/// Scalar values outlive the client/result; absent guest commands remain null.
pub const BalloonHintingStatus = struct {
    host_cmd: i64,
    guest_cmd: ?i64 = null,
};

/// Latest balloon statistics. Scalar values outlive the client and result.
/// Missing guest counters remain null, not zero. Swap, free/total/available
/// memory, and disk-cache counters are bytes; target/actual units are in names.
pub const BalloonStatistics = struct {
    target_pages: i64,
    actual_pages: i64,
    target_mib: i64,
    actual_mib: i64,
    swap_in: ?i64 = null,
    swap_out: ?i64 = null,
    major_faults: ?i64 = null,
    minor_faults: ?i64 = null,
    free_memory: ?i64 = null,
    total_memory: ?i64 = null,
    available_memory: ?i64 = null,
    disk_caches: ?i64 = null,
    hugetlb_allocations: ?i64 = null,
    hugetlb_failures: ?i64 = null,
    oom_kill: ?i64 = null,
    alloc_stall: ?i64 = null,
    async_scan: ?i64 = null,
    direct_scan: ?i64 = null,
    async_reclaim: ?i64 = null,
    direct_reclaim: ?i64 = null,
};

/// Pre-boot vsock configuration. Request strings are borrowed for the call;
/// uds_path belongs to the Firecracker server's filesystem namespace.
pub const VsockConfiguration = struct {
    guest_cid: i64,
    uds_path: []const u8,
    vsock_id: ?[]const u8 = null,
};

/// Pre-boot entropy device configuration. Null rate limiters are omitted.
pub const EntropyConfiguration = struct {
    rate_limiter: ?RateLimiter = null,
};

/// Serial console configuration. The output path is borrowed for the call and
/// resolved by Firecracker, not opened locally. Null fields are omitted.
/// The limiter is a single token bucket, not a bandwidth/operations pair.
pub const SerialConfiguration = struct {
    serial_out_path: ?[]const u8 = null,
    rate_limiter: ?TokenBucket = null,
};

pub const MmdsConfiguration = struct {
    network_interfaces: []const []const u8,
    version: ?[]const u8 = null,
    imds_compat: ?bool = null,
    ipv4_address: ?[]const u8 = null,
};

/// Pre-boot pmem configuration. Borrowed id selects both URL and body;
/// path_on_host is resolved by Firecracker. Null fields are omitted.
pub const PmemConfiguration = struct {
    id: []const u8,
    path_on_host: []const u8,
    root_device: ?bool = null,
    read_only: ?bool = null,
    rate_limiter: ?RateLimiter = null,
};

/// Post-boot pmem rate-limiter update. The borrowed ID selects URL and body.
/// Null omits the limiter; explicit zero-valued token buckets are sent.
pub const PmemUpdate = struct {
    id: []const u8,
    rate_limiter: ?RateLimiter = null,
};

pub const MemoryHotplugConfiguration = struct {
    total_size_mib: ?i64 = null,
    slot_size_mib: ?i64 = null,
    block_size_mib: ?i64 = null,
};

/// Requests a new virtio-mem target in MiB. Null is omitted; zero is sent.
/// Firecracker validates capacity, alignment, and lifecycle restrictions.
pub const MemoryHotplugUpdate = struct {
    requested_size_mib: ?i64 = null,
};

/// Scalar virtio-mem status in MiB, independent of the client/result lifetime.
/// Absent fields remain null. Requested size need not equal plugged size.
pub const MemoryHotplugStatus = struct {
    total_size_mib: ?i64 = null,
    slot_size_mib: ?i64 = null,
    block_size_mib: ?i64 = null,
    plugged_size_mib: ?i64 = null,
    requested_size_mib: ?i64 = null,
};

/// Custom CPU template, also returned within full VM configuration.
/// For PUT, strings and nested slices are borrowed for the call; null fields
/// are omitted and explicit empty arrays are preserved. Firecracker validates
/// architecture-specific fields and bitmaps; acceptance is not proof of boot.
pub const CpuConfiguration = struct {
    cpuid_modifiers: ?[]const CpuidLeafModifier = null,
    kvm_capabilities: ?[]const []const u8 = null,
    msr_modifiers: ?[]const CpuRegisterModifier = null,
    vcpu_features: ?[]const VcpuFeatures = null,
    reg_modifiers: ?[]const CpuRegisterModifier = null,
};

pub const CpuidLeafModifier = struct {
    leaf: []const u8,
    subleaf: []const u8,
    flags: i64,
    modifiers: []const CpuidRegisterModifier,
};

pub const CpuidRegisterModifier = struct {
    register: []const u8,
    bitmap: []const u8,
};

pub const CpuRegisterModifier = struct {
    addr: []const u8,
    bitmap: []const u8,
};

pub const VcpuFeatures = struct {
    index: i64,
    bitmap: []const u8,
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

/// Updates an existing drive, including after boot; does not attach a device.
/// Strings are borrowed. Null fields are omitted, not reset.
/// Coordinate backing-file changes with the guest to prevent concurrent I/O.
pub const DriveUpdate = struct {
    drive_id: []const u8,
    path_on_host: ?[]const u8 = null,
    rate_limiter: ?RateLimiter = null,
};

/// Pre-boot network interface creation/replacement. Strings are borrowed for
/// the call. The TAP device must already exist in Firecracker's network namespace.
/// Firecracker validates MAC, MTU, rate limits, and lifecycle restrictions.
pub const NetworkInterfaceRequest = struct {
    iface_id: []const u8,
    host_dev_name: []const u8,
    guest_mac: ?[]const u8 = null,
    mtu: ?i64 = null,
    rx_rate_limiter: ?RateLimiter = null,
    tx_rate_limiter: ?RateLimiter = null,
};

/// Updates rate limiters on an existing interface, including after boot.
/// The ID is borrowed. Null fields are omitted, leaving those limits unchanged.
pub const NetworkInterfaceUpdate = struct {
    iface_id: []const u8,
    rx_rate_limiter: ?RateLimiter = null,
    tx_rate_limiter: ?RateLimiter = null,
};

/// Logger configuration. Strings are borrowed for the call. The destination
/// belongs to Firecracker's filesystem namespace; the client never opens it.
/// Null fields are omitted; Firecracker applies defaults and validates values.
pub const LoggerRequest = struct {
    log_path: ?[]const u8 = null,
    level: ?[]const u8 = null,
    show_level: ?bool = null,
    show_log_origin: ?bool = null,
    module: ?[]const u8 = null,
};

/// Metrics initialization. The path, property map, keys, and values are borrowed
/// during the call. The caller retains ownership of the map and its strings.
pub const MetricsRequest = struct {
    metrics_path: []const u8,
    emit_id: ?bool = null,
    properties: ?std.json.ArrayHashMap([]const u8) = null,
};

/// Post-boot snapshot creation. The VM must be paused; Diff requires dirty-page
/// tracking. Strings are borrowed and paths belong to Firecracker's filesystem.
/// Null options are omitted: Firecracker defaults to Full and syncing files.
pub const SnapshotCreateRequest = struct {
    mem_file_path: []const u8,
    snapshot_path: []const u8,
    snapshot_type: ?[]const u8 = null,
    sync_snapshot_files: ?bool = null,
};

/// Loads into a fresh process (only logger/metrics may already be configured).
/// Exactly one of mem_backend and mem_file_path must be supplied.
/// All strings and slices are borrowed during the call; null options are omitted.
/// Firecracker validates combinations, values, and snapshot compatibility.
pub const SnapshotLoadRequest = struct {
    snapshot_path: []const u8,
    mem_backend: ?MemoryBackend = null,
    /// Deprecated upstream; prefer mem_backend with backend_type = "File".
    mem_file_path: ?[]const u8 = null,
    track_dirty_pages: ?bool = null,
    /// Deprecated upstream; prefer track_dirty_pages.
    enable_diff_snapshots: ?bool = null,
    resume_vm: ?bool = null,
    network_overrides: ?[]const NetworkOverride = null,
    vsock_override: ?VsockOverride = null,
    clock_realtime: ?bool = null,
    huge_pages: ?[]const u8 = null,
};

/// File uses a memory image path; Uffd uses an external page-fault server's UDS.
/// Paths belong to Firecracker's filesystem namespace.
pub const MemoryBackend = struct {
    backend_type: []const u8,
    backend_path: []const u8,
};

pub const NetworkOverride = struct {
    iface_id: []const u8,
    host_dev_name: []const u8,
};

pub const VsockOverride = struct {
    uds_path: []const u8,
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
