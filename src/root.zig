pub const Client = @import("client.zig").Client;
pub const ConnectOptions = @import("client.zig").ConnectOptions;
pub const Binary = @import("client.zig").Binary;
pub const models = @import("models.zig");
pub const Result = @import("result.zig").Result;
pub const HttpFault = @import("result.zig").HttpFault;

test {
    _ = @import("internal/version.zig");
    _ = @import("internal/discovery.zig");
}
