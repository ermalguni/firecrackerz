# firecrackerz

Zig 0.17 bindings for the [Firecracker API](https://github.com/firecracker-microvm/firecracker), designed to provide **one client interface across multiple Firecracker versions**.

## Project status

This project is in the implementation-design stage. The package manifest and build configuration exist, but `src/root.zig` and the unified client implementation are currently absent. The API examples below describe the intended interface; they are **not runnable examples of an implemented API**.

Do not infer runtime version support from directory names or build targets. Supported releases must be explicitly registered and verified before being advertised as supported.

## Goals and scope

- Discover a local Firecracker executable and determine its version.
- Reject unsupported versions before constructing a usable client.
- Provide stable public request and response models, independent of runtime version.
- Select version-specific adapters internally, without requiring callers to import version namespaces.
- Communicate with a running Firecracker instance over its Unix-domain API socket.
- Reject unsupported features explicitly rather than silently ignoring request fields.

The proposed client connects to an existing process. Launching Firecracker, managing the jailer, preparing images, configuring host networking, and managing VM/process lifecycle remain application responsibilities. Automatic process launching is not part of the proposed client interface.

## Requirements

| Component | Requirement |
| --- | --- |
| Zig | Minimum version `0.17.0`, as declared in `build.zig.zon` |
| Host | Linux for local Firecracker discovery and operation |
| Firecracker | An installed executable with a version accepted by the library |
| API endpoint | An accessible Unix socket served by a running Firecracker instance |
| HTTP dependency | Dusty v0.4.0, pinned by commit and package hash |
| Development tooling | `openapi2zig` on `PATH` for model generation; Python 3 for the configured protocol-fixture target |

Running actual microVMs also requires Firecracker's host prerequisites, including KVM access. Installing this Zig package does not install Firecracker.

## Intended connection flow

`Client.connect` is intended to perform these steps:

1. Resolve an explicit executable path or search a caller-supplied `PATH`.
2. Execute the resolved binary with `--version`, without invoking a shell.
3. Parse the version and select an explicitly supported API contract.
4. Query `GET /version` on the supplied API socket.
5. Verify that the running instance matches the discovered binary version.
6. Return a unified client backed by the selected adapter.

An installed binary does not prove which version serves a socket. Both checks are necessary for this construction path.

Discovery executes local code. Privileged applications should use a trusted explicit executable path rather than an untrusted search path. Discovery must bound execution time and output size, and clean up its child process on failure.

## Integrating the package

The existing build configuration exports a module named `firecrackerz`. Once the implementation is available, add the package to your application's dependencies:

```sh
zig fetch --save=firecrackerz <repository-or-package-url>
```

Replace the URL placeholder with the package source you intend to use; pin a revision for reproducible builds.

In your application's `build.zig`, after creating its executable:

```zig
const firecrackerz = b.dependency("firecrackerz", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("firecrackerz", firecrackerz.module("firecrackerz"));
```

This wiring matches the declared module name, but cannot compile against the current missing source implementation.

### Proposed client usage

The following fragment assumes the application supplies an allocator, `std.Io`, and a process search path. Names and signatures are design targets, not a released API.

```zig
const fc = @import("firecrackerz");

var client = try fc.Client.connect(allocator, io, .{
    .socket_path = "/run/firecracker.sock",
    .binary = .{ .search_path = process_path },
    // Alternatively: .binary = .{ .executable = "/usr/bin/firecracker" },
    .allow_development = false,
});
defer client.deinit();

var result = try client.putMachineConfiguration(.{
    .vcpu_count = 2,
    .mem_size_mib = 256,
});
defer result.deinit();

switch (result) {
    .success => {},
    .fault => |fault| {
        std.log.err("Firecracker returned HTTP {d}: {s}", .{
            fault.status,
            fault.body,
        });
        return error.ConfigurationRejected;
    },
}
```

This operation configures a machine; it does not boot a guest. The application must configure the required boot source and devices before requesting `InstanceStart`.

### Public API design

| Surface | Intended responsibility |
| --- | --- |
| `Client.connect` | Discovery, compatibility selection, socket version verification |
| `Client.deinit` | Release client-owned resources |
| `Client.info` | Executable path, detected and running versions, selected contract |
| `Client.capabilities` | Feature availability without caller-side version comparisons |
| API operation methods | Unified requests and responses, with internal version dispatch |
| `models` | Version-independent public types |
| `Result(T)` | Owned success value or HTTP fault |

Preserve upstream operation names where practical, such as `putMachineConfiguration` and `createSyncAction`.

## Compatibility and error handling

The intended support policy is conservative:

- Accept only explicitly verified runtime versions.
- Ignore semantic-version build metadata when selecting a contract.
- Reject unknown patch releases and prereleases rather than assuming compatibility.
- Require explicit opt-in for supported development snapshots. A development version string alone does not identify an upstream commit.
- Reuse one adapter across releases only after validating their API contracts.

Public models must not alias a runtime-selected version's wire models. Adapters translate stable public types into the selected contract and normalize responses back into public types.

If a caller supplies a field unavailable in the selected contract, return `error.UnsupportedFeature` before sending the request. Omitting an optional newer-only field should still permit a compatible request. Capability queries are a convenience; operations must enforce compatibility independently.

Construction should distinguish executable absence, process failure, malformed version output, unsupported versions, disallowed development versions, and installed/running version mismatches. Transport and protocol errors should retain their own meaning.

Keep HTTP faults separate from ordinary Zig errors. The proposed `Result(T)` preserves HTTP status and raw fault body, while Zig errors represent local discovery, compatibility, allocation, transport, and decoding failures.

### Intended ownership rules

- Clients and results own their resources and require `deinit`.
- The allocator and I/O runtime must outlive the client; result storage must not outlive its allocator.
- Request data is borrowed for the duration of a call.
- Do not copy live owning client values or assume concurrent calls are supported.
- Construction failures must release partially initialized resources.
- Configuration sequences are not transactions: earlier successful mutations remain applied if a later call fails.

## Target directory structure

This is the intended layout, not a list of currently implemented files. See [AGENTS.md](AGENTS.md) for repository instructions and architectural boundaries.

```text
firecrackerz/
├── build.zig
├── build.zig.zon
├── README.md
├── src/
│   ├── root.zig                 # Public exports
│   ├── client.zig               # Unified facade and construction
│   ├── models.zig               # Stable public models
│   ├── result.zig               # Response ownership and HTTP faults
│   ├── capabilities.zig         # Feature availability
│   ├── internal/
│   │   ├── discovery.zig        # Executable resolution and --version
│   │   ├── version.zig          # Supported-contract registry
│   │   ├── backend.zig          # Private tagged-union dispatch
│   │   ├── transport.zig        # Unix-socket HTTP transport
│   │   └── operations.zig       # Shared endpoint implementations
│   └── versions/
│       ├── v1_17/
│       │   ├── adapter.zig      # Compatibility and conversions
│       │   └── models.zig       # Generated wire models
│       └── v1_18/
│           ├── adapter.zig
│           └── models.zig
├── spec/
│   ├── v1_17/                  # Pinned schemas and provenance
│   └── v1_18/
├── tests/
│   ├── discovery.zig
│   ├── compatibility.zig
│   └── protocol.zig
└── examples/
    ├── discover.zig
    ├── inspect.zig
    └── configure_and_start.zig
```

Keep handwritten public models separate from generated wire models. Share identical endpoint implementations and introduce adapter-specific behavior only where contracts differ.

## Development and verification

The current `build.zig` declares these commands. They are build configuration entrypoints, **not claims that the incomplete checkout builds or that these checks have passed**.

| Command | Configured purpose |
| --- | --- |
| `zig build` / `zig build check` | Compile library tests, examples, and scenario runners |
| `zig build test` | Run library tests |
| `zig build codegen` | Generate version-specific Firecracker models with `openapi2zig` |
| `zig build protocol` | Exercise API contracts through a local Unix-socket fixture |
| `zig build discovery-test` | Exercise executable discovery, limits, and deadlines |
| `zig build examples` | Build and install usage examples |
| `zig build integration -- SOCKET` | Exercise a disposable v1.17.0 API instance |

These targets require their referenced source files and scripts. Integration checks must use a disposable instance, never a production socket.

Model generation runs `openapi2zig generate --models-only` for each configured version:

| Input specification | Generated output |
| --- | --- |
| `spec/v1_17/firecracker.json` | `src/versions/v1_17/models.zig` |
| `spec/v1_18/firecracker.json` | `src/versions/v1_18/models.zig` |

Run `zig build codegen` after changing the input schemas. It overwrites the generated wire-model files; keep handwritten public models and adapters separate. Generation does not implement the client or establish runtime compatibility. Add new version identifiers to the code-generation loop in `build.zig`.

### Adding version support

1. Pin the upstream schema and record its release or commit provenance under `spec/`.
2. Compare it with existing supported contracts.
3. Generate version-specific wire models; do not silently change public models to match an upstream schema.
4. Add or update an adapter only for actual contract differences.
5. Register explicitly accepted versions and capabilities.
6. Verify request encoding, response normalization, unsupported-feature rejection, and discovery/connection version mismatches.
7. Update user-facing compatibility documentation with the versions actually exercised.

For AI agents and contributors: read `AGENTS.md` first, inspect the current implementation before relying on examples, and distinguish design targets from verified behavior. Do not bypass compatibility checks, silently drop fields, or expose version-specific types merely to make a unified method compile.

## References

- [Firecracker project](https://github.com/firecracker-microvm/firecracker)
- [Upstream API specification](https://github.com/firecracker-microvm/firecracker/blob/main/src/firecracker/swagger/firecracker.yaml) — current upstream reference, not a pinned compatibility contract
- [Firecracker API request documentation](https://github.com/firecracker-microvm/firecracker/tree/main/docs/api_requests)
- [Dusty HTTP library](https://github.com/lalinsky/dusty)
- [Repository license](LICENSE)
