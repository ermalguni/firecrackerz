# firecrackerz

Zig 0.17 bindings for the [Firecracker API](https://github.com/firecracker-microvm/firecracker), with one public client and private version adapters.

## Status and scope

Connection and machine configuration reads/writes are implemented: executable discovery, version selection, Unix-socket HTTP handshake, connection metadata, `getMachineConfiguration()`, `putMachineConfiguration()`, and resource cleanup. **Firecracker v1.17.0 is the only accepted runtime release.** Connection, configuration updates, and readback have been exercised against real v1.17.0 instances.

Boot-source/device configuration, action methods, capability queries, and development-snapshot support are not implemented. Generated v1.18 models do not establish runtime support.

The client connects to an existing process. Launching Firecracker, managing the jailer, preparing images, host networking, and VM/process lifecycle remain application responsibilities.

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
- Responses outside the operation's expected status (200 for reads, 204 for configuration writes) return `.fault` with owned raw body and numeric status. Oversized or unreadable fault bodies remain transport errors.
- `Result(Client).deinit()` releases either its client or its HTTP fault. Do not also deinitialize the contained client.
- Clients and results are owning values: do not copy them or deinitialize them twice.
- The allocator and I/O runtime must outlive the client. Metadata strings are borrowed until client destruction.
- Input paths are copied during construction. Failed construction releases partially acquired resources.
- Concurrent use is not supported.

## Development and verification

| Command | Purpose |
| --- | --- |
| `zig build` / `zig build check` | Compile library tests, protocol and configuration runners, and inspection example |
| `zig build test` | Run version and discovery unit tests |
| `zig build protocol` | Run local Unix-socket connection, machine configuration, and subprocess discovery scenarios |
| `zig build discovery-test` | Run the same combined protocol scenarios |
| `zig build examples` | Build and install the inspection example |
| `zig build inspect -- SOCKET EXECUTABLE` | Print verified metadata and current machine configuration |
| `zig build integration -- SOCKET EXECUTABLE` | Run the inspection example against a disposable real instance |
| `zig build configure-test -- SOCKET EXECUTABLE --disposable` | Mutate a disposable pre-boot instance; verify readback, optional-field reset, and invalid-update rejection |
| `zig build codegen` | Regenerate version-specific wire models |

Protocol scenarios cover explicit and PATH discovery, supported versions, content-length and chunked responses, version mismatch, preserved HTTP faults, malformed JSON, socket absence, oversized responses, request and discovery timeouts, malformed executable output, process failure, and unsupported releases.

Machine configuration scenarios additionally cover a fresh connection after the handshake, repeated reads with retained results, strings and faults surviving client destruction, absent optional fields, missing required fields, and server disconnects.

PUT scenarios verify omitted versus explicit optional fields, JSON content type and request body, empty HTTP 204 success, unexpected statuses, owned fault bodies, timeouts, disconnects, and oversized fault responses.

Use a disposable instance for general integration checks. The inspection example sends only `GET /version` and `GET /machine-config`; it does not configure or boot a guest.

`configure-test` **writes** configuration and requires the `--disposable` acknowledgement. Never point it at an instance you need to preserve. It sets configuration twice and submits an invalid update to verify rejection leaves prior state intact.

## Architecture

- `src/root.zig`: public exports only.
- `src/client.zig`: unified construction, handshake, metadata, and ownership.
- `src/models.zig`: stable public metadata, borrowed configuration requests, and owned configuration responses.
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
