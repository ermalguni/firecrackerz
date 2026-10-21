const std = @import("std");
const dusty = @import("dusty");

/// An owned, fully buffered response. Release it before moving or destroying
/// the transport that produced it. The body remains valid until deinit.
pub const Response = struct {
    status: u16,
    body: []const u8,
    response: dusty.ClientResponse,

    pub fn deinit(self: *Response) void {
        self.response.deinit();
        self.* = undefined;
    }
};

/// Sequential HTTP requests over one owned Unix socket path.
/// The allocator and I/O implementation must outlive this transport and its
/// responses. There are no retries, redirects, or unbounded streaming reads.
pub const Transport = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    client: dusty.Client,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        socket_path: []const u8,
        timeout_ms: u32,
    ) !Transport {
        return .{
            .allocator = allocator,
            .socket_path = try allocator.dupe(u8, socket_path),
            .client = dusty.Client.init(allocator, io, .{
                .max_redirects = 0,
                .max_response_size = 64 * 1024,
                // An idle connection retains a pointer into its client. Closing
                // it lets the transport move safely once its response is freed.
                .max_idle_connections = 0,
                .timeout = .fromMilliseconds(timeout_ms),
            }),
        };
    }

    /// All responses must have been released first.
    pub fn deinit(self: *Transport) void {
        self.client.deinit();
        self.allocator.free(self.socket_path);
        self.* = undefined;
    }

    pub fn get(self: *Transport, comptime path: []const u8) !Response {
        return self.request(path, .get, null, null);
    }

    pub fn put(self: *Transport, comptime path: []const u8, body: []const u8) !Response {
        var keys: [1][]const u8 = undefined;
        var values: [1][]const u8 = undefined;
        var hashes: [1]u8 = undefined;
        var headers: dusty.Headers = .{ .keys = &keys, .values = &values, .hashes = &hashes };
        try headers.put("Content-Type", "application/json");
        return self.request(path, .put, body, &headers);
    }

    fn request(self: *Transport, comptime path: []const u8, method: dusty.Method, request_body: ?[]const u8, headers: ?*const dusty.Headers) !Response {
        // Non-streaming fetch includes the entire body in Dusty's deadline and
        // size limit; body() below only retrieves that already-buffered result.
        var response = try self.client.fetch("http://localhost" ++ path, .{
            .method = method,
            .body = request_body,
            .headers = headers,
            .unix_socket_path = self.socket_path,
            .decompress = false,
            .stream = false,
        });
        errdefer response.deinit();

        const body = try response.body() orelse "";
        return .{
            .status = @intCast(@backingInt(response.status())),
            .body = body,
            .response = response,
        };
    }
};
