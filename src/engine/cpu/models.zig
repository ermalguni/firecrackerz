/// Custom CPU template, also returned within full VM configuration.
/// For PUT, strings and nested slices are borrowed for the call; null fields
/// are omitted and explicit empty arrays are preserved. Firecracker validates
/// architecture-specific fields and bitmaps; acceptance is not proof of boot.
pub const CpuConfiguration = struct {
    cpuid_modifiers: ?[]const CpuidLeafModifier = null,
    kvm_capabilities: ?[]const []const u8 = null,
    msr_modifiers: ?[]const CpuRegisterModifier = null,
    vcpu_features: ?[]const VcpuFeatures = null,
    reg_modifiers: ?[]const CpuRegisterModifier = null,
};

pub const CpuidLeafModifier = struct {
    leaf: []const u8,
    subleaf: []const u8,
    flags: i64,
    modifiers: []const CpuidRegisterModifier,
};

pub const CpuidRegisterModifier = struct {
    register: []const u8,
    bitmap: []const u8,
};

pub const CpuRegisterModifier = struct {
    addr: []const u8,
    bitmap: []const u8,
};

pub const VcpuFeatures = struct {
    index: i64,
    bitmap: []const u8,
};
