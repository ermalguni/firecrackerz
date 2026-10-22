const std = @import("std");
const discovery = @import("internal/discovery.zig");
const version = @import("internal/version.zig");
const Backend = @import("internal/backend.zig").Backend;
const Transport = @import("internal/transport.zig").Transport;
const models = @import("models.zig");
const results = @import("result.zig");
const instance = @import("instance/operations.zig");
const machine = @import("machine/operations.zig");
const cpu = @import("cpu/operations.zig");
const boot_source = @import("boot_source/operations.zig");
const drive = @import("drive/operations.zig");
const network_interface = @import("network_interface/operations.zig");
const balloon = @import("balloon/operations.zig");
const memory_hotplug = @import("memory_hotplug/operations.zig");
const mmds = @import("mmds/operations.zig");
const snapshot = @import("snapshot/operations.zig");
const observability = @import("observability/operations.zig");
const devices = @import("devices/operations.zig");
const vm_configuration = @import("vm_configuration/operations.zig");

pub const Binary = discovery.Binary;
pub const ConnectOptions = struct {
    socket_path: []const u8,
    binary: Binary,
    discovery_timeout_ms: u32 = 3000,
    request_timeout_ms: u32 = 3000,
};

/// Owns its transport and discovery metadata. Sequential use only; do not copy.
pub const Client = struct {
    allocator: std.mem.Allocator,
    discovered: discovery.Discovered,
    transport: Transport,
    backend: Backend,
    running_version: version.Version,

    /// HTTP rejection is an owned fault result; local failures are Zig errors.
    pub fn connect(allocator: std.mem.Allocator, io: std.Io, options: ConnectOptions) !results.Result(Client) {
        if (options.discovery_timeout_ms == 0 or options.request_timeout_ms == 0) return error.InvalidTimeout;
        var discovered = try discovery.discover(allocator, io, options.binary, options.discovery_timeout_ms);
        errdefer discovered.deinit(allocator);
        const backend = try Backend.select(discovered.version);
        var transport = try Transport.init(allocator, io, options.socket_path, options.request_timeout_ms);
        errdefer transport.deinit();
        var response = try transport.get("/version");
        errdefer response.deinit();
        if (response.status != 200) {
            const body = try allocator.dupe(u8, response.body);
            const status = response.status;
            response.deinit();
            transport.deinit();
            discovered.deinit(allocator);
            return .{ .fault = .{ .allocator = allocator, .status = status, .body = body } };
        }
        const running = try backend.decodeVersion(allocator, response.body);
        if (!version.eql(discovered.version, running)) return error.VersionMismatch;
        response.deinit();
        return .{ .success = .{
            .allocator = allocator,
            .discovered = discovered,
            .transport = transport,
            .backend = backend,
            .running_version = running,
        } };
    }

    pub fn info(self: *const Client) models.ConnectionInfo {
        return .{
            .executable_path = self.discovered.executable_path,
            .detected_version = publicVersion(self.discovered.version),
            .running_version = publicVersion(self.running_version),
            .contract = self.backend.contract(),
        };
    }

    /// Fetches live instance state, unlike cached info(). Does not poll for readiness.
    /// The owned result may outlive the client, but not its allocator.
    pub fn getInstanceInfo(self: *Client) !results.Result(models.InstanceInfo) {
        return instance.getInstanceInfo(self.allocator, &self.transport, self.backend);
    }

    /// Fetches current configuration. The owned result may outlive the client.
    pub fn getMachineConfiguration(self: *Client) !results.Result(models.MachineConfiguration) {
        return machine.getMachineConfiguration(self.allocator, &self.transport, self.backend);
    }

    /// Exports all VM resource configuration, not guest state or MMDS contents.
    /// The owned result and its nested data may outlive the client.
    pub fn getVmConfiguration(self: *Client) !results.Result(models.FullVmConfiguration) {
        return vm_configuration.getVmConfiguration(self.allocator, &self.transport, self.backend);
    }

    /// Pre-boot replacement, not PATCH: omitted optional fields reset to defaults.
    /// Request data is borrowed during the call. No automatic retries.
    pub fn putMachineConfiguration(self: *Client, request: models.MachineConfigurationRequest) !results.Result(void) {
        return machine.putMachineConfiguration(self.allocator, &self.transport, self.backend, request);
    }

    /// Pre-boot partial update: omitted fields preserve their current values.
    /// Firecracker validates values and lifecycle. Borrowed data; no retries.
    pub fn patchMachineConfiguration(self: *Client, request: models.MachineConfigurationUpdate) !results.Result(void) {
        return machine.patchMachineConfiguration(self.allocator, &self.transport, self.backend, request);
    }

    /// Sets a custom pre-boot CPU template. Strings and nested slices are borrowed.
    /// Firecracker validates architecture-specific input. No automatic retries.
    pub fn putCpuConfiguration(self: *Client, request: models.CpuConfiguration) !results.Result(void) {
        return cpu.putCpuConfiguration(self.allocator, &self.transport, self.backend, request);
    }

    /// Creates or replaces the pre-boot source. Paths belong to the server's
    /// filesystem namespace. Request strings are borrowed; no automatic retries.
    pub fn putGuestBootSource(self: *Client, request: models.BootSourceRequest) !results.Result(void) {
        return boot_source.putGuestBootSource(self.allocator, &self.transport, self.backend, request);
    }

    /// Creates or replaces a pre-boot drive. The ID selects both path and body.
    /// Request strings are borrowed; server paths are not opened locally.
    pub fn putGuestDrive(self: *Client, request: models.DriveRequest) !results.Result(void) {
        return drive.putGuestDrive(self.allocator, &self.transport, self.backend, request);
    }

    /// Updates an existing drive's backing path or rate limiter.
    /// The ID selects path and body. Borrowed strings; no local file I/O or retries.
    pub fn patchGuestDrive(self: *Client, request: models.DriveUpdate) !results.Result(void) {
        return drive.patchGuestDrive(self.allocator, &self.transport, self.backend, request);
    }

    /// Creates or updates the pre-boot vsock device. Strings are borrowed;
    /// the socket path belongs to the server. No local socket I/O or retries.
    /// HTTP rejections return owned faults that the caller must deinitialize.
    pub fn putGuestVsock(self: *Client, request: models.VsockConfiguration) !results.Result(void) {
        return devices.putGuestVsock(self.allocator, &self.transport, self.backend, request);
    }

    /// Creates the pre-boot entropy device. Null rate limiters are omitted.
    /// No automatic retries; the caller must deinitialize returned faults.
    pub fn putEntropy(self: *Client, request: models.EntropyConfiguration) !results.Result(void) {
        return devices.putEntropy(self.allocator, &self.transport, self.backend, request);
    }

    /// Configures the serial console; the guest kernel must also enable it.
    /// Borrows the server output path; no local file I/O or automatic retries.
    /// The caller must deinitialize returned HTTP faults.
    pub fn putSerial(self: *Client, request: models.SerialConfiguration) !results.Result(void) {
        return devices.putSerial(self.allocator, &self.transport, self.backend, request);
    }

    /// Creates or updates a pre-boot pmem device. The borrowed ID selects path
    /// and body; the backing path belongs to the server. No local I/O or retries.
    /// The caller must deinitialize returned HTTP faults.
    pub fn putGuestPmem(self: *Client, request: models.PmemConfiguration) !results.Result(void) {
        return devices.putGuestPmem(self.allocator, &self.transport, self.backend, request);
    }

    /// Updates a pmem device's rate limiter after boot, not its backing path.
    /// The borrowed ID selects path and body. No automatic retries.
    /// The caller must deinitialize returned HTTP faults.
    pub fn patchGuestPmem(self: *Client, request: models.PmemUpdate) !results.Result(void) {
        return devices.patchGuestPmem(self.allocator, &self.transport, self.backend, request);
    }

    /// Creates or replaces a pre-boot network interface using an existing TAP.
    /// The ID selects both path and body. Does not configure host networking.
    /// Request strings are borrowed; no automatic retries.
    pub fn putGuestNetworkInterface(self: *Client, request: models.NetworkInterfaceRequest) !results.Result(void) {
        return network_interface.putGuestNetworkInterface(self.allocator, &self.transport, self.backend, request);
    }

    /// Updates an existing interface's RX/TX rate limiters, not host networking.
    /// The borrowed ID selects path and body. No automatic retries.
    pub fn patchGuestNetworkInterface(self: *Client, request: models.NetworkInterfaceUpdate) !results.Result(void) {
        return network_interface.patchGuestNetworkInterface(self.allocator, &self.transport, self.backend, request);
    }

    /// Reads live balloon configuration, not statistics. Scalar values outlive
    /// the client; absent optional fields remain null.
    pub fn getBalloon(self: *Client) !results.Result(models.BalloonConfiguration) {
        return balloon.getBalloon(self.allocator, &self.transport, self.backend);
    }

    /// Reads the latest balloon statistics without enabling polling or waiting
    /// for a fresh guest sample. Absent guest counters remain null.
    pub fn getBalloonStatistics(self: *Client) !results.Result(models.BalloonStatistics) {
        return balloon.getBalloonStatistics(self.allocator, &self.transport, self.backend);
    }

    /// Creates or replaces a balloon device before boot. Null fields are omitted.
    /// Firecracker validates values and lifecycle. No automatic retries.
    pub fn putBalloon(self: *Client, request: models.BalloonConfiguration) !results.Result(void) {
        return balloon.putBalloon(self.allocator, &self.transport, self.backend, request);
    }

    /// Changes an existing balloon's target size, not its other settings.
    /// Success acknowledges the target, not guest reclamation. No retries.
    pub fn patchBalloon(self: *Client, request: models.BalloonUpdate) !results.Result(void) {
        return balloon.patchBalloon(self.allocator, &self.transport, self.backend, request);
    }

    /// Changes the polling interval, scheduling the first update immediately.
    /// Cannot toggle statistics after boot. Does not wait for a sample or retry.
    pub fn patchBalloonStatistics(self: *Client, request: models.BalloonStatisticsUpdate) !results.Result(void) {
        return balloon.patchBalloonStatistics(self.allocator, &self.transport, self.backend, request);
    }

    /// Starts a free-page hinting run, enabled through putBalloon before boot.
    /// Does not wait for guest completion. No automatic retries.
    pub fn startBalloonHinting(self: *Client, request: models.BalloonHintingStartRequest) !results.Result(void) {
        return balloon.startBalloonHinting(self.allocator, &self.transport, self.backend, request);
    }

    /// Requests that the hinting run stop. No automatic retries or guest polling.
    pub fn stopBalloonHinting(self: *Client) !results.Result(void) {
        return balloon.stopBalloonHinting(self.allocator, &self.transport);
    }

    /// Reads the last host/guest hinting commands without caching or polling.
    pub fn getBalloonHintingStatus(self: *Client) !results.Result(models.BalloonHintingStatus) {
        return balloon.getBalloonHintingStatus(self.allocator, &self.transport, self.backend);
    }

    /// Configures pre-boot virtio-mem capacity and granularity. Null fields are
    /// omitted; Firecracker validates values and lifecycle. No retries.
    pub fn putMemoryHotplug(self: *Client, request: models.MemoryHotplugConfiguration) !results.Result(void) {
        return memory_hotplug.putMemoryHotplug(self.allocator, &self.transport, self.backend, request);
    }

    /// Changes the virtio-mem target, not its capacity. Does not wait for the
    /// guest to plug/unplug memory. No automatic retries.
    pub fn patchMemoryHotplug(self: *Client, request: models.MemoryHotplugUpdate) !results.Result(void) {
        return memory_hotplug.patchMemoryHotplug(self.allocator, &self.transport, self.backend, request);
    }

    /// Reads live virtio-mem status, including requested and plugged sizes.
    /// Does not poll for convergence. Absent fields remain null.
    pub fn getMemoryHotplug(self: *Client) !results.Result(models.MemoryHotplugStatus) {
        return memory_hotplug.getMemoryHotplug(self.allocator, &self.transport, self.backend);
    }

    /// Configures MMDS before boot, not its metadata contents. Interface IDs must
    /// already exist. Request data is borrowed; Firecracker validates values.
    /// Null options are omitted. No automatic retries.
    pub fn putMmdsConfiguration(self: *Client, request: models.MmdsConfiguration) !results.Result(void) {
        return mmds.putMmdsConfiguration(self.allocator, &self.transport, self.backend, request);
    }

    /// Reads owned metadata, not MMDS configuration. Nested JSON data may outlive
    /// the client, but not the allocator. Release the enclosing result once.
    pub fn getMmds(self: *Client) !results.Result(models.MmdsContents) {
        return mmds.getMmds(self.allocator, &self.transport);
    }

    /// Replaces the entire metadata store with borrowed JSON text.
    /// Firecracker validates the document. No automatic retries.
    pub fn putMmds(self: *Client, json: []const u8) !results.Result(void) {
        return mmds.putMmds(self.allocator, &self.transport, json);
    }

    /// Applies a JSON merge patch to the existing metadata store.
    /// JSON text is borrowed; Firecracker merges and validates. No retries.
    pub fn patchMmds(self: *Client, json: []const u8) !results.Result(void) {
        return mmds.patchMmds(self.allocator, &self.transport, json);
    }

    /// Configures Firecracker logging; does not create or read the destination.
    /// Request data is borrowed during the call. No automatic retries.
    pub fn putLogger(self: *Client, request: models.LoggerRequest) !results.Result(void) {
        return observability.putLogger(self.allocator, &self.transport, self.backend, request);
    }

    /// Initializes metrics output in Firecracker's filesystem namespace.
    /// Firecracker rejects repeated initialization. No automatic retries.
    pub fn putMetrics(self: *Client, request: models.MetricsRequest) !results.Result(void) {
        return observability.putMetrics(self.allocator, &self.transport, self.backend, request);
    }

    /// Requests an immediate post-start metrics flush, not a metrics read.
    /// Never retried: a timeout may follow a completed flush.
    pub fn flushMetrics(self: *Client) !results.Result(void) {
        return observability.flushMetrics(self.allocator, &self.transport);
    }

    /// Starts the configured microVM once. Success is not guest readiness.
    /// Never retried: a timeout/disconnect can leave the VM running.
    /// Firecracker validates configuration and lifecycle; no local state is cached.
    pub fn startInstance(self: *Client) !results.Result(void) {
        return instance.startInstance(self.allocator, &self.transport);
    }

    /// Sends Ctrl+Alt+Del; v1.17.0 supports this on Intel/AMD only.
    /// Success acknowledges injection, not guest shutdown. Guest handling varies.
    /// Never retried: a timeout/disconnect can follow a delivered key sequence.
    pub fn sendCtrlAltDel(self: *Client) !results.Result(void) {
        return instance.sendCtrlAltDel(self.allocator, &self.transport);
    }

    /// Pauses the microVM via PATCH /vm. Firecracker validates lifecycle state.
    /// Never retried; on timeout/disconnect, inspect live state before acting.
    pub fn pauseInstance(self: *Client) !results.Result(void) {
        return instance.pauseInstance(self.allocator, &self.transport);
    }

    /// Resumes a paused microVM; does not start an unbooted instance.
    /// Never retried; no local lifecycle state is cached.
    pub fn resumeInstance(self: *Client) !results.Result(void) {
        return instance.resumeInstance(self.allocator, &self.transport);
    }

    /// Creates a Full or Diff snapshot of a paused VM. Diff requires dirty-page
    /// tracking. Does not pause/resume, open paths locally, or retry.
    /// A timeout/disconnect may follow completed or partially written files.
    pub fn createSnapshot(self: *Client, request: models.SnapshotCreateRequest) !results.Result(void) {
        return snapshot.createSnapshot(self.allocator, &self.transport, self.backend, request);
    }

    /// Restores into a fresh Firecracker process; optionally resumes via resume_vm.
    /// Does not prepare memory images, TAPs, or a UFFD server. Never retried:
    /// a timeout/disconnect may follow a successful restore or a running guest.
    pub fn loadSnapshot(self: *Client, request: models.SnapshotLoadRequest) !results.Result(void) {
        return snapshot.loadSnapshot(self.allocator, &self.transport, self.backend, request);
    }

    pub fn deinit(self: *Client) void {
        self.transport.deinit();
        self.discovered.deinit(self.allocator);
        self.* = undefined;
    }
};

fn publicVersion(v: version.Version) models.Version {
    return .{ .major = v.major, .minor = v.minor, .patch = v.patch };
}
