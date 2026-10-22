/// Pre-boot boot source. Strings are borrowed for the call. Paths are resolved
/// by Firecracker in its filesystem namespace, not by this client.
pub const BootSourceRequest = struct {
    kernel_image_path: []const u8,
    boot_args: ?[]const u8 = null,
    initrd_path: ?[]const u8 = null,
};
