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
