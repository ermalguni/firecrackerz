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
