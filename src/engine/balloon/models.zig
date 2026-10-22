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
