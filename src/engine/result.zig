const std = @import("std");

pub const HttpFault = struct {
    allocator: std.mem.Allocator,
    status: u16,
    body: []const u8,

    pub fn deinit(self: *HttpFault) void {
        self.allocator.free(self.body);
        self.* = undefined;
    }
};

/// Owning result. Do not copy; call deinit exactly once. Local failures use Zig errors.
/// T is void or a struct; resource-owning structs provide deinit, value structs do not.
pub fn Result(comptime T: type) type {
    return union(enum) {
        success: T,
        fault: HttpFault,

        pub fn deinit(self: *@This()) void {
            switch (self.*) {
                .success => |*value| if (T != void and @hasDecl(T, "deinit")) value.deinit(),
                .fault => |*fault| fault.deinit(),
            }
            self.* = undefined;
        }
    };
}
