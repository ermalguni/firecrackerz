const std = @import("std");
const discovery = @import("internal/discovery.zig");
const version = @import("internal/version.zig");
const Backend = @import("internal/backend.zig").Backend;
const Transport = @import("internal/transport.zig").Transport;
const models = @import("models.zig");
const results = @import("result.zig");
const operations = @import("internal/operations.zig");

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
        return operations.getInstanceInfo(self.allocator, &self.transport, self.backend);
    }

    /// Fetches current configuration. The owned result may outlive the client.
    pub fn getMachineConfiguration(self: *Client) !results.Result(models.MachineConfiguration) {
        return operations.getMachineConfiguration(self.allocator, &self.transport, self.backend);
    }

    /// Pre-boot replacement, not PATCH: omitted optional fields reset to defaults.
    /// Request data is borrowed during the call. No automatic retries.
    pub fn putMachineConfiguration(self: *Client, request: models.MachineConfigurationRequest) !results.Result(void) {
        return operations.putMachineConfiguration(self.allocator, &self.transport, self.backend, request);
    }

    /// Creates or replaces the pre-boot source. Paths belong to the server's
    /// filesystem namespace. Request strings are borrowed; no automatic retries.
    pub fn putGuestBootSource(self: *Client, request: models.BootSourceRequest) !results.Result(void) {
        return operations.putGuestBootSource(self.allocator, &self.transport, self.backend, request);
    }

    /// Creates or replaces a pre-boot drive. The ID selects both path and body.
    /// Request strings are borrowed; server paths are not opened locally.
    pub fn putGuestDrive(self: *Client, request: models.DriveRequest) !results.Result(void) {
        return operations.putGuestDrive(self.allocator, &self.transport, self.backend, request);
    }

    /// Starts the configured microVM once. Success is not guest readiness.
    /// Never retried: a timeout/disconnect can leave the VM running.
    /// Firecracker validates configuration and lifecycle; no local state is cached.
    pub fn startInstance(self: *Client) !results.Result(void) {
        return operations.startInstance(self.allocator, &self.transport);
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
