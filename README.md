# firecrackerz

Zig 0.17 bindings for the [Firecracker API](https://github.com/firecracker-microvm/firecracker), with one public client and private version adapters.

## Status and scope

Connection, live instance-information reads, machine configuration reads/writes, boot-source configuration, drive and network-interface configuration, logger and metrics configuration, metrics flushing, and instance start/pause/resume are implemented: executable discovery, version selection, Unix-socket HTTP handshake, connection metadata, `getInstanceInfo()`, `getMachineConfiguration()`, `putMachineConfiguration()`, `putGuestBootSource()`, `putGuestDrive()`, `putGuestNetworkInterface()`, `putLogger()`, `putMetrics()`, `flushMetrics()`, `startInstance()`, `pauseInstance()`, `resumeInstance()`, and resource cleanup. **Firecracker v1.17.0 is the only accepted runtime release.** A disposable disk-backed guest has booted through the client to a minimal init program.

Other device configuration, other action methods, capability queries, and development-snapshot support are not implemented. Generated v1.18 models do not establish runtime support.

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
