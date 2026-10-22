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
