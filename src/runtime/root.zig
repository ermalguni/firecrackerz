pub const Vm = @import("vm.zig").Vm;
pub const StartOptions = @import("vm.zig").StartOptions;
pub const BootSpec = @import("spec.zig").BootSpec;

test {
    _ = @import("artifacts/workspace.zig");
}
