const std = @import("std");
const wire = @import("models.zig");
const version = @import("../../internal/version.zig");
const models = @import("../../models.zig");

pub fn decodeVersion(allocator: std.mem.Allocator, body: []const u8) !version.Version {
    const parsed = try std.json.parseFromSlice(wire.FirecrackerVersion, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return version.parse(parsed.value.firecracker_version);
}

pub fn decodeInstanceInfo(allocator: std.mem.Allocator, body: []const u8) !models.InstanceInfo {
    const parsed = try std.json.parseFromSlice(wire.InstanceInfo, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    return .{
        .id = parsed.value.id,
        .state = parsed.value.state,
        .vmm_version = parsed.value.vmm_version,
        .app_name = parsed.value.app_name,
        .arena = parsed.arena,
    };
}

pub fn decodeMachineConfiguration(allocator: std.mem.Allocator, body: []const u8) !models.MachineConfiguration {
    const parsed = try std.json.parseFromSlice(wire.MachineConfiguration, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    // Transfer the parse arena, not the wire type. Strings must outlive the HTTP response.
    return .{
        .vcpu_count = parsed.value.vcpu_count,
        .mem_size_mib = parsed.value.mem_size_mib,
        .smt = parsed.value.smt,
        .track_dirty_pages = parsed.value.track_dirty_pages,
        .cpu_template = parsed.value.cpu_template,
        .huge_pages = parsed.value.huge_pages,
        .arena = parsed.arena,
    };
}

pub fn decodeBalloon(allocator: std.mem.Allocator, body: []const u8) !models.BalloonConfiguration {
    const parsed = try std.json.parseFromSlice(wire.Balloon, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return .{
        .amount_mib = parsed.value.amount_mib,
        .deflate_on_oom = parsed.value.deflate_on_oom,
        .stats_polling_interval_s = parsed.value.stats_polling_interval_s,
        .free_page_hinting = parsed.value.free_page_hinting,
        .free_page_reporting = parsed.value.free_page_reporting,
    };
}

pub fn decodeBalloonStatistics(allocator: std.mem.Allocator, body: []const u8) !models.BalloonStatistics {
    const parsed = try std.json.parseFromSlice(wire.BalloonStats, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return .{
        .target_pages = parsed.value.target_pages,
        .actual_pages = parsed.value.actual_pages,
        .target_mib = parsed.value.target_mib,
        .actual_mib = parsed.value.actual_mib,
        .swap_in = parsed.value.swap_in,
        .swap_out = parsed.value.swap_out,
        .major_faults = parsed.value.major_faults,
        .minor_faults = parsed.value.minor_faults,
        .free_memory = parsed.value.free_memory,
        .total_memory = parsed.value.total_memory,
        .available_memory = parsed.value.available_memory,
        .disk_caches = parsed.value.disk_caches,
        .hugetlb_allocations = parsed.value.hugetlb_allocations,
        .hugetlb_failures = parsed.value.hugetlb_failures,
        .oom_kill = parsed.value.oom_kill,
        .alloc_stall = parsed.value.alloc_stall,
        .async_scan = parsed.value.async_scan,
        .direct_scan = parsed.value.direct_scan,
        .async_reclaim = parsed.value.async_reclaim,
        .direct_reclaim = parsed.value.direct_reclaim,
    };
}

pub fn decodeVmConfiguration(allocator: std.mem.Allocator, body: []const u8) !models.FullVmConfiguration {
    // Nested public values match this contract's JSON shapes. Decode directly
    // into them to avoid allocating and copying a second set of device arrays.
    const Configuration = struct {
        @"boot-source": ?models.BootSourceRequest = null,
        @"machine-config": ?models.MachineConfigurationRequest = null,
        drives: ?[]const models.DriveRequest = null,
        @"network-interfaces": ?[]const models.NetworkInterfaceRequest = null,
        @"cpu-config": ?models.CpuConfiguration = null,
        balloon: ?models.BalloonConfiguration = null,
        vsock: ?models.VsockConfiguration = null,
        entropy: ?models.EntropyConfiguration = null,
        @"mmds-config": ?models.MmdsConfiguration = null,
        logger: ?models.LoggerRequest = null,
        metrics: ?models.MetricsRequest = null,
        pmem: ?[]const models.PmemConfiguration = null,
        @"memory-hotplug": ?models.MemoryHotplugConfiguration = null,
    };
    const parsed = try std.json.parseFromSlice(Configuration, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    const value = parsed.value;
    return .{
        .boot_source = value.@"boot-source",
        .machine_config = value.@"machine-config",
        .drives = value.drives,
        .network_interfaces = value.@"network-interfaces",
        .cpu_config = value.@"cpu-config",
        .balloon = value.balloon,
        .vsock = value.vsock,
        .entropy = value.entropy,
        .mmds_config = value.@"mmds-config",
        .logger = value.logger,
        .metrics = value.metrics,
        .pmem = value.pmem,
        .memory_hotplug = value.@"memory-hotplug",
        .arena = parsed.arena,
    };
}

pub fn encodeMachineConfiguration(allocator: std.mem.Allocator, request: models.MachineConfigurationRequest) ![]u8 {
    const value: wire.MachineConfiguration = .{
        .vcpu_count = request.vcpu_count,
        .mem_size_mib = request.mem_size_mib,
        .smt = request.smt,
        .track_dirty_pages = request.track_dirty_pages,
        .cpu_template = request.cpu_template,
        .huge_pages = request.huge_pages,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeMachineConfigurationUpdate(allocator: std.mem.Allocator, request: models.MachineConfigurationUpdate) ![]u8 {
    // The schema reuses the PUT model with required CPU/memory fields, but
    // PATCH accepts a subset. Keep every field optional without changing codegen.
    return std.json.Stringify.valueAlloc(allocator, request, .{ .emit_null_optional_fields = false });
}

pub fn encodeCpuConfiguration(allocator: std.mem.Allocator, request: models.CpuConfiguration) ![]u8 {
    // Public nested shapes match this contract. Borrow their slices instead of
    // allocating a second tree of generated wire entries.
    return std.json.Stringify.valueAlloc(allocator, request, .{ .emit_null_optional_fields = false });
}

pub fn encodeBootSource(allocator: std.mem.Allocator, request: models.BootSourceRequest) ![]u8 {
    const value: wire.BootSource = .{
        .kernel_image_path = request.kernel_image_path,
        .boot_args = request.boot_args,
        .initrd_path = request.initrd_path,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeDrive(allocator: std.mem.Allocator, request: models.DriveRequest) ![]u8 {
    const value: wire.Drive = .{
        .drive_id = request.drive_id,
        .is_root_device = request.is_root_device,
        .partuuid = request.partuuid,
        .cache_type = request.cache_type,
        .is_read_only = request.is_read_only,
        .discard = request.discard,
        .path_on_host = request.path_on_host,
        .rate_limiter = encodeRateLimiter(request.rate_limiter),
        .io_engine = request.io_engine,
        .blk_size = request.blk_size,
        .topology = if (request.topology) |topology| .{
            .physical_block_exp = topology.physical_block_exp,
            .alignment_offset = topology.alignment_offset,
            .min_io_size = topology.min_io_size,
            .opt_io_size = topology.opt_io_size,
        } else null,
        .socket = request.socket,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeDriveUpdate(allocator: std.mem.Allocator, request: models.DriveUpdate) ![]u8 {
    const value: wire.PartialDrive = .{
        .drive_id = request.drive_id,
        .path_on_host = request.path_on_host,
        .rate_limiter = encodeRateLimiter(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeVsock(allocator: std.mem.Allocator, request: models.VsockConfiguration) ![]u8 {
    const value: wire.Vsock = .{
        .guest_cid = request.guest_cid,
        .uds_path = request.uds_path,
        .vsock_id = request.vsock_id,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeEntropy(allocator: std.mem.Allocator, request: models.EntropyConfiguration) ![]u8 {
    const value: wire.EntropyDevice = .{
        .rate_limiter = encodeRateLimiter(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeSerial(allocator: std.mem.Allocator, request: models.SerialConfiguration) ![]u8 {
    const value: wire.SerialDevice = .{
        .serial_out_path = request.serial_out_path,
        .rate_limiter = encodeTokenBucket(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodePmem(allocator: std.mem.Allocator, request: models.PmemConfiguration) ![]u8 {
    const value: wire.Pmem = .{
        .id = request.id,
        .path_on_host = request.path_on_host,
        .root_device = request.root_device,
        .read_only = request.read_only,
        .rate_limiter = encodeRateLimiter(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodePmemUpdate(allocator: std.mem.Allocator, request: models.PmemUpdate) ![]u8 {
    const value: wire.PartialPmem = .{
        .id = request.id,
        .rate_limiter = encodeRateLimiter(request.rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeNetworkInterface(allocator: std.mem.Allocator, request: models.NetworkInterfaceRequest) ![]u8 {
    const value: wire.NetworkInterface = .{
        .iface_id = request.iface_id,
        .host_dev_name = request.host_dev_name,
        .guest_mac = request.guest_mac,
        .mtu = request.mtu,
        .rx_rate_limiter = encodeRateLimiter(request.rx_rate_limiter),
        .tx_rate_limiter = encodeRateLimiter(request.tx_rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeNetworkInterfaceUpdate(allocator: std.mem.Allocator, request: models.NetworkInterfaceUpdate) ![]u8 {
    const value: wire.PartialNetworkInterface = .{
        .iface_id = request.iface_id,
        .rx_rate_limiter = encodeRateLimiter(request.rx_rate_limiter),
        .tx_rate_limiter = encodeRateLimiter(request.tx_rate_limiter),
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeBalloon(allocator: std.mem.Allocator, request: models.BalloonConfiguration) ![]u8 {
    const value: wire.Balloon = .{
        .amount_mib = request.amount_mib,
        .deflate_on_oom = request.deflate_on_oom,
        .stats_polling_interval_s = request.stats_polling_interval_s,
        .free_page_hinting = request.free_page_hinting,
        .free_page_reporting = request.free_page_reporting,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeBalloonUpdate(allocator: std.mem.Allocator, request: models.BalloonUpdate) ![]u8 {
    const value: wire.BalloonUpdate = .{ .amount_mib = request.amount_mib };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeBalloonStatisticsUpdate(allocator: std.mem.Allocator, request: models.BalloonStatisticsUpdate) ![]u8 {
    const value: wire.BalloonStatsUpdate = .{ .stats_polling_interval_s = request.stats_polling_interval_s };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeBalloonHintingStart(allocator: std.mem.Allocator, request: models.BalloonHintingStartRequest) ![]u8 {
    const value: wire.BalloonStartCmd = .{ .acknowledge_on_stop = request.acknowledge_on_stop };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn decodeBalloonHintingStatus(allocator: std.mem.Allocator, body: []const u8) !models.BalloonHintingStatus {
    const parsed = try std.json.parseFromSlice(wire.BalloonHintingStatus, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return .{ .host_cmd = parsed.value.host_cmd, .guest_cmd = parsed.value.guest_cmd };
}

pub fn encodeMemoryHotplug(allocator: std.mem.Allocator, request: models.MemoryHotplugConfiguration) ![]u8 {
    const value: wire.MemoryHotplugConfig = .{
        .total_size_mib = request.total_size_mib,
        .slot_size_mib = request.slot_size_mib,
        .block_size_mib = request.block_size_mib,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeMemoryHotplugUpdate(allocator: std.mem.Allocator, request: models.MemoryHotplugUpdate) ![]u8 {
    const value: wire.MemoryHotplugSizeUpdate = .{ .requested_size_mib = request.requested_size_mib };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn decodeMemoryHotplugStatus(allocator: std.mem.Allocator, body: []const u8) !models.MemoryHotplugStatus {
    const parsed = try std.json.parseFromSlice(wire.MemoryHotplugStatus, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return .{
        .total_size_mib = parsed.value.total_size_mib,
        .slot_size_mib = parsed.value.slot_size_mib,
        .block_size_mib = parsed.value.block_size_mib,
        .plugged_size_mib = parsed.value.plugged_size_mib,
        .requested_size_mib = parsed.value.requested_size_mib,
    };
}

pub fn encodeMmdsConfiguration(allocator: std.mem.Allocator, request: models.MmdsConfiguration) ![]u8 {
    const value: wire.MmdsConfig = .{
        .network_interfaces = request.network_interfaces,
        .version = request.version,
        .imds_compat = request.imds_compat,
        .ipv4_address = request.ipv4_address,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeLogger(allocator: std.mem.Allocator, request: models.LoggerRequest) ![]u8 {
    const value: wire.Logger = .{
        .log_path = request.log_path,
        .level = request.level,
        .show_level = request.show_level,
        .show_log_origin = request.show_log_origin,
        .module = request.module,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeMetrics(allocator: std.mem.Allocator, request: models.MetricsRequest) ![]u8 {
    // The generated properties field is an untyped json.Value. Serialize the
    // schema's string-only map directly, without allocating a second map.
    const value = .{
        .metrics_path = request.metrics_path,
        .emit_id = request.emit_id,
        .properties = request.properties,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeSnapshotCreate(allocator: std.mem.Allocator, request: models.SnapshotCreateRequest) ![]u8 {
    const value: wire.SnapshotCreateParams = .{
        .mem_file_path = request.mem_file_path,
        .snapshot_path = request.snapshot_path,
        .snapshot_type = request.snapshot_type,
        .sync_snapshot_files = request.sync_snapshot_files,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

pub fn encodeSnapshotLoad(allocator: std.mem.Allocator, request: models.SnapshotLoadRequest) ![]u8 {
    // The public override entries match this contract's JSON shape. Borrow the
    // slice instead of allocating a second array of generated wire entries.
    const value = .{
        .snapshot_path = request.snapshot_path,
        .mem_backend = if (request.mem_backend) |backend| @as(wire.MemoryBackend, .{
            .backend_type = backend.backend_type,
            .backend_path = backend.backend_path,
        }) else null,
        .mem_file_path = request.mem_file_path,
        .track_dirty_pages = request.track_dirty_pages,
        .enable_diff_snapshots = request.enable_diff_snapshots,
        .resume_vm = request.resume_vm,
        .network_overrides = request.network_overrides,
        .vsock_override = if (request.vsock_override) |vsock| @as(wire.VsockOverride, .{
            .uds_path = vsock.uds_path,
        }) else null,
        .clock_realtime = request.clock_realtime,
        .huge_pages = request.huge_pages,
    };
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}

fn encodeRateLimiter(limiter: ?models.RateLimiter) ?wire.RateLimiter {
    const value = limiter orelse return null;
    return .{
        .bandwidth = encodeTokenBucket(value.bandwidth),
        .ops = encodeTokenBucket(value.ops),
    };
}

fn encodeTokenBucket(bucket: ?models.TokenBucket) ?wire.TokenBucket {
    const value = bucket orelse return null;
    return .{
        .size = value.size,
        .refill_time = value.refill_time,
        .one_time_burst = value.one_time_burst,
    };
}
