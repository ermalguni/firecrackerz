# firecrackerz

Zig 0.17 bindings for the [Firecracker API](https://github.com/firecracker-microvm/firecracker), with one public client and private version adapters.

## Status and scope

Connection, live instance-information reads, machine configuration reads/writes, boot-source configuration, drive and network-interface configuration, logger and metrics configuration, metrics flushing, and instance start/pause/resume are implemented: executable discovery, version selection, Unix-socket HTTP handshake, connection metadata, `getInstanceInfo()`, `getMachineConfiguration()`, `putMachineConfiguration()`, `putGuestBootSource()`, `putGuestDrive()`, `putGuestNetworkInterface()`, `putLogger()`, `putMetrics()`, `flushMetrics()`, `startInstance()`, `pauseInstance()`, `resumeInstance()`, and resource cleanup. **Firecracker v1.17.0 is the only accepted runtime release.** A disposable disk-backed guest has booted through the client to a minimal init program.

`sendCtrlAltDel()`, `createSnapshot()`, `loadSnapshot()`, and `putBalloon()` are also implemented. Other device configuration, capability queries, and development-snapshot support are not implemented. Generated v1.18 models do not establish runtime support.

`getVmConfiguration()` exports the full VM resource configuration via `GET /vm/config`.
`patchMachineConfiguration()` partially updates pre-boot machine settings via `PATCH /machine-config`.
`putCpuConfiguration()` configures custom pre-boot CPU features via `PUT /cpu-config`.
`getBalloon()` reads live balloon device configuration via `GET /balloon`.
`patchBalloon()` changes an existing balloon's target size via `PATCH /balloon`.
`getBalloonStatistics()` reads the latest balloon statistics via `GET /balloon/statistics`.
`patchBalloonStatistics()` changes the polling interval via `PATCH /balloon/statistics`.
`startBalloonHinting()`, `stopBalloonHinting()`, and `getBalloonHintingStatus()` bind the free-page hinting endpoints.
`putMemoryHotplug()`, `patchMemoryHotplug()`, and `getMemoryHotplug()` bind `PUT/PATCH/GET /hotplug/memory`.

The client connects to an existing process. Launching Firecracker, managing the jailer, preparing images, host networking, guest readiness checks, and process cleanup remain application responsibilities.

## Requirements

- Linux and Zig 0.17.0.
- A trusted Firecracker v1.17.0 executable and an accessible running API socket.
- Dusty v0.4.0, pinned by commit and package hash in `build.zig.zon`.
- Python 3 for protocol scenarios; `openapi2zig` on `PATH` only for model generation.

## Usage

The build exports a module named `firecrackerz`. Add it to your application's root module:

```zig
const firecrackerz = b.dependency("firecrackerz", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("firecrackerz", firecrackerz.module("firecrackerz"));
```

With an allocator and `std.Io` supplied by the application:

```zig
const fc = @import("firecrackerz");

var result = try fc.Client.connect(allocator, io, .{
    .socket_path = "/run/firecracker.sock",
    .binary = .{ .executable = "/usr/bin/firecracker" },
    // Alternatively: .binary = .{ .search_path = process_path },
    .discovery_timeout_ms = 3000,
    .request_timeout_ms = 3000,
});
defer result.deinit();

switch (result) {
    .success => |*client| {
        const info = client.info();
        std.log.info("Connected to {s}, contract {s}", .{
            info.executable_path, @tagName(info.contract),
        });
    },
    .fault => |fault| {
        std.log.err("Firecracker HTTP {d}: {s}", .{ fault.status, fault.body });
    },
}
```

`search_path` is a caller-provided colon-separated PATH directory list, not an executable name. Discovery searches for `firecracker`; empty entries designate the current directory. Privileged applications should supply a trusted explicit executable path instead.

### Reading live instance information

On a successfully connected client:

```zig
var instance = try client.getInstanceInfo();
defer instance.deinit();

switch (instance) {
    .success => |value| std.log.info("Instance {s}: {s} ({s} {s})", .{
        value.id, value.state, value.app_name, value.vmm_version,
    }),
    .fault => |fault| std.log.err("Instance information HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

`getInstanceInfo()` sends a fresh `GET /` request and returns `Result(models.InstanceInfo)`. Unlike `client.info()` (cached handshake metadata), this is a live, read-only snapshot. It neither polls nor waits for readiness.

All four response fields—`id`, `state`, `vmm_version`, and `app_name`—are required strings. The v1.17 states are `Not started`, `Running`, and `Paused`. State strings are preserved rather than mapped to an enum; callers must handle unfamiliar values explicitly, not treat them as running. Additional JSON fields are ignored. `vmm_version` preserves the returned build-version string; it does not replace the version verified during connection.

Strings are owned by the result, independent of the HTTP response and client. A result may outlive the client but not its allocator; subsequent reads do not mutate retained results. Call `instance.deinit()` exactly once, do not separately deinitialize the contained value, and do not modify its internal arena.

HTTP 200 is decoded; all other statuses preserve their raw body and status as an owned `.fault`. Malformed JSON, missing/null/non-string required fields, and transport failures return Zig errors. Existing timeout, response-size limit, and no-retry behavior apply. `Running` describes the VM, not guest application readiness.

### Exporting full VM configuration

```zig
var exported = try client.getVmConfiguration();
defer exported.deinit();

switch (exported) {
    .success => |config| {
        if (config.boot_source) |boot| {
            std.log.info("Kernel: {s}", .{boot.kernel_image_path});
        }
        for (config.drives orelse &.{}) |drive| {
            std.log.info("Drive: {s}", .{drive.drive_id});
        }
    },
    .fault => |fault| std.log.err("VM configuration HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

Returns `Result(models.FullVmConfiguration)` with typed `boot_source`,
`machine_config`, `drives`, `network_interfaces`, `cpu_config`, `balloon`,
`vsock`, `entropy`, `mmds_config`, `logger`, `metrics`, `pmem`, and
`memory_hotplug` fields. These cover the pinned v1.17 full-configuration schema;
it does not include MMDS contents, serial-console configuration, or guest state.
Existing request-shaped models are reused for matching nested configuration
values; this read does not add write endpoints for the additional devices.

All top-level fields are optional. Missing/null resources remain null, empty
arrays remain empty, and explicit zero/false/empty-string values are preserved.
For snapshot-restored VMs, upstream documents boot-source, machine-config.smt,
and machine-config.cpu_template as empty; callers must not infer boot settings
from them. Unknown JSON fields are ignored.

The enclosing result owns every nested string, slice, and metrics property map.
It may outlive the client, but not its allocator. Call `exported.deinit()` exactly
once; do not separately free nested data or modify the internal arena.
Only HTTP 200 is decoded. Other statuses return owned faults; malformed JSON,
invalid nested required fields, and transport failures return Zig errors.
The existing request timeout, 64 KiB response limit, and no-retry behavior apply.

The `inspect` example also calls this endpoint. Verification includes a live
read from a disposable Firecracker v1.17.0 process before boot, plus Unix-socket
protocol scenarios for nested resources, retained-result ownership across a
second read and client destruction, snapshot-shaped omissions, malformed
responses, HTTP faults, timeouts, disconnects, and oversized responses.

### Reading machine configuration

On a successfully connected client:

```zig
var configuration = try client.getMachineConfiguration();
defer configuration.deinit();

switch (configuration) {
    .success => |config| std.log.info("vCPUs: {d}; memory: {d} MiB", .{
        config.vcpu_count, config.mem_size_mib,
    }),
    .fault => |fault| std.log.err("Machine configuration HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

This sends `GET /machine-config` on a fresh connection, using the client's request timeout and response-body limit. It does not modify the VM.

The result is `Result(models.MachineConfiguration)`. Required fields are `vcpu_count` and `mem_size_mib`; `smt`, `track_dirty_pages`, `cpu_template`, and `huge_pages` preserve missing/null values as `null`. String values are owned by the result, independent of the HTTP response and client. The result may outlive the client but not its allocator. Call `configuration.deinit()` exactly once; do not separately deinitialize its success value. Its arena is internal ownership storage and must not be modified.

Non-200 responses preserve their status and raw body as `.fault`. Invalid JSON, missing required fields, and transport failures return Zig errors.

### Writing machine configuration

On a connected, **pre-boot** instance:

```zig
var updated = try client.putMachineConfiguration(.{
    .vcpu_count = 2,
    .mem_size_mib = 256,
    .track_dirty_pages = true,
});
defer updated.deinit();

switch (updated) {
    .success => {},
    .fault => |fault| std.log.err("Configuration rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

`models.MachineConfigurationRequest` is separate from the owned response model. Both integer fields are required; the optional fields are `smt`, `track_dirty_pages`, `cpu_template`, and `huge_pages`. Strings are borrowed only for the call. The adapter encodes every supplied field; null optional fields are omitted from JSON, while explicit `false` is preserved.

This is `PUT /machine-config`, **not PATCH**. Omitted optional settings reset to Firecracker defaults (`smt=false`, `track_dirty_pages=false`, no CPU template, `huge_pages=None`); they do not preserve the previous configuration. Firecracker validates values and lifecycle restrictions. Invalid configurations are returned as HTTP faults, not silently corrected locally.

The return type is `Result(void)`: HTTP 204 succeeds without JSON decoding; every other status is preserved as an owned fault. Call `updated.deinit()` even for a void success. Transport/allocation errors remain Zig errors. Requests use the existing timeout and response-size limit and are never automatically retried. A timeout or disconnect after sending a write does not prove the server rejected it; read back state before deciding whether to retry.

### Partially updating machine configuration

On a connected, **pre-boot** instance:

```zig
var patched = try client.patchMachineConfiguration(.{
    .mem_size_mib = 512,
    .track_dirty_pages = false,
});
defer patched.deinit();

switch (patched) {
    .success => {},
    .fault => |fault| std.log.err("Partial update rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

`models.MachineConfigurationUpdate` makes all six fields optional:
`vcpu_count`, `mem_size_mib`, `smt`, `track_dirty_pages`, `cpu_template`, and
`huge_pages`. Null fields are omitted from JSON and preserve the current setting,
unlike PUT's replacement semantics. Explicit false, zero, and empty strings are
sent unchanged for Firecracker to validate. Strings are borrowed during the call.
An empty update is sent as `{}`; the client does not impose additional validation.

Firecracker enforces pre-boot restrictions and rejects the entire update if a
supplied value is invalid. `Result(void)` succeeds only for HTTP 204; all other
statuses return owned faults. Call `patched.deinit()` on either outcome.
Transport/allocation failures remain Zig errors. There are no automatic retries:
after a timeout or disconnect, read back configuration before retrying.

`zig build configure-test -- SOCKET EXECUTABLE --disposable` exercises both PUT
and PATCH against a caller-supplied disposable instance. Live verification on
Firecracker v1.17.0 confirmed that a memory-only PATCH preserves CPU count and
optional settings, explicit false disables dirty-page tracking without resetting
other fields, and an invalid multi-field PATCH leaves prior configuration intact.
Protocol scenarios also cover empty updates, explicit values and string escaping,
owned HTTP faults, unexpected statuses, timeouts, disconnects, oversized responses,
and absence of automatic retries.

### Configuring custom CPU features

On a connected, **pre-boot x86_64** instance:

```zig
var cpu = try client.putCpuConfiguration(.{
    .cpuid_modifiers = &.{.{
        .leaf = "0x1",
        .subleaf = "0x0",
        .flags = 0,
        .modifiers = &.{.{
            .register = "ecx",
            // Clear SSE3; preserve the other bits. Choose a template for your guest.
            .bitmap = "0bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx0",
        }},
    }},
});
defer cpu.deinit();

switch (cpu) {
    .success => {},
    .fault => |fault| std.log.err("CPU template rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

The request uses the existing `models.CpuConfiguration`:

| Field | Architecture | Entry type |
| --- | --- | --- |
| `cpuid_modifiers` | x86_64 | `CpuidLeafModifier` with nested `CpuidRegisterModifier` |
| `msr_modifiers` | x86_64 | `CpuRegisterModifier` |
| `reg_modifiers` | aarch64 | `CpuRegisterModifier` |
| `vcpu_features` | aarch64 | `VcpuFeatures` |
| `kvm_capabilities` | Both | Numeric strings; prefix `!` to remove a capability |

All fields are optional. Null fields are omitted; explicit empty arrays and
all supplied nested fields are preserved. Strings and slices are borrowed only
for the call. Bitmap characters `0`, `1`, and `x` clear, set, and preserve bits;
their permitted widths and register formats depend on the modifier type.
Firecracker validates architecture-specific fields, formats, and lifecycle
restrictions. The client does not silently drop fields or validate against its
own host CPU.

This sets a custom template, distinct from the static `cpu_template` setting in
machine configuration. PUT replaces the custom template rather than merging
individual modifiers. HTTP 204 returns `Result(void).success`; other statuses
return owned faults. Always call `deinit()`. Transport/allocation failures remain
Zig errors, and requests are never automatically retried.

Acceptance does not establish that the host can apply every requested feature
at boot, or that the guest can run with it. Firecracker v1.17.0 explicitly exports
`cpu-config: null` in [`VmmConfig::from`](https://github.com/firecracker-microvm/firecracker/blob/v1.17.0/src/vmm/src/resources.rs),
so `getVmConfiguration()` cannot confirm the installed custom template.

Protocol coverage includes x86_64 and aarch64 nested shapes, omitted versus empty
arrays, string escaping, HTTP faults, unexpected statuses, timeouts, disconnects,
oversized responses, and no retries. Live `configure-test` verification on
Firecracker v1.17.0 x86_64 confirmed HTTP 204 for a CPUID/KVM-capability template
and an empty replacement, and HTTP 400 for malformed capability input.
Guest feature application and aarch64 runtime behavior were not exercised.

### Configuring the boot source

On a connected, **pre-boot** instance:

```zig
var boot_source = try client.putGuestBootSource(.{
    .kernel_image_path = "/images/vmlinux",
    .boot_args = "console=ttyS0 reboot=k panic=1",
    .initrd_path = "/images/initramfs",
});
defer boot_source.deinit();

switch (boot_source) {
    .success => {},
    .fault => |fault| std.log.err("Boot source rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

`models.BootSourceRequest` requires `kernel_image_path`; `boot_args` and `initrd_path` default to null and are omitted from JSON. Explicit empty strings are preserved. All strings are borrowed for the call.

`PUT /boot-source` creates or replaces the boot source, not a partial update. Paths are interpreted by the **Firecracker process**, including its jailer/chroot filesystem namespace; the client does not open, upload, or rewrite the files. They must be readable by that process. Firecracker handles path, argument, and lifecycle validation and returns any rejection as an owned HTTP fault.

The return type is `Result(void)`: HTTP 204 succeeds, other statuses preserve the raw fault body, and transport/allocation failures return Zig errors. The existing timeout, size limit, and no-retry policy apply. Successful configuration is not proof of a bootable kernel/initramfs combination; this method does not send `InstanceStart`.

### Configuring a drive

On a connected, **pre-boot** instance:

```zig
var drive = try client.putGuestDrive(.{
    .drive_id = "rootfs",
    .is_root_device = true,
    .path_on_host = "/images/rootfs.ext4",
    .is_read_only = true,
});
defer drive.deinit();

switch (drive) {
    .success => {},
    .fault => |fault| std.log.err("Drive rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

`models.DriveRequest` requires `drive_id` and `is_root_device`. Virtio-block also requires `path_on_host` and `is_read_only`; vhost-user-block uses `socket` instead. Firecracker validates backend-specific combinations. Optional fields are `partuuid`, `cache_type`, `is_read_only`, `discard`, `path_on_host`, `rate_limiter`, `io_engine`, `blk_size`, `topology`, and `socket`. Cache and engine strings use the upstream values (`Unsafe`/`Writeback`, `Sync`/`Async`).

`RateLimiter` contains optional `bandwidth` and `ops` token buckets. Each `TokenBucket` requires `size` and `refill_time` (milliseconds), with optional `one_time_burst`. `BlockTopology` contains optional `physical_block_exp`, `alignment_offset`, `min_io_size`, and `opt_io_size`. Null fields are omitted recursively; explicit false, zero, empty strings, and empty nested objects are preserved. All supplied fields are encoded, not silently discarded.

`PUT /drives/{drive_id}` creates or replaces the identified drive, not a partial update. The same ID supplies the path and JSON body. It is percent-escaped as a single URL segment so delimiters cannot inject another route or query; escaping does not make an invalid Firecracker ID valid. Use ASCII letters, digits, and underscores for portable IDs. Invalid IDs and configurations remain server HTTP faults.

Strings are borrowed for the call. Image and socket paths belong to the **Firecracker process's filesystem namespace**; the client does not open, upload, or rewrite them. The return type is `Result(void)`: HTTP 204 succeeds, other statuses preserve owned raw faults, and transport/allocation errors remain Zig errors. Existing timeouts, response limits, and the no-retry policy apply. Configuration does not format a disk, check for a guest filesystem, or start the guest.

### Updating an existing drive

`patchGuestDrive(models.DriveUpdate)` sends `PATCH /drives/{drive_id}` to change
an existing drive's backing file, rate limiter, or both, including after boot.
It does not attach a new device.

```zig
var update = try client.patchGuestDrive(.{
    .drive_id = "data",
    .path_on_host = "/images/replacement.ext4",
    .rate_limiter = .{
        .bandwidth = .{ .size = 1048576, .refill_time = 100 },
    },
});
defer update.deinit();
switch (update) {
    .success => {},
    .fault => |fault| std.log.err("Drive update rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

Only `drive_id` is required. Omitted (`null`) fields are not serialized, including
nested limiter fields; explicit zero values and empty strings/objects are
preserved for Firecracker to interpret. A request containing only `drive_id` is
also supported, including vhost-user configuration-change notifications.
One ID supplies both the JSON body and the escaped URL segment.

Strings are borrowed during the call. Paths are in Firecracker's filesystem
namespace; this method does not open, resize, or modify host files. HTTP 204
returns success; all other statuses return owned raw faults. Transport errors,
timeouts, response-size limits, and the no-retry policy match drive creation.
A timeout does not establish whether the update was applied.

**Coordinate backing-file changes with the guest:** the drive must not be
mounted or subject to guest reads/writes during the update sequence. Pausing
alone does not eliminate queued guest I/O. Host-file changes and PATCH are not
atomic; when changing a file's size, PATCH is needed to notify Firecracker.
See the upstream [block-update safety requirements](https://github.com/firecracker-microvm/firecracker/blob/v1.17.0/docs/api_requests/patch-block.md).

### Configuring a network interface

On a connected, **pre-boot** instance, using a TAP device already prepared for Firecracker:

```zig
var network = try client.putGuestNetworkInterface(.{
    .iface_id = "eth0",
    .host_dev_name = "tap0",
    .guest_mac = "06:00:00:00:00:01",
    .mtu = 1500,
    .rx_rate_limiter = .{
        .bandwidth = .{ .size = 1048576, .refill_time = 100 },
    },
});
defer network.deinit();

switch (network) {
    .success => {},
    .fault => |fault| std.log.err("Network interface rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

`models.NetworkInterfaceRequest` requires `iface_id` and `host_dev_name`. Optional fields are `guest_mac`, `mtu`, `rx_rate_limiter`, and `tx_rate_limiter`. Both limiters reuse `RateLimiter` and `TokenBucket` above. Null fields are omitted recursively; explicit zero, empty strings, and empty limiter objects are preserved. The optional MTU is advertised to compatible guest drivers; Firecracker validates its range (68–65535), the MAC, rate limits, and device/lifecycle restrictions.

`PUT /network-interfaces/{iface_id}` creates or replaces a pre-boot interface, not a partial update. One ID supplies both the JSON body and the percent-escaped URL path segment. Escaping prevents route/query injection; invalid IDs still produce server faults.

The TAP must exist and be accessible in **Firecracker's network namespace**. The client does not create TAPs, configure host addresses, bridges, routing or NAT, assign guest IP addresses, or wait for guest connectivity. Request strings are borrowed for the call. HTTP 204 returns a successful `Result(void)`; every other status preserves an owned raw fault. Transport/allocation errors remain Zig errors. Existing timeout, response-size limit, and no-retry behavior apply. A timeout does not prove the write failed.

To include an existing TAP in the boot example:

```sh
zig build configure_and_start -- SOCKET EXECUTABLE KERNEL ROOTFS tap0 --disposable
```

The optional TAP argument configures interface ID `eth0` before starting the guest. Omitting it preserves disk-only boot. The guest still needs its own network configuration.

### Updating network rate limiters

`patchGuestNetworkInterface(models.NetworkInterfaceUpdate)` sends
`PATCH /network-interfaces/{iface_id}` to update an existing interface's RX
and/or TX rate limiters after boot. It does not attach interfaces or change
the TAP, MAC, MTU, or host networking.

```zig
var update = try client.patchGuestNetworkInterface(.{
    .iface_id = "eth0",
    .rx_rate_limiter = .{
        .bandwidth = .{ .size = 1048576, .refill_time = 1000 },
        .ops = .{ .size = 2000, .refill_time = 1000 },
    },
});
defer update.deinit();
switch (update) {
    .success => {},
    .fault => |fault| std.log.err("Network update rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

Only `iface_id` is required. RX and TX limiters are independently optional:
the example leaves TX unchanged. Null fields are omitted recursively, while
explicit zero values and empty limiter objects are preserved. To disable TX
limiting, provide both zero-sized buckets:

```zig
const disable_tx: fc.models.NetworkInterfaceUpdate = .{
    .iface_id = "eth0",
    .tx_rate_limiter = .{
        .bandwidth = .{ .size = 0, .refill_time = 0 },
        .ops = .{ .size = 0, .refill_time = 0 },
    },
};
// Pass disable_tx to client.patchGuestNetworkInterface and handle its Result.
```

The borrowed interface ID supplies both the JSON body and a percent-escaped
URL segment. Firecracker validates IDs, limiter values, and device/lifecycle
restrictions. HTTP 204 returns success; other statuses preserve owned raw
faults. Transport/allocation errors remain Zig errors. Existing timeouts,
response-size limits, and no-retry behavior apply; a timeout does not prove
the update failed.

See the pinned [network update semantics](https://github.com/firecracker-microvm/firecracker/blob/v1.17.0/docs/api_requests/patch-network-interface.md).

### Configuring a balloon device

`putBalloon(models.BalloonConfiguration)` sends `PUT /balloon` to create or
replace the balloon device before VM startup:

```zig
var balloon = try client.putBalloon(.{
    .amount_mib = 64,
    .deflate_on_oom = true,
    .stats_polling_interval_s = 5,
});
defer balloon.deinit();
switch (balloon) {
    .success => {},
    .fault => |fault| {
        std.log.err("Balloon HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.ConfigurationRejected;
    },
}
```

`amount_mib` (target size in MiB) and `deflate_on_oom` are required.
`stats_polling_interval_s`, `free_page_hinting`, and `free_page_reporting` are
optional. Null fields are omitted; explicit zero and false are sent unchanged.
An omitted statistics interval defaults to zero (statistics disabled).
This is replacement configuration, not a partial size update. Firecracker
validates values, device compatibility, and lifecycle; PUT fails after startup.

HTTP 204 returns `Result(void).success`; other statuses return owned raw faults.
Transport/allocation failures remain Zig errors. Existing request deadlines,
response-size limits, and no-retry behavior apply. A timeout does not prove the
configuration failed. This method does not start hinting or read statistics.

Verification covers omitted versus explicit zero/false fields, HTTP faults
surviving client destruction, unexpected statuses, timeout, disconnect,
oversized faults, and no retries. A disposable Firecracker v1.17.0 instance
accepted full, explicit-zero, and minimal configurations through the client;
direct `GET /balloon` readback confirmed all five fields after each replacement.

### Reading balloon configuration

```zig
var balloon = try client.getBalloon();
defer balloon.deinit();
switch (balloon) {
    .success => |config| {
        std.log.info("Balloon target: {d} MiB; deflate on OOM: {}", .{
            config.amount_mib, config.deflate_on_oom,
        });
    },
    .fault => |fault| {
        std.log.err("Balloon HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.ConfigurationReadRejected;
    },
}
```

Returns `Result(models.BalloonConfiguration)` from a live `GET /balloon`, not
cached configuration or balloon statistics. Only HTTP 200 is decoded.
Other statuses, including an unconfigured device's rejection, preserve the raw
body and status in an owned fault. Transport, allocation, and JSON decoding
failures remain Zig errors.

The success value contains only numbers and booleans and may be copied or
retained after client/result destruction. Missing or null optional fields remain
null; explicit zero and false remain distinct. Unknown response fields are
ignored. Always call `deinit()` on the enclosing result to release possible
fault storage; `Result` also supports value structs without a destructor.

Protocol coverage includes optional-field absence/null/zero/false, required
fields, malformed responses, HTTP faults, unexpected statuses, timeout,
disconnect, and response-size limits. Live Firecracker v1.17.0 verification
used `getBalloon()` after full, zero, and minimal replacements and checked all
five fields after destroying the client.

### Changing balloon size

```zig
var resized = try client.patchBalloon(.{ .amount_mib = 32 });
defer resized.deinit();
switch (resized) {
    .success => {},
    .fault => |fault| {
        std.log.err("Balloon resize HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.BalloonResizeRejected;
    },
}
```

`models.BalloonUpdate` requires only `amount_mib`, the new target size in MiB.
Zero requests full deflation. The request does not alter deflate-on-OOM,
statistics polling, hinting, or reporting settings, and cannot create a device.
Configure the balloon with `putBalloon()` before boot.

**Firecracker v1.17.0 rejects PATCH before VM startup**, despite the pinned
OpenAPI description claiming pre-start support. Use `putBalloon()` to change
pre-boot configuration; use `patchBalloon()` after startup. The client leaves
value, device, and lifecycle validation to Firecracker and preserves rejections.

Only HTTP 204 returns success; other statuses return owned raw HTTP faults.
Success acknowledges the target change, not completed guest memory reclamation.
Transport/allocation failures remain Zig errors. Existing deadlines and response
limits apply; no automatic retries. A timeout does not prove the resize failed.

Protocol verification covers nonzero and zero targets, negative values reaching
server validation, owned faults after client destruction, unexpected statuses,
timeouts, disconnects, oversized faults, and no retries. A disposable live
v1.17.0 process received `PATCH /balloon` with `{"amount_mib":32}` and returned
the pre-start HTTP 400 restriction. Post-start resizing and guest reclamation
were not exercised in this verification.

### Reading balloon statistics

```zig
var statistics = try client.getBalloonStatistics();
defer statistics.deinit();
switch (statistics) {
    .success => |stats| {
        std.log.info("Balloon target: {d} MiB; actual: {d} MiB", .{
            stats.target_mib, stats.actual_mib,
        });
        if (stats.free_memory) |bytes| {
            std.log.info("Guest free memory: {d} bytes", .{bytes});
        }
    },
    .fault => |fault| {
        std.log.err("Balloon statistics HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.StatisticsReadRejected;
    },
}
```

Returns `Result(models.BalloonStatistics)`. Required fields are `target_pages`,
`actual_pages`, `target_mib`, and `actual_mib`. Optional guest counters cover
swap, page faults, free/total/available memory, disk caches, hugetlb allocations
and failures, OOM kills, allocation stalls, and asynchronous/direct scans and
reclaims. Swap, free/total/available memory, and disk-cache counters use bytes.
Values use `i64`, matching the pinned wire models, without conversion through
floating point.

Missing or null optional counters remain null, distinct from zero; unknown
response fields are ignored. The scalar success value can be copied and retained
after destroying the client or result. Always deinitialize the enclosing result
to release possible fault storage.

Enable statistics before boot with a nonzero `stats_polling_interval_s` in
`putBalloon()`, then start the VM. This GET does not enable polling or wait for
a fresh guest sample. Firecracker v1.17.0 rejects this operation before startup,
even when polling is configured. The schema also documents HTTP 400 when
statistics were not enabled.

Only HTTP 200 is decoded; other statuses preserve owned raw faults.
Transport, allocation, and JSON decoding failures remain Zig errors. Existing
deadlines, response-size limits, and no-retry behavior apply.

Protocol verification covers all 20 fields, distinct target/actual values,
integers above floating-point exact precision, absent/null/zero counters,
missing required fields, malformed responses, owned faults after client
destruction, unexpected statuses, timeout, disconnect, and oversized responses.
A live v1.17.0 process received the client's statistics GET and returned the
pre-start HTTP 400 restriction. Post-start guest statistics were not exercised.

### Changing the statistics polling interval

```zig
var updated = try client.patchBalloonStatistics(.{
    .stats_polling_interval_s = 7,
});
defer updated.deinit();
switch (updated) {
    .success => {},
    .fault => |fault| {
        std.log.err("Balloon interval HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.StatisticsIntervalRejected;
    },
}
```

`models.BalloonStatisticsUpdate` requires `stats_polling_interval_s`, in seconds.
Only that field is sent; the balloon size and other settings are unchanged.
The pinned contract schedules the first statistics update immediately.
HTTP success does not mean a fresh guest sample is already available.

Configure statistics with a nonzero interval in `putBalloon()` before boot,
then use this PATCH to change the interval after startup. Statistics cannot be
turned on or off after boot; zero is not a supported way to disable active
polling. The client sends values unchanged, including zero and negative values,
and leaves value, device, and lifecycle validation to Firecracker.

Live Firecracker v1.17.0 rejects this PATCH before startup, contrary to the
endpoint's pinned OpenAPI description. For pre-boot changes, replace the balloon
configuration with `putBalloon()`.

Only HTTP 204 returns `Result(void).success`; other statuses preserve owned raw
HTTP faults. Transport/allocation failures remain Zig errors. Existing deadlines,
response-size limits, and no-retry behavior apply; a timeout does not establish
whether the interval changed.

Protocol coverage verifies the exact PATCH path and payload, positive/zero/
negative values, faults surviving client destruction, unexpected statuses,
timeouts, disconnects, oversized faults, and no retries. Live v1.17.0 received
`{"stats_polling_interval_s":7}` at `/balloon/statistics` and returned the pre-start
HTTP 400 restriction. Post-start polling cadence was not exercised.

### Free-page hinting

Enable `.free_page_hinting = true` in `putBalloon()` before boot. Firecracker
v1.17.0 labels this feature development preview. The guest must support it;
enabling free-page reporting alone does not enable hinting.

| Client method | HTTP endpoint | Result |
| --- | --- | --- |
| `startBalloonHinting(request)` | `PATCH /balloon/hinting/start` | `Result(void)` |
| `stopBalloonHinting()` | `PATCH /balloon/hinting/stop` | `Result(void)` |
| `getBalloonHintingStatus()` | `GET /balloon/hinting/status` | `Result(models.BalloonHintingStatus)` |

```zig
var started = try client.startBalloonHinting(.{ .acknowledge_on_stop = true });
defer started.deinit();
switch (started) {
    .success => {},
    .fault => |fault| {
        std.log.err("Hinting start HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.HintingStartRejected;
    },
}

var status = try client.getBalloonHintingStatus();
defer status.deinit();
switch (status) {
    .success => |value| {
        std.log.info("Hinting host command: {d}; guest command: {?d}", .{
            value.host_cmd, value.guest_cmd,
        });
    },
    .fault => |fault| {
        std.log.err("Hinting status HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.HintingStatusRejected;
    },
}

// When the application decides to stop the run:
var stopped = try client.stopBalloonHinting();
defer stopped.deinit();
switch (stopped) {
    .success => {},
    .fault => |fault| {
        std.log.err("Hinting stop HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.HintingStopRejected;
    },
}
```

`BalloonHintingStartRequest.acknowledge_on_stop` controls whether Firecracker
automatically acknowledges the guest's done command. Passing `.{}`
omits that field and sends `{}`, leaving the server default intact. Explicit
true and false are preserved. Stop sends an empty body, as supported by the
[v1.17 request parser](https://github.com/firecracker-microvm/firecracker/blob/v1.17.0/src/firecracker/src/api_server/request/balloon.rs).

Status requires `host_cmd`; optional `guest_cmd` preserves absence/null separately
from zero. Both are numeric commands, not a derived running/completed enum.
Unknown response fields are ignored. The scalar status may outlive the client
and result; always deinitialize the result to release possible fault storage.

Start/stop accept only HTTP 204 as success; status decodes only HTTP 200.
Other statuses preserve owned raw faults. Transport/allocation/decoding failures
remain Zig errors. Existing deadlines and response-size limits apply. No method
retries or polls for guest completion. A timeout can follow an accepted command.

Live Firecracker v1.17.0 rejected all three endpoints before VM startup even
with hinting configured. Use them after startup; Firecracker validates device
availability and lifecycle. Protocol coverage checks start's omitted/true/false
option, stop's empty body, status absence/null/zero and distinct commands,
malformed responses, owned faults, unexpected statuses, timeout, disconnect,
oversized responses, and no retries. Live request delivery and pre-start
rejections were observed; post-start guest hinting was not exercised.

### Hotpluggable memory

Hotpluggable memory uses virtio-mem and is a separate pool from the VM's boot
memory. Configure its capacity before boot, then request target sizes after
startup. The guest must support `CONFIG_VIRTIO_MEM`; host acceptance does not
guarantee guest progress or successful unplugging.

| Client method | Request / result |
| --- | --- |
| `putMemoryHotplug(request)` | `MemoryHotplugConfiguration` → `Result(void)` |
| `patchMemoryHotplug(request)` | `MemoryHotplugUpdate` → `Result(void)` |
| `getMemoryHotplug()` | `Result(MemoryHotplugStatus)` |

Configure before starting the VM:

```zig
var configured = try client.putMemoryHotplug(.{
    .total_size_mib = 1024,
    .slot_size_mib = 128,
    .block_size_mib = 2,
});
defer configured.deinit();
switch (configured) {
    .success => {},
    .fault => |fault| {
        std.log.err("Memory hotplug configuration HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.MemoryHotplugConfigurationRejected;
    },
}
```

After the application has started the VM, request memory:

```zig
var resized = try client.patchMemoryHotplug(.{ .requested_size_mib = 256 });
defer resized.deinit();
switch (resized) {
    .success => {},
    .fault => |fault| {
        std.log.err("Memory hotplug resize HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.MemoryHotplugResizeRejected;
    },
}

var status = try client.getMemoryHotplug();
defer status.deinit();
switch (status) {
    .success => |value| {
        std.log.info("Memory hotplug requested: {?d} MiB; plugged: {?d} MiB", .{
            value.requested_size_mib, value.plugged_size_mib,
        });
    },
    .fault => |fault| {
        std.log.err("Memory hotplug status HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.MemoryHotplugStatusRejected;
    },
}
```

All sizes are MiB. Firecracker requires `total_size_mib` for configuration,
with default slot/block sizes of 128/2 MiB. Capacity must be a multiple of the
slot size. Blocks must be powers of two and at least 2 MiB; slots must be at
least 128 MiB and multiples of the block size. The resize target must be a
multiple of the block size and not exceed capacity. Zero requests unplugging
all hotpluggable memory, not boot memory.

Public request fields remain optional to match the pinned schema and existing
full-VM configuration model. Null fields are omitted, not replaced with client
defaults; explicit zero and negative values reach server validation. Supply
`total_size_mib` for PUT and `requested_size_mib` for PATCH. PUT configures
capacity/granularity; PATCH changes only the target.

GET exposes `total_size_mib`, `slot_size_mib`, `block_size_mib`,
`plugged_size_mib`, and `requested_size_mib`. Missing/null fields remain null;
explicit zero is preserved and unknown fields are ignored. Scalar status data
may outlive the client/result. Requested and plugged sizes can differ while the
guest works; these methods neither poll nor wait for convergence.

PUT/PATCH accept only HTTP 204; GET decodes only HTTP 200. Other statuses return
owned raw faults. Transport/allocation/decoding failures remain Zig errors.
Always deinitialize results. Existing deadlines, response-size limits, and
no-retry behavior apply; a timed-out resize may already have changed the target.

Live Firecracker v1.17.0 accepted the 1024/128/2 MiB configuration through the
client, and `/vm/config` confirmed it. Both GET and PATCH on `/hotplug/memory`
were rejected before startup; use `getVmConfiguration().memory_hotplug` to
inspect pre-boot configuration instead. This differs from the upstream guide's
claim that status can be queried at any time. Post-start resizing and guest
convergence were not exercised.

Protocol verification covers minimal/full/empty requests, zero and negative
values, distinct requested/plugged sizes, absent/null/zero status fields,
malformed JSON/types, owned faults after client destruction, unexpected
statuses, timeout, disconnect, oversized responses, and no retries.
See the [v1.17 virtio-mem guide](https://github.com/firecracker-microvm/firecracker/blob/v1.17.0/docs/memory-hotplug.md)
for guest kernel requirements, memory onlining, and hot-removal constraints.

### Configuring MMDS

`putMmdsConfiguration()` sends `PUT /mmds/config` before boot, reusing
`models.MmdsConfiguration` from `getVmConfiguration()`.

```zig
var configured = try client.putMmdsConfiguration(.{
    .network_interfaces = &.{"eth0"},
    .version = "V2",
    .ipv4_address = "169.254.169.254",
    .imds_compat = false,
});
defer configured.deinit();
switch (configured) {
    .success => {},
    .fault => |fault| std.debug.print("MMDS configuration failed: HTTP {d}: {s}\n", .{ fault.status, fault.body }),
}
```

Configure the referenced network interfaces first. Firecracker v1.17.0 rejects
empty interface lists and unknown IDs. Optional `version`, `ipv4_address`, and
`imds_compat` fields are omitted when null; explicit false and empty values are
sent unchanged for Firecracker to validate. The pinned schema lists V1/V2,
a link-local IPv4 address, and EC2 IMDS compatibility. Strings and interface
slices are borrowed only during the call.

Only HTTP 204 is success; other statuses return owned raw faults. Transport and
allocation failures remain Zig errors. Existing deadlines and response limits
apply, with no automatic retries. This configures the metadata service, not
metadata contents, host networking, or guest readiness.

Live verification on Firecracker v1.17.0 used a disposable TAP in an isolated
user/network namespace: V2, a custom address, and IMDS compatibility were
confirmed through `getVmConfiguration()`. A subsequent request with omitted
options and explicit `imds_compat = false` succeeded and read back false.
Unknown and empty interface lists returned HTTP 400. Guest metadata access
was not exercised.

### Reading and updating metadata

`getMmds()`, `putMmds(json)`, and `patchMmds(json)` access the `/mmds`
data store, independently of `putMmdsConfiguration()`.

```zig
var replaced = try client.putMmds(
    \\{"service":{"name":"worker","obsolete":true},"ports":[8080]}
);
defer replaced.deinit();
switch (replaced) {
    .success => {},
    .fault => |fault| {
        std.debug.print("MMDS replacement: HTTP {d}: {s}\n", .{ fault.status, fault.body });
        return;
    },
}

var patched = try client.patchMmds(
    \\{"service":{"obsolete":null,"ready":true}}
);
defer patched.deinit();
switch (patched) {
    .success => {},
    .fault => |fault| {
        std.debug.print("MMDS patch: HTTP {d}: {s}\n", .{ fault.status, fault.body });
        return;
    },
}

var metadata = try client.getMmds();
defer metadata.deinit();
switch (metadata) {
    .success => |contents| {
        const json = try std.json.Stringify.valueAlloc(allocator, contents.value, .{});
        defer allocator.free(json);
        std.debug.print("{s}\n", .{json});
    },
    .fault => |fault| std.debug.print("MMDS read: HTTP {d}: {s}\n", .{ fault.status, fault.body }),
}
```

Writes borrow JSON text for the call and send it unchanged: no local parsing,
re-encoding, or merge. Firecracker validates the document. PUT replaces the
entire store; PATCH merges objects recursively, removes members whose patch
value is null, and replaces arrays rather than concatenating them. Initialize
the store with PUT before PATCH; v1.17.0 returns HTTP 400 for an uninitialized
patch. Neither operation configures network interfaces or enables guest access.

GET accepts HTTP 200 and returns `models.MmdsContents`, an owned
`std.json.Value` tree. Keys, strings, arrays, objects, and number lexemes remain
valid across subsequent requests and client destruction, until result
`deinit()`. Its allocator must remain alive. Numbers use `.number_string`
to preserve precision; convert explicitly when numeric computation is needed.
Do not deinitialize nested values separately.

PUT/PATCH accept only HTTP 204. Other statuses, including validation failures,
are owned raw HTTP faults. Transport, allocation, and GET JSON decoding failures
are Zig errors. Existing deadlines and response-size limits apply. No automatic
retries: a failed connection or timeout can follow an applied write.

Live Firecracker v1.17.0 verification covered replacement, recursive merge and
null deletion, array replacement, explicit null storage, escaped strings, a
64-bit unsigned integer without precision loss, and results retained across
later requests and client destruction. Invalid JSON and an uninitialized PATCH
returned HTTP 400. Guest-side metadata retrieval was not exercised.

### Configuring logs and metrics

Configure destinations before starting the guest:

```zig
var logger = try client.putLogger(.{
    .log_path = "/logs/firecracker.log",
    .level = "Debug",
    .show_level = true,
    .show_log_origin = true,
});
defer logger.deinit();
switch (logger) {
    .success => {},
    .fault => |fault| {
        std.log.err("Logger HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.LoggerRejected;
    },
}

var properties: std.json.ArrayHashMap([]const u8) = .{};
defer properties.deinit(allocator);
try properties.map.put(allocator, "service", "worker");
var metrics = try client.putMetrics(.{
    .metrics_path = "/logs/metrics.jsonl",
    .emit_id = true,
    .properties = properties,
});
defer metrics.deinit();
switch (metrics) {
    .success => {},
    .fault => |fault| {
        std.log.err("Metrics HTTP {d}: {s}", .{ fault.status, fault.body });
        return error.MetricsRejected;
    },
}
```

`LoggerRequest` has optional `log_path`, `level`, `show_level`, `show_log_origin`, and `module` fields. Levels are `Error`, `Warning`, `Info`, `Debug`, `Trace`, and `Off` (case-insensitive); `module` filters by module path. Null fields are omitted so Firecracker applies its behavior/defaults. Explicit false and empty strings are sent unchanged; Firecracker validates values.

`MetricsRequest` requires `metrics_path`; `emit_id` and `properties` are optional. Properties are a string-to-string JSON map, not arbitrary JSON. The caller owns the map and its strings; the client borrows them only during the call. Null omits properties, while an empty map sends `{}`. Firecracker rejects repeated metrics initialization.

Both methods return `Result(void)`: HTTP 204 succeeds, other statuses preserve owned raw faults, and transport/allocation failures remain Zig errors. Paths refer to files or named pipes in **Firecracker's filesystem namespace**. Prepare destinations and permissions there; for FIFOs, arrange a reader before configuration to avoid blocking the server. The client does not create, read, rotate, or ship output files.

After starting the VM, request an immediate flush:

```zig
var flushed = try client.flushMetrics();
defer flushed.deinit();
switch (flushed) {
    .success => {},
    .fault => |fault| std.log.err("Metrics flush HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

`flushMetrics()` sends `PUT /actions` with `{"action_type":"FlushMetrics"}`. Firecracker v1.17.0 rejects this action before VM start. Success acknowledges the flush operation; metrics are written to the configured destination, not returned in the HTTP response. Existing request deadlines, response limits, and no-retry behavior apply to all three methods. A timeout does not establish whether configuration or flushing completed.

The `observability` example has separate configuration and post-start flush commands:

```sh
zig build observability -- SOCKET EXECUTABLE LOG_PATH METRICS_PATH --disposable
# Configure and start the guest, then:
zig build observability -- SOCKET EXECUTABLE --flush --disposable
```

It enables debug logging with level/origin fields and metrics with the instance ID and `{"source":"firecrackerz"}` properties. Both commands mutate the server and require `--disposable`. They do not start or stop Firecracker.

### Starting the instance

After configuring the machine, boot source, and any required devices:

```zig
var started = try client.startInstance();
defer started.deinit();

switch (started) {
    .success => std.log.info("Instance start accepted", .{}),
    .fault => |fault| std.log.err("Start rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

This sends `PUT /actions` with `{"action_type":"InstanceStart"}` and returns `Result(void)`. HTTP 204 succeeds without JSON decoding; every other status preserves an owned raw fault. Transport/allocation failures remain Zig errors. Firecracker validates configuration and lifecycle: a successful start is allowed only once, and missing boot configuration or a repeated start is rejected. The client does not cache a running flag or suppress subsequent requests.

**There are no automatic retries.** A timeout or disconnect after sending the action does not establish whether the VM started. Call `client.getInstanceInfo()` to inspect live state before deciding what to do; `client.info()` is cached connection metadata, not VM state. A read is a snapshot, not a guarantee against concurrent lifecycle changes. If the read fails or the outcome remains ambiguous, do not assume startup failed and blindly retry. Existing request timeouts and response limits apply.

Success means Firecracker accepted startup, not that the guest reached userspace or that an application is ready. A disk-backed guest needs a bootable root filesystem; an initramfs-only guest need not have a root drive. Destroying the client closes client resources; it does not stop the VM or terminate Firecracker.

### Pausing and resuming

Use `pauseInstance()` to suspend a booted microVM and `resumeInstance()` to resume it. Resume does not boot an unstarted VM and pause does not shut down the guest or terminate Firecracker.

```zig
var paused = try client.pauseInstance();
defer paused.deinit();
switch (paused) {
    .success => {},
    .fault => |fault| {
        std.log.err("Pause rejected: HTTP {d}: {s}", .{ fault.status, fault.body });
        return;
    },
}

// Perform work requiring the VM to remain paused, then resume.
var resumed = try client.resumeInstance();
defer resumed.deinit();
switch (resumed) {
    .success => {},
    .fault => |fault| std.log.err("Resume rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

Both methods send `PATCH /vm`: pause uses `{"state":"Paused"}`, resume uses `{"state":"Resumed"}` (not `"Running"`). They return `Result(void)`: only HTTP 204 succeeds; every other status preserves an owned raw fault body. Transport/allocation failures remain Zig errors. Firecracker validates lifecycle state, including requests before boot; the client neither caches state nor suppresses repeated requests.

Requests use the configured timeout and response-size limit and are never automatically retried. After a timeout or disconnect, the state change may already have completed. Inspect `getInstanceInfo()` before deciding what to do; it reports `Paused` or `Running`, but cannot prevent concurrent lifecycle changes.

### Creating full or differential snapshots

`createSnapshot(models.SnapshotCreateRequest)` sends `PUT /snapshot/create` and
returns `Result(void)`. Pause the booted VM with `pauseInstance()` and check its
result before creating a snapshot. The client does not pause or resume implicitly.

```zig
// The VM is already paused.
var snapshot = try client.createSnapshot(.{
    .mem_file_path = "/snapshots/guest.mem",
    .snapshot_path = "/snapshots/guest.state",
    .snapshot_type = "Full", // Use "Diff" for a differential snapshot.
});
defer snapshot.deinit();
switch (snapshot) {
    .success => {},
    .fault => |fault| {
        std.log.err("Snapshot rejected: HTTP {d}: {s}", .{ fault.status, fault.body });
        return;
    },
}
```

Both paths are required, borrowed during the call, and resolved in Firecracker's
filesystem namespace. The client does not open them or create directories.
Omitting `snapshot_type` requests the server's default full snapshot. For `"Diff"`,
enable `track_dirty_pages = true` in machine configuration before boot. Firecracker
validates snapshot type, lifecycle, paths, and dirty-page tracking; invalid requests
are returned as HTTP faults rather than checked against cached client state.

`sync_snapshot_files` is optional and defaults to true on the server. Explicit
false avoids waiting for snapshot state/memory file writeback, sacrificing
durability across host crashes; block-device backing files are still synced.
Only HTTP 204 succeeds; other statuses retain their owned raw fault body.

Snapshot creation uses `request_timeout_ms` from connection options; choose a
timeout appropriate for guest memory size and storage speed. There are no retries:
a timeout or disconnect may leave completed or partially written files. Live VM
state alone cannot establish snapshot completion. Resume explicitly when appropriate.
Management of differential memory files remains an application responsibility.

Local Unix-socket protocol scenarios exercise full and differential requests,
omitted options, escaped paths, explicit sync true/false, HTTP faults, unexpected
statuses, timeouts, disconnects, and absence of automatic retries.

### Restoring snapshots

`loadSnapshot(models.SnapshotLoadRequest)` sends `PUT /snapshot/load`. Connect to
a **fresh Firecracker process**, before configuring any resource other than
logger and metrics. Do not configure a boot source, drives, or machine settings
first: the snapshot supplies the VM configuration.

```zig
var restored = try client.loadSnapshot(.{
    .snapshot_path = "/snapshots/guest.state",
    .mem_backend = .{
        .backend_type = "File",
        .backend_path = "/snapshots/guest.mem",
    },
    .track_dirty_pages = true,
    .resume_vm = false,
});
defer restored.deinit();
switch (restored) {
    .success => {},
    .fault => |fault| {
        std.log.err("Restore rejected: HTTP {d}: {s}", .{ fault.status, fault.body });
        return;
    },
}
// The restored VM is paused. Call resumeInstance() when ready.
```

Set `resume_vm = true` to resume as part of loading; omitted or false leaves the
VM paused. Success does not establish guest/application readiness.

All request strings and slices are borrowed during the call. Paths belong to
Firecracker's filesystem namespace, not the client's. Supply exactly one memory
source: `mem_backend` (recommended) or the upstream-deprecated `mem_file_path`.
The backend type is `"File"` for a memory image or `"Uffd"` for a Unix socket
served by an external userfaultfd page-fault handler. The client starts neither
the handler nor Firecracker.

Optional fields are omitted when null; explicit false and empty override lists
are preserved:

| Field | Purpose |
| --- | --- |
| `track_dirty_pages` | Enable dirty-page tracking for subsequent differential snapshots |
| `enable_diff_snapshots` | Upstream-deprecated dirty-tracking option; prefer `track_dirty_pages` |
| `network_overrides` | Slice of `{ .iface_id, .host_dev_name }` entries selecting existing host TAPs |
| `vsock_override` | `{ .uds_path }` to replace the backing vsock socket path |
| `clock_realtime` | x86_64 wall-clock advancement during restore |
| `huge_pages` | `"Snapshot"` (server default), `"None"`, `"Transparent"`, or `"2M"`; explicit 2M pages require UFFD |

Firecracker validates memory-source combinations, snapshot compatibility,
architecture-specific options, and lifecycle state. Only HTTP 204 succeeds;
other statuses return an owned fault body, while transport/allocation failures
remain Zig errors. Requests use the connection's `request_timeout_ms` and are
never retried. A timeout or disconnect can follow a completed restore, including
a running guest when `resume_vm` is true; do not blindly retry.

For differential snapshots, prepare the complete memory image by applying the
required differential layers to their base before a file-backed restore. This
binding does not merge layers, prepare backing disks, or create TAP devices.
Restore requires compatible snapshot state and its associated memory/resources.

Local Unix-socket scenarios cover file and UFFD requests, legacy memory paths,
device overrides, omitted and explicit false options, empty lists, preserved
server faults for invalid memory-source combinations, unexpected statuses,
timeouts, disconnects, response limits, and absence of retries. These are protocol
checks, not a real guest restore or UFFD-handler integration test.

### Sending Ctrl+Alt+Delete

```zig
var action = try client.sendCtrlAltDel();
defer action.deinit();
switch (action) {
    .success => {},
    .fault => |fault| std.log.err("Ctrl+Alt+Del rejected: HTTP {d}: {s}", .{
        fault.status, fault.body,
    }),
}
```

This sends `PUT /actions` with `{"action_type":"SendCtrlAltDel"}` and returns `Result(void)`. Only HTTP 204 succeeds; other statuses preserve an owned raw fault body, and transport/allocation failures remain Zig errors. Firecracker validates lifecycle state; the client does not cache state or suppress requests.

For the supported **v1.17.0** runtime, this action is **Intel/AMD only**, as documented in the [pinned upstream action contract](https://github.com/firecracker-microvm/firecracker/blob/v1.17.0/docs/api_requests/actions.md). The guest needs keyboard/i8042 support (`CONFIG_SERIO_I8042` and `CONFIG_KEYBOARD_ATKBD` on Linux) and must handle the key sequence. Guests commonly shut down and reset; Firecracker exits on CPU reset. Success acknowledges injection, **not shutdown completion**. This is not a universal stop operation and does not supervise or terminate the Firecracker process.

Existing timeouts and response limits apply. There are no automatic retries: after a timeout or disconnect the sequence may already have been delivered. `getInstanceInfo()` cannot prove whether the guest consumed the sequence; do not blindly retry an ambiguous outcome.

Verification covers HTTP 204, owned HTTP faults, unexpected statuses, timeout, disconnect, oversized responses, and no automatic retries over a local Unix socket. A live disposable v1.17.0 process also rejected the action before boot with HTTP 400, with its fault preserved by the client. Guest shutdown behavior has not been verified for this method.


### Connection behavior

1. Resolve the executable to an absolute path and check executability.
2. Execute it directly with `--version`, without a shell. Bound combined stdout/stderr to 4096 bytes and enforce a deadline through child exit. Clean up and reap the child on failures.
3. Parse the Firecracker version banner and require an explicitly registered release.
4. Send `GET /version` over the supplied Unix-domain socket using Dusty.
5. Require HTTP 200, decode the version, and compare it with the executable's version.
6. Return an owning `Result(Client)`.

Semantic-version build metadata is validated but ignored for compatibility and equality. Prereleases, development versions, and unknown patch releases are rejected. A matching version is not authentication of the server or proof of executable identity; trust the socket and executable paths.

The HTTP request defaults to a 3000 ms timeout and a 64 KiB response-body limit. Discovery has its own 3000 ms timeout. Zero timeouts are invalid. Redirects, automatic retries, decompression, and idle connection pooling are disabled. The handshake connection closes after its response is consumed; the client retains transport configuration, not a permanent live socket. `info()` returns cached handshake metadata, not a live health check.

### Errors and ownership

- Ordinary Zig errors represent local failures: discovery, unsupported versions, allocation, timeout, transport, malformed responses, and `VersionMismatch`.
- Discovery distinguishes `ExecutableNotFound`, `NotExecutable`, `InvalidExecutablePath`, `ProcessFailed`, `InvalidVersionOutput`, `OutputTooLong`, `UnsupportedVersion`, and `PrereleaseVersion`.
- Responses outside the operation's expected status (200 for reads, 204 for configuration writes and instance start) return `.fault` with owned raw body and numeric status. Oversized or unreadable fault bodies remain transport errors.
- `Result(Client).deinit()` releases either its client or its HTTP fault. Do not also deinitialize the contained client.
- Clients and results are owning values: do not copy them or deinitialize them twice.
- The allocator and I/O runtime must outlive the client. Metadata strings are borrowed until client destruction.
- Input paths are copied during construction. Failed construction releases partially acquired resources.
- Concurrent use is not supported.

## Development and verification

| Command | Purpose |
| --- | --- |
| `zig build` / `zig build check` | Compile library tests, protocol and configuration runners, and examples |
| `zig build test` | Run version and discovery unit tests |
| `zig build protocol` | Run local Unix-socket connection, live instance-information, configuration, instance-start, and subprocess discovery scenarios |
| `zig build discovery-test` | Run the same combined protocol scenarios |
| `zig build examples` | Build and install inspection, configure-and-start, and observability examples |
| `zig build inspect -- SOCKET EXECUTABLE` | Print verified metadata, live instance information, and current machine configuration |
| `zig build integration -- SOCKET EXECUTABLE` | Run the inspection example against a disposable real instance |
| `zig build configure-test -- SOCKET EXECUTABLE --disposable` | Mutate a disposable pre-boot instance; verify readback, optional-field reset, and invalid-update rejection |
| `zig build boot-source-test -- SOCKET EXECUTABLE KERNEL INITRD --disposable` | Configure a disposable pre-boot instance; exercise optional arguments, replacement, and invalid paths without starting a guest |
| `zig build drive-test -- SOCKET EXECUTABLE IMAGE --disposable` | Configure a disposable root drive; exercise replacement, invalid paths, and invalid configuration without starting a guest |
| `zig build configure_and_start -- SOCKET EXECUTABLE KERNEL ROOTFS [TAP] --disposable` | Configure 1 vCPU, 128 MiB, kernel, read-only root drive, and optional existing TAP, then start a disposable guest |
| `zig build observability -- SOCKET EXECUTABLE LOG_PATH METRICS_PATH --disposable` | Configure logging and metrics on a disposable instance |
| `zig build observability -- SOCKET EXECUTABLE --flush --disposable` | Flush metrics after starting the disposable VM |
| `zig build codegen` | Regenerate version-specific wire models |

Protocol scenarios cover explicit and PATH discovery, supported versions, content-length and chunked responses, version mismatch, preserved HTTP faults, malformed JSON, socket absence, oversized responses, request and discovery timeouts, malformed executable output, process failure, and unsupported releases.

Machine configuration scenarios additionally cover a fresh connection after the handshake, repeated reads with retained results, strings and faults surviving client destruction, absent optional fields, missing required fields, and server disconnects.

Instance-information scenarios cover state changes across repeated reads with retained results, all three documented states, unfamiliar state strings and extra JSON fields, escaped strings surviving client destruction, faults surviving client destruction, each required field missing/null, incorrect field types, malformed JSON, unexpected statuses, timeouts, disconnects, and response-size limits.

Live instance-information verification on v1.17.0 used the inspection example to read `Not started`, then `Running` after the configure-and-start example, and `Paused` after a direct `PATCH /vm` probe. All reads returned the configured instance ID, VMM version, and application name. Pausing was test setup through the direct API; the client does not yet expose a pause method.

PUT scenarios verify omitted versus explicit optional fields, JSON content type and request body, empty HTTP 204 success, unexpected statuses, owned fault bodies, timeouts, disconnects, and oversized fault responses.

Boot-source scenarios additionally verify JSON escaping for paths and arguments, omitted optional fields versus explicit empty arguments, and the `/boot-source` endpoint. Live verification used `/boot/vmlinuz-linux` and the readable `/boot/amd-ucode.img` early initramfs; the root-only `/boot/initramfs-linux.img` produced a preserved HTTP 400 permission fault. This verifies API configuration, not guest boot or a complete guest userspace.

Drive scenarios additionally cover all optional and nested fields, omitted versus explicit zero/false/empty values, socket-only request encoding, and escaped/empty IDs. Live verification on v1.17.0 used a disposable 4 MiB regular backing file: root-drive creation and replacement succeeded, an invalid image child path and negative block size returned owned HTTP 400 faults, and `/vm/config` readback confirmed the restored root drive. This proves configuration, not a bootable filesystem. Vhost-user request encoding is covered locally; a live vhost-user backend was not exercised.

Network-interface protocol scenarios cover omitted fields, independent RX/TX limiters, nested zero values, explicit empty values, MAC/MTU encoding, escaped IDs, long IDs exceeding the stack path buffer, owned faults surviving client destruction, unexpected statuses, timeouts, disconnects, oversized responses, and absence of automatic retries. Live verification on v1.17.0 used a disposable TAP in an isolated user/network namespace: creation and replacement through the client succeeded, and direct `GET /vm/config` readback confirmed the interface ID and TAP name.

End-to-end network verification used the `configure_and_start` example with its TAP argument, Firecracker v1.17.0, the same CI kernel recorded below, and a disposable ext4 image containing a static init program. In an isolated user/network namespace, the guest configured `172.16.0.2/30` and successfully sent a TCP payload to the host-side TAP address `172.16.0.1`. This verifies guest-to-host connectivity, not Internet routing/NAT, DHCP, or rate-limit throughput.

Instance-start protocol scenarios cover the action payload, empty 204 success, owned faults surviving client destruction, unexpected 200 responses, timeouts, disconnects, oversized faults, and absence of automatic retries. Live verification used Firecracker v1.17.0, the upstream CI x86_64 kernel `firecracker-ci/20261021-1e5fcc27b59f-0/x86_64/vmlinux-6.1.188`, and a temporary ext4 root filesystem with a static minimal init program. The configure-and-start example succeeded, `GET /` reported `Running`, and serial output confirmed the init program ran. Direct API probes rejected unconfigured and repeated starts with HTTP 400. This is a minimal boot smoke check, not verification of a production guest or application.

Observability protocol scenarios cover omitted versus explicit false/empty fields, escaped paths and property keys/values, string-valued properties as JSON objects, empty property maps, owned faults surviving client destruction, unexpected statuses, timeouts, disconnects, oversized faults, and no automatic retries for logger/metrics configuration or flushing.

Live observability verification on Firecracker v1.17.0 used the `observability` example to configure real log and metrics files, then the configure-and-start example to start a disposable VM with the CI kernel and minimal ext4 image described above. The post-start `--flush` command succeeded; logs contained the `FlushMetrics` action and successful response with debug level/origin metadata. Metrics lines parsed as JSON and contained the configured instance ID, `{"source":"firecrackerz"}` properties, and API-server/logger counters. Repeated metrics initialization returned HTTP 400. A pre-start flush also returned HTTP 400, preserving Firecracker's lifecycle rejection. FIFO operation, rotation, and downstream shipping were not exercised.

Use a disposable instance for general integration checks. The inspection example sends only `GET /version`, `GET /`, and `GET /machine-config`; it does not configure or boot a guest.

`configure-test` **writes** configuration and requires the `--disposable` acknowledgement. Never point it at an instance you need to preserve. It sets configuration twice and submits an invalid update to verify rejection leaves prior state intact.

`boot-source-test` also **writes** and requires `--disposable`. It accepts kernel/initrd paths in the server's filesystem, exercises valid and invalid replacements, and leaves the kernel configured with empty boot arguments and no initrd. Use regular image files as its inputs. It never starts the guest.

`drive-test` **writes** and requires `--disposable`. Supply a regular image file readable by Firecracker. It creates/replaces the `rootfs` drive, checks invalid updates, and leaves a read-only root drive with optional settings omitted. It never starts the guest.

`configure_and_start` **writes configuration and starts the guest**; it requires `--disposable`. Supply an uncompressed guest kernel and a bootable root filesystem readable in Firecracker's namespace. An optional TAP name before `--disposable` configures a network interface; the TAP must already exist in Firecracker's network namespace. The example uses a read-only root drive and `console=ttyS0 reboot=k panic=0`; a panicking guest remains stopped in the panic handler rather than rebooting automatically. The caller owns readiness checks and shutdown/cleanup. Configuration is sequential and is not rolled back if a later request fails.

## Architecture

- `src/root.zig`: public exports only.
- `src/client.zig`: unified construction, handshake, metadata, and ownership.
- `src/models.zig`: stable public metadata, borrowed configuration requests, and owned instance/configuration responses.
- `src/result.zig`: owned results and HTTP faults.
- `src/internal/discovery.zig`: executable resolution and bounded probing.
- `src/internal/version.zig`: parsing and explicit support registry.
- `src/internal/transport.zig`: shared Unix-socket HTTP transport.
- `src/internal/operations.zig`: shared endpoint operations.
- `src/internal/backend.zig`: private contract selection and dispatch.
- `src/versions/v1_17/adapter.zig`: wire-request encoding and response decoding.

See [AGENTS.md](AGENTS.md) for the intended full-client layout. Feature capabilities and additional endpoints are not implemented; there are no placeholder endpoint methods.

### Model generation and additional versions

`zig build codegen` invokes `openapi2zig generate --models-only` for each configured version, reading `spec/<version>/firecracker.json` and overwriting `src/versions/<version>/models.zig`. Do not hand-edit generated models. Keep stable public types and handwritten adapters separate.

Adding runtime support requires pinned schema provenance, contract comparison, explicit registration, an adapter where behavior differs, and verification against that release. Directory names and successful generation do not establish support. Future operations must reject unsupported fields rather than silently discarding them.

## References

- [Firecracker API specification](https://github.com/firecracker-microvm/firecracker/blob/main/src/firecracker/swagger/firecracker.yaml)
- [Firecracker API request documentation](https://github.com/firecracker-microvm/firecracker/tree/main/docs/api_requests)
- [Dusty HTTP library](https://github.com/lalinsky/dusty)
- [Repository license](LICENSE)
