const std = @import("std");
const models = @import("../../../models.zig");

pub fn encodeCpuConfiguration(allocator: std.mem.Allocator, request: models.CpuConfiguration) ![]u8 {
    // Public nested shapes match this contract. Borrow their slices instead of
    // allocating a second tree of generated wire entries.
    return std.json.Stringify.valueAlloc(allocator, request, .{ .emit_null_optional_fields = false });
}
