const std = @import("std");
const fc = @import("firecrackerz").engine;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5 and args.len != 6) return error.InvalidArguments;
    const machine = args.len == 6;
    const expected = args[3];
    var result = fc.Client.connect(init.gpa, init.io, .{
        .socket_path = args[1],
        .binary = if (std.mem.eql(u8, args[4], "search")) .{ .search_path = args[2] } else .{ .executable = args[2] },
        .request_timeout_ms = 150,
        .discovery_timeout_ms = 150,
    }) catch |err| {
        if (!machine and std.mem.eql(u8, expected, @errorName(err))) return;
        std.debug.print("Expected {s}, got {s}\n", .{ expected, @errorName(err) });
        return err;
    };
    var connected = true;
    defer if (connected) result.deinit();
    switch (result) {
        .success => |*client| {
            if (machine and std.mem.startsWith(u8, args[5], "device-")) {
                var written = deviceWrite(client, args[5]["device-".len..]) catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    return err;
                };
                defer written.deinit();
                result.deinit();
                connected = false;
                switch (written) {
                    .success => if (!std.mem.eql(u8, expected, "success")) return error.UnexpectedSuccess,
                    .fault => |fault| {
                        const raw_fault = std.mem.eql(u8, expected, "raw-fault");
                        const code: u16 = if (raw_fault) 503 else if (std.mem.eql(u8, expected, "unexpected-status")) 200 else 400;
                        const body = if (raw_fault) "unavailable\nnot JSON" else "{\"fault_message\":\"denied\"}";
                        if ((!raw_fault and !std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != code or !std.mem.eql(u8, fault.body, body))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (machine and std.mem.eql(u8, args[5], "hotplug-read")) {
                var status = client.getMemoryHotplug() catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    return err;
                };
                defer status.deinit();
                result.deinit();
                connected = false;
                switch (status) {
                    .success => |value| {
                        const wanted: fc.models.MemoryHotplugStatus = if (std.mem.eql(u8, expected, "hotplug-full")) .{
                            .total_size_mib = 1024,
                            .slot_size_mib = 128,
                            .block_size_mib = 2,
                            .plugged_size_mib = 128,
                            .requested_size_mib = 256,
                        } else if (std.mem.eql(u8, expected, "hotplug-zero")) .{
                            .total_size_mib = 0,
                            .slot_size_mib = 0,
                            .block_size_mib = 0,
                            .plugged_size_mib = 0,
                            .requested_size_mib = 0,
                        } else if (std.mem.eql(u8, expected, "hotplug-empty")) .{} else return error.UnexpectedSuccess;
                        if (!std.meta.eql(wanted, value)) return error.IncorrectHotplugStatus;
                    },
                    .fault => |fault| {
                        const code: u16 = if (std.mem.eql(u8, expected, "unexpected-status")) 202 else 400;
                        if ((!std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != code or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (machine and std.mem.startsWith(u8, args[5], "hotplug-")) {
                const full = std.mem.endsWith(u8, args[5], "-full");
                const empty = std.mem.endsWith(u8, args[5], "-empty");
                const zero = std.mem.endsWith(u8, args[5], "-zero");
                const negative = std.mem.endsWith(u8, args[5], "-negative");
                var written = (if (std.mem.startsWith(u8, args[5], "hotplug-patch-")) client.patchMemoryHotplug(.{
                    .requested_size_mib = if (empty) null else if (zero) 0 else if (negative) -1 else 256,
                }) else client.putMemoryHotplug(.{
                    .total_size_mib = if (empty) null else if (zero) 0 else if (negative) -1 else 1024,
                    .slot_size_mib = if (full) 128 else if (zero) @as(?i64, 0) else null,
                    .block_size_mib = if (full) 2 else if (zero) @as(?i64, 0) else null,
                })) catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    return err;
                };
                defer written.deinit();
                result.deinit();
                connected = false;
                switch (written) {
                    .success => if (!std.mem.eql(u8, expected, "success")) return error.UnexpectedSuccess,
                    .fault => |fault| {
                        const code: u16 = if (std.mem.eql(u8, expected, "unexpected-status")) 200 else 400;
                        if ((!std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != code or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (machine and std.mem.eql(u8, args[5], "vm-config")) {
                var exported = client.getVmConfiguration() catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    return err;
                };
                defer exported.deinit();
                if (std.mem.eql(u8, expected, "resources")) {
                    var second = try client.getVmConfiguration();
                    defer second.deinit();
                    switch (second) {
                        .success => |config| if (config.drives != null) return error.IncorrectSecondConfiguration,
                        .fault => return error.UnexpectedFault,
                    }
                }
                result.deinit();
                connected = false;
                switch (exported) {
                    .success => |config| {
                        if (std.mem.eql(u8, expected, "resources")) {
                            if (!std.mem.eql(u8, config.boot_source.?.kernel_image_path, "/kernel") or
                                config.machine_config.?.vcpu_count != 2 or
                                !std.mem.eql(u8, config.drives.?[0].path_on_host.?, "/disk") or
                                config.drives.?[0].rate_limiter.?.bandwidth.?.size != 0 or
                                config.drives.?[0].topology.?.min_io_size != 0 or
                                !std.mem.eql(u8, config.network_interfaces.?[0].host_dev_name, "tap0") or
                                !std.mem.eql(u8, config.cpu_config.?.cpuid_modifiers.?[0].modifiers[0].bitmap, "0b1") or
                                !std.mem.eql(u8, config.cpu_config.?.kvm_capabilities.?[0], "1") or
                                !std.mem.eql(u8, config.cpu_config.?.msr_modifiers.?[0].addr, "0x1") or
                                !std.mem.eql(u8, config.cpu_config.?.reg_modifiers.?[0].bitmap, "0b0") or
                                config.cpu_config.?.vcpu_features.?[0].index != 0 or
                                config.balloon.?.deflate_on_oom != false or
                                config.balloon.?.free_page_hinting != true or
                                !std.mem.eql(u8, config.vsock.?.uds_path, "/vsock") or
                                config.entropy.?.rate_limiter.?.ops.?.refill_time != 10 or
                                !std.mem.eql(u8, config.mmds_config.?.network_interfaces[0], "eth0") or
                                !std.mem.eql(u8, config.logger.?.log_path.?, "/log") or
                                !std.mem.eql(u8, config.metrics.?.properties.?.map.get("key").?, "value") or
                                !std.mem.eql(u8, config.pmem.?[0].id, "pm0") or
                                config.memory_hotplug.?.total_size_mib != 1024)
                                return error.IncorrectExport;
                        } else if (std.mem.eql(u8, expected, "restored")) {
                            if (config.boot_source != null or config.machine_config.?.smt != null or
                                config.machine_config.?.cpu_template != null or config.drives.?.len != 0 or
                                config.network_interfaces != null or config.cpu_config != null)
                                return error.InventedConfiguration;
                        } else return error.UnexpectedSuccess;
                    },
                    .fault => |fault| {
                        const status: u16 = if (std.mem.eql(u8, expected, "unexpected-status")) 202 else 400;
                        if ((!std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != status or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (machine and std.mem.eql(u8, args[5], "instance")) {
                var instance = client.getInstanceInfo() catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    std.debug.print("Expected instance {s}, got {s}\n", .{ expected, @errorName(err) });
                    return err;
                };
                defer instance.deinit();
                const transition = std.mem.eql(u8, expected, "transition");
                if (transition) {
                    var second = try client.getInstanceInfo();
                    defer second.deinit();
                    switch (second) {
                        .success => |value| if (!std.mem.eql(u8, value.state, "Running") or
                            !std.mem.eql(u8, value.id, "second"))
                            return error.IncorrectLiveState,
                        .fault => return error.UnexpectedFault,
                    }
                }
                result.deinit();
                connected = false;
                switch (instance) {
                    .success => |value| {
                        const state = if (transition) "Not started" else expected;
                        if (!std.mem.eql(u8, value.state, state) or
                            !std.mem.eql(u8, value.id, "vm\"one") or
                            !std.mem.eql(u8, value.vmm_version, "1.17.0+build") or
                            !std.mem.eql(u8, value.app_name, "Firecracker"))
                            return error.IncorrectInstanceInfo;
                    },
                    .fault => |fault| {
                        const status: u16 = if (std.mem.eql(u8, expected, "unexpected-status")) 202 else 400;
                        if ((!std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != status or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (machine and std.mem.eql(u8, args[5], "balloon-hinting-status")) {
                var status = client.getBalloonHintingStatus() catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    return err;
                };
                defer status.deinit();
                result.deinit();
                connected = false;
                switch (status) {
                    .success => |value| {
                        const full = std.mem.eql(u8, expected, "hinting-full");
                        const zero = std.mem.eql(u8, expected, "hinting-zero");
                        if (!full and !zero and !std.mem.eql(u8, expected, "hinting-minimal")) return error.UnexpectedSuccess;
                        if (value.host_cmd != 4294967295 or
                            value.guest_cmd != (if (full) @as(?i64, 42) else if (zero) @as(?i64, 0) else null))
                            return error.IncorrectHintingStatus;
                    },
                    .fault => |fault| {
                        const code: u16 = if (std.mem.eql(u8, expected, "unexpected-status")) 202 else 400;
                        if ((!std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != code or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (machine and std.mem.eql(u8, args[5], "balloon-statistics")) {
                var statistics = client.getBalloonStatistics() catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    return err;
                };
                defer statistics.deinit();
                result.deinit();
                connected = false;
                switch (statistics) {
                    .success => |stats| {
                        var wanted: fc.models.BalloonStatistics = .{
                            .target_pages = 16384,
                            .actual_pages = 8192,
                            .target_mib = 64,
                            .actual_mib = 32,
                        };
                        if (std.mem.eql(u8, expected, "stats-full")) {
                            wanted.swap_in = 9007199254740993;
                            wanted.swap_out = 2;
                            wanted.major_faults = 3;
                            wanted.minor_faults = 4;
                            wanted.free_memory = 5;
                            wanted.total_memory = 6;
                            wanted.available_memory = 7;
                            wanted.disk_caches = 8;
                            wanted.hugetlb_allocations = 9;
                            wanted.hugetlb_failures = 10;
                            wanted.oom_kill = 11;
                            wanted.alloc_stall = 12;
                            wanted.async_scan = 13;
                            wanted.direct_scan = 14;
                            wanted.async_reclaim = 15;
                            wanted.direct_reclaim = 0;
                        } else if (!std.mem.eql(u8, expected, "stats-minimal")) return error.UnexpectedSuccess;
                        if (!std.meta.eql(wanted, stats)) return error.IncorrectStatistics;
                    },
                    .fault => |fault| {
                        const status: u16 = if (std.mem.eql(u8, expected, "unexpected-status")) 202 else 400;
                        if ((!std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != status or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (machine and std.mem.eql(u8, args[5], "balloon-read")) {
                var balloon = client.getBalloon() catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    return err;
                };
                defer balloon.deinit();
                result.deinit();
                connected = false;
                switch (balloon) {
                    .success => |config| {
                        const full = std.mem.eql(u8, expected, "balloon-full");
                        const zero = std.mem.eql(u8, expected, "balloon-zero");
                        if (!full and !zero and !std.mem.eql(u8, expected, "balloon-minimal")) return error.UnexpectedSuccess;
                        if (config.amount_mib != (if (full) @as(i64, 64) else 0) or config.deflate_on_oom != full)
                            return error.IncorrectBalloon;
                        if (config.stats_polling_interval_s != (if (full) @as(?i64, 5) else if (zero) @as(?i64, 0) else null) or
                            config.free_page_hinting != (if (full) @as(?bool, true) else if (zero) @as(?bool, false) else null) or
                            config.free_page_reporting != (if (full) @as(?bool, true) else if (zero) @as(?bool, false) else null))
                            return error.IncorrectBalloonOptions;
                    },
                    .fault => |fault| {
                        const status: u16 = if (std.mem.eql(u8, expected, "unexpected-status")) 202 else 400;
                        if ((!std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != status or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (machine and std.mem.startsWith(u8, args[5], "balloon-")) {
                const full = std.mem.eql(u8, args[5], "balloon-full");
                const explicit = full or std.mem.eql(u8, args[5], "balloon-zero");
                const patch = std.mem.startsWith(u8, args[5], "balloon-patch-");
                const interval = std.mem.startsWith(u8, args[5], "balloon-interval-");
                const hinting_start = std.mem.startsWith(u8, args[5], "balloon-hinting-start");
                const hinting_stop = std.mem.eql(u8, args[5], "balloon-hinting-stop");
                var written = (if (hinting_start) client.startBalloonHinting(.{
                    .acknowledge_on_stop = if (std.mem.endsWith(u8, args[5], "-true")) true else if (std.mem.endsWith(u8, args[5], "-false")) false else null,
                }) else if (hinting_stop) client.stopBalloonHinting() else if (interval) client.patchBalloonStatistics(.{
                    .stats_polling_interval_s = if (std.mem.eql(u8, args[5], "balloon-interval-zero")) 0 else if (std.mem.eql(u8, args[5], "balloon-interval-negative")) -1 else 7,
                }) else if (patch) client.patchBalloon(.{
                    .amount_mib = if (std.mem.eql(u8, args[5], "balloon-patch-zero")) 0 else if (std.mem.eql(u8, args[5], "balloon-patch-negative")) -1 else 32,
                }) else client.putBalloon(.{
                    .amount_mib = if (full) 64 else 0,
                    .deflate_on_oom = full,
                    .stats_polling_interval_s = if (explicit) (if (full) @as(i64, 5) else 0) else null,
                    .free_page_hinting = if (explicit) full else null,
                    .free_page_reporting = if (explicit) full else null,
                })) catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    return err;
                };
                defer written.deinit();
                result.deinit();
                connected = false;
                switch (written) {
                    .success => if (!std.mem.eql(u8, expected, "success")) return error.UnexpectedSuccess,
                    .fault => |fault| {
                        const status: u16 = if (std.mem.eql(u8, expected, "unexpected-status")) 200 else 400;
                        if ((!std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != status or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            const boot = machine and std.mem.startsWith(u8, args[5], "boot-");
            const drive = machine and std.mem.startsWith(u8, args[5], "drive-");
            const network = machine and std.mem.startsWith(u8, args[5], "network-");
            const start = machine and std.mem.eql(u8, args[5], "start");
            const ctrl_alt_del = machine and std.mem.eql(u8, args[5], "ctrl-alt-del");
            const pause = machine and std.mem.eql(u8, args[5], "pause");
            const resume_vm = machine and std.mem.eql(u8, args[5], "resume");
            const snapshot = machine and std.mem.startsWith(u8, args[5], "snapshot-");
            const patch_machine = machine and std.mem.startsWith(u8, args[5], "patch-machine-");
            const patch_drive = machine and std.mem.startsWith(u8, args[5], "patch-drive-");
            const patch_network = machine and std.mem.startsWith(u8, args[5], "patch-network-");
            const cpu = machine and std.mem.startsWith(u8, args[5], "cpu-");
            const observability = machine and (std.mem.startsWith(u8, args[5], "logger-") or
                std.mem.startsWith(u8, args[5], "metrics-") or std.mem.eql(u8, args[5], "flush"));
            if (machine and (patch_network or patch_drive or cpu or patch_machine or snapshot or ctrl_alt_del or pause or resume_vm or observability or network or start or drive or boot or std.mem.startsWith(u8, args[5], "put"))) {
                const full = std.mem.endsWith(u8, args[5], "-full");
                var written = (if (patch_network) client.patchGuestNetworkInterface(networkUpdate(args[5])) else if (patch_drive) client.patchGuestDrive(driveUpdate(args[5])) else if (cpu) client.putCpuConfiguration(cpuRequest(args[5])) else if (patch_machine) client.patchMachineConfiguration(
                    if (std.mem.eql(u8, args[5], "patch-machine-empty")) .{} else if (std.mem.eql(u8, args[5], "patch-machine-memory")) .{
                        .mem_size_mib = 1024,
                    } else .{
                        .vcpu_count = 0,
                        .mem_size_mib = 0,
                        .smt = false,
                        .track_dirty_pages = false,
                        .cpu_template = "",
                        .huge_pages = "quoted\"\\\n",
                    },
                ) else if (snapshot and std.mem.startsWith(u8, args[5], "snapshot-load-")) client.loadSnapshot(snapshotLoadRequest(args[5])) else if (snapshot) client.createSnapshot(.{
                    .mem_file_path = "/snapshots/memory \"quoted\"\\path\n",
                    .snapshot_path = "/snapshots/state with spaces",
                    .snapshot_type = if (full) "Full" else if (std.mem.eql(u8, args[5], "snapshot-diff")) "Diff" else null,
                    .sync_snapshot_files = if (full) true else if (std.mem.eql(u8, args[5], "snapshot-diff")) false else null,
                }) else if (ctrl_alt_del) client.sendCtrlAltDel() else if (pause) client.pauseInstance() else if (resume_vm) client.resumeInstance() else if (observability) writeObservability(client, init.gpa, args[5]) else if (network) client.putGuestNetworkInterface(networkRequest(args[5])) else if (start) client.startInstance() else if (drive) client.putGuestDrive(driveRequest(args[5])) else if (boot) client.putGuestBootSource(.{
                    .kernel_image_path = "/images/kernel \"quoted\"\\path",
                    .boot_args = if (full) "console=ttyS0 key=\"value\"\nnext" else if (std.mem.eql(u8, args[5], "boot-empty")) "" else null,
                    .initrd_path = if (full) "/images/initrd with spaces" else null,
                }) else client.putMachineConfiguration(.{
                    .vcpu_count = 4,
                    .mem_size_mib = 512,
                    .smt = if (full) true else null,
                    .track_dirty_pages = if (full) false else null,
                    .cpu_template = if (full) "T2" else null,
                    .huge_pages = if (full) "2M" else null,
                })) catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    std.debug.print("Expected write {s}, got {s}\n", .{ expected, @errorName(err) });
                    return err;
                };
                defer written.deinit();
                result.deinit();
                connected = false;
                switch (written) {
                    .success => if (!std.mem.eql(u8, expected, "success")) return error.UnexpectedSuccess,
                    .fault => |fault| {
                        const expected_status: u16 = if (std.mem.eql(u8, expected, "unexpected-status")) 200 else 400;
                        if ((!std.mem.eql(u8, expected, "fault") and !std.mem.eql(u8, expected, "unexpected-status")) or
                            fault.status != expected_status or !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (machine) {
                var configuration = client.getMachineConfiguration() catch |err| {
                    if (std.mem.eql(u8, expected, @errorName(err))) return;
                    std.debug.print("Expected machine {s}, got {s}\n", .{ expected, @errorName(err) });
                    return err;
                };
                defer configuration.deinit();
                // Exercise another request while the first response is retained.
                if (std.mem.eql(u8, expected, "full")) {
                    var second = try client.getMachineConfiguration();
                    defer second.deinit();
                    switch (second) {
                        .success => |config| if (config.vcpu_count != 1 or config.mem_size_mib != 128)
                            return error.IncorrectSecondConfiguration,
                        .fault => return error.UnexpectedFault,
                    }
                }
                result.deinit();
                connected = false;
                // Both success strings and fault bodies must outlive the client.
                switch (configuration) {
                    .success => |config| {
                        if (config.vcpu_count != 4 or config.mem_size_mib != 512) return error.IncorrectConfiguration;
                        if (std.mem.eql(u8, expected, "full")) {
                            if (config.smt != true or config.track_dirty_pages != false) return error.IncorrectOptionalFlags;
                            if (!std.mem.eql(u8, config.cpu_template orelse return error.MissingCpuTemplate, "T2") or
                                !std.mem.eql(u8, config.huge_pages orelse return error.MissingHugePages, "2M"))
                                return error.IncorrectOptionalStrings;
                        } else if (std.mem.eql(u8, expected, "minimal")) {
                            if (config.smt != null or config.track_dirty_pages != null or config.cpu_template != null or config.huge_pages != null)
                                return error.InventedOptionalFields;
                        } else return error.UnexpectedSuccess;
                    },
                    .fault => |fault| {
                        if (!std.mem.eql(u8, expected, "fault") or fault.status != 400 or
                            !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                            return error.IncorrectFault;
                    },
                }
                return;
            }
            if (!std.mem.eql(u8, expected, "success")) return error.UnexpectedSuccess;
            const info = client.info();
            if (info.running_version.major != 1 or info.running_version.minor != 17 or
                info.running_version.patch != 0 or info.contract != .v1_17)
                return error.IncorrectMetadata;
        },
        .fault => |fault| {
            if (!std.mem.eql(u8, expected, "fault") or fault.status != 400 or
                !std.mem.eql(u8, fault.body, "{\"fault_message\":\"denied\"}"))
                return error.IncorrectFault;
        },
    }
}

fn cpuRequest(mode: []const u8) fc.models.CpuConfiguration {
    if (std.mem.eql(u8, mode, "cpu-minimal")) return .{};
    if (std.mem.eql(u8, mode, "cpu-empty")) return .{
        .cpuid_modifiers = &.{},
        .msr_modifiers = &.{},
        .reg_modifiers = &.{},
        .vcpu_features = &.{},
        .kvm_capabilities = &.{},
    };
    if (std.mem.eql(u8, mode, "cpu-arm")) return .{
        .reg_modifiers = &.{.{ .addr = "0x603000000013c020", .bitmap = "0bxxxx_0001" }},
        .vcpu_features = &.{.{ .index = 0, .bitmap = "0b1" }},
        .kvm_capabilities = &.{ "121", "!122" },
    };
    if (std.mem.eql(u8, mode, "cpu-invalid")) return .{
        .msr_modifiers = &.{.{ .addr = "", .bitmap = "invalid\"\\\n" }},
    };
    return .{
        .cpuid_modifiers = &.{
            .{ .leaf = "0x1", .subleaf = "0", .flags = 0, .modifiers = &.{
                .{ .register = "ecx", .bitmap = "0bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx0" },
                .{ .register = "edx", .bitmap = "0b1" },
            } },
            .{ .leaf = "0x7", .subleaf = "0x0", .flags = 1, .modifiers = &.{} },
        },
        .msr_modifiers = &.{.{ .addr = "0x10a", .bitmap = "0bxxxx_0001" }},
        .kvm_capabilities = &.{ "121", "!122" },
    };
}

fn networkUpdate(mode: []const u8) fc.models.NetworkInterfaceUpdate {
    if (std.mem.eql(u8, mode, "patch-network-rx")) return .{
        .iface_id = "eth0",
        .rx_rate_limiter = .{ .bandwidth = .{ .size = 1048576, .refill_time = 100 } },
    };
    if (std.mem.eql(u8, mode, "patch-network-tx")) return .{
        .iface_id = "eth0",
        .tx_rate_limiter = .{ .ops = .{ .size = 10, .refill_time = 100, .one_time_burst = 20 } },
    };
    if (std.mem.eql(u8, mode, "patch-network-both")) return .{
        .iface_id = "eth0",
        .rx_rate_limiter = .{ .ops = .{ .size = 5, .refill_time = 50 } },
        .tx_rate_limiter = .{
            .bandwidth = .{ .size = 0, .refill_time = 0, .one_time_burst = 0 },
            .ops = .{ .size = 0, .refill_time = 0 },
        },
    };
    if (std.mem.eql(u8, mode, "patch-network-empty")) return .{
        .iface_id = "",
        .rx_rate_limiter = .{},
    };
    if (std.mem.eql(u8, mode, "patch-network-escaped")) return .{ .iface_id = "eth/other?x#% \"\\\n" };
    if (std.mem.eql(u8, mode, "patch-network-long")) return .{ .iface_id = &@as([600]u8, @splat('x')) };
    return .{ .iface_id = "eth0" };
}

fn driveUpdate(mode: []const u8) fc.models.DriveUpdate {
    if (std.mem.eql(u8, mode, "patch-drive-path")) return .{
        .drive_id = "rootfs",
        .path_on_host = "/images/new \"disk\"\\file",
    };
    if (std.mem.eql(u8, mode, "patch-drive-rate")) return .{
        .drive_id = "rootfs",
        .rate_limiter = .{ .bandwidth = .{ .size = 0, .refill_time = 0 } },
    };
    if (std.mem.eql(u8, mode, "patch-drive-both")) return .{
        .drive_id = "rootfs",
        .path_on_host = "",
        .rate_limiter = .{ .ops = .{ .size = 10, .refill_time = 100, .one_time_burst = 0 } },
    };
    if (std.mem.eql(u8, mode, "patch-drive-escaped")) return .{ .drive_id = "disk/other?x#% " };
    if (std.mem.eql(u8, mode, "patch-drive-long")) return .{ .drive_id = &@as([600]u8, @splat('x')) };
    return .{ .drive_id = "rootfs" };
}

fn driveRequest(mode: []const u8) fc.models.DriveRequest {
    if (std.mem.eql(u8, mode, "drive-full")) return .{
        .drive_id = "data._~-01",
        .is_root_device = false,
        .partuuid = "partition \"quoted\"\\id",
        .cache_type = "Writeback",
        .path_on_host = "/images/data \"quoted\"\\disk\nnext",
        .io_engine = "Async",
        .socket = "/run/vhost \"quoted\"\\socket",
        .is_read_only = false,
        .discard = false,
        .blk_size = 0,
        .rate_limiter = .{
            .bandwidth = .{ .size = 0, .refill_time = 100, .one_time_burst = 0 },
            .ops = .{ .size = 200, .refill_time = 0, .one_time_burst = 300 },
        },
        .topology = .{
            .physical_block_exp = 0,
            .alignment_offset = 1,
            .min_io_size = 0,
            .opt_io_size = 8,
        },
    };
    if (std.mem.eql(u8, mode, "drive-vhost")) return .{
        .drive_id = "vhost0",
        .is_root_device = false,
        .socket = "/run/vhost.sock",
    };
    if (std.mem.eql(u8, mode, "drive-empty")) return .{
        .drive_id = "empty",
        .is_root_device = false,
        .partuuid = "",
        .cache_type = "",
        .path_on_host = "",
        .io_engine = "",
        .socket = "",
        .rate_limiter = .{},
        .topology = .{},
    };
    if (std.mem.eql(u8, mode, "drive-nested")) return .{
        .drive_id = "nested",
        .is_root_device = false,
        .path_on_host = "/images/data.ext4",
        .rate_limiter = .{
            .bandwidth = .{ .size = 0, .refill_time = 0 },
        },
        .topology = .{ .min_io_size = 0 },
    };
    if (std.mem.eql(u8, mode, "drive-escaped")) return .{
        .drive_id = "disk/other?mode=rw#frag %\"\\\n",
        .is_root_device = false,
        .path_on_host = "/images/data.ext4",
    };
    if (std.mem.eql(u8, mode, "drive-empty-id")) return .{
        .drive_id = "",
        .is_root_device = false,
        .path_on_host = "/images/data.ext4",
    };
    return .{
        .drive_id = "rootfs",
        .is_root_device = true,
        .path_on_host = "/images/rootfs.ext4",
    };
}

fn networkRequest(mode: []const u8) fc.models.NetworkInterfaceRequest {
    if (std.mem.eql(u8, mode, "network-full")) return .{
        .iface_id = "eth._~-01",
        .host_dev_name = "tap \"quoted\"\\name",
        .guest_mac = "06:00:00:00:00:01",
        .mtu = 9000,
        .rx_rate_limiter = .{
            .bandwidth = .{ .size = 1000, .refill_time = 100, .one_time_burst = 0 },
            .ops = .{ .size = 0, .refill_time = 0 },
        },
        .tx_rate_limiter = .{
            .ops = .{ .size = 200, .refill_time = 50, .one_time_burst = 300 },
        },
    };
    if (std.mem.eql(u8, mode, "network-empty")) return .{
        .iface_id = "",
        .host_dev_name = "",
        .guest_mac = "",
        .mtu = 0,
        .rx_rate_limiter = .{},
        .tx_rate_limiter = .{},
    };
    if (std.mem.eql(u8, mode, "network-escaped")) return .{
        .iface_id = "net/other?mode=rw#frag %\"\\\n",
        .host_dev_name = "tap0",
    };
    if (std.mem.eql(u8, mode, "network-long")) return .{
        .iface_id = &@as([600]u8, @splat('a')),
        .host_dev_name = "tap0",
    };
    return .{ .iface_id = "eth0", .host_dev_name = "tap0" };
}

fn writeObservability(client: *fc.Client, allocator: std.mem.Allocator, mode: []const u8) !fc.Result(void) {
    if (std.mem.eql(u8, mode, "flush")) return client.flushMetrics();
    const full = std.mem.endsWith(u8, mode, "-full");
    const empty = std.mem.endsWith(u8, mode, "-empty");
    if (std.mem.startsWith(u8, mode, "logger-")) {
        if (!full and !empty) return client.putLogger(.{});
        return client.putLogger(.{
            .log_path = if (empty) "" else "/logs/\"quoted\"\\path\n",
            .level = if (empty) "" else "Debug",
            .show_level = full,
            .show_log_origin = false,
            .module = if (empty) "" else "api_server::request",
        });
    }
    var properties: std.json.ArrayHashMap([]const u8) = .{};
    defer properties.deinit(allocator);
    if (full) {
        try properties.map.put(allocator, "key\"\\\n", "value\"\\\n");
        try properties.map.put(allocator, "empty", "");
    }
    return client.putMetrics(.{
        .metrics_path = if (empty) "" else "/metrics/\"quoted\"\\path\n",
        .emit_id = if (full or empty) full else null,
        .properties = if (full or empty) properties else null,
    });
}

fn snapshotLoadRequest(mode: []const u8) fc.models.SnapshotLoadRequest {
    var request: fc.models.SnapshotLoadRequest = .{
        .snapshot_path = "/snapshots/state \"quoted\"\\path\n",
    };
    if (std.mem.eql(u8, mode, "snapshot-load-missing")) return request;
    const legacy = std.mem.eql(u8, mode, "snapshot-load-legacy");
    const both = std.mem.eql(u8, mode, "snapshot-load-both");
    if (legacy or both) request.mem_file_path = "/snapshots/memory";
    if (legacy) {
        request.enable_diff_snapshots = true;
        return request;
    }
    const uffd = std.mem.eql(u8, mode, "snapshot-load-uffd");
    request.mem_backend = .{
        .backend_type = if (uffd) "Uffd" else "File",
        .backend_path = if (uffd) "/run/uffd.sock" else "/snapshots/memory",
    };
    if (std.mem.eql(u8, mode, "snapshot-load-full") or uffd) {
        request.resume_vm = true;
        request.track_dirty_pages = true;
        request.clock_realtime = true;
        request.huge_pages = if (uffd) "2M" else "None";
        request.network_overrides = &.{
            .{ .iface_id = "eth0", .host_dev_name = "tap\"\\\n" },
            .{ .iface_id = "eth1", .host_dev_name = "tap1" },
        };
        request.vsock_override = .{ .uds_path = "/run/vsock \"quoted\"\\socket" };
    } else if (std.mem.eql(u8, mode, "snapshot-load-false")) {
        request.resume_vm = false;
        request.track_dirty_pages = false;
        request.enable_diff_snapshots = false;
        request.clock_realtime = false;
        request.network_overrides = &.{};
        request.huge_pages = "Snapshot";
    }
    return request;
}

fn deviceWrite(client: *fc.Client, mode: []const u8) !fc.Result(void) {
    const minimal = std.mem.endsWith(u8, mode, "-minimal");
    const empty = std.mem.endsWith(u8, mode, "-empty");
    if (std.mem.startsWith(u8, mode, "vsock-")) return client.putGuestVsock(.{
        .guest_cid = if (empty) 0 else 3,
        .uds_path = if (empty) "" else "/run/vsock \"quoted\"\\socket\n",
        .vsock_id = if (minimal) null else if (empty) "" else "guest",
    });
    if (std.mem.startsWith(u8, mode, "entropy-")) return client.putEntropy(.{
        .rate_limiter = if (minimal) null else if (empty) .{} else .{
            .bandwidth = .{ .size = 0, .refill_time = 10, .one_time_burst = 0 },
            .ops = .{ .size = 20, .refill_time = 0 },
        },
    });
    if (std.mem.startsWith(u8, mode, "serial-")) return client.putSerial(.{
        .serial_out_path = if (minimal or std.mem.endsWith(u8, mode, "-rate")) null else if (empty) "" else "/logs/serial \"quoted\"\\output\n",
        .rate_limiter = if (minimal or empty) null else .{
            .size = 0,
            .refill_time = if (std.mem.endsWith(u8, mode, "-rate")) 0 else 10,
            .one_time_burst = if (std.mem.endsWith(u8, mode, "-rate")) null else 0,
        },
    });
    const long_id = comptime blk: {
        @setEvalBranchQuota(2000);
        var bytes: [1200]u8 = undefined;
        for (&bytes, 0..) |*byte, index| byte.* = if (index % 2 == 0) 'x' else '/';
        break :blk bytes;
    };
    const id = if (empty) "" else if (std.mem.endsWith(u8, mode, "-escaped")) "pmem/other?mode=rw#frag %\"\\\n" else if (std.mem.endsWith(u8, mode, "-long")) &long_id else "pm._~-01";
    const full = std.mem.endsWith(u8, mode, "-full");
    const limiter: ?fc.models.RateLimiter = if (empty) .{} else if (full) .{
        .bandwidth = .{ .size = 0, .refill_time = 0 },
        .ops = .{ .size = 10, .refill_time = 100, .one_time_burst = 0 },
    } else null;
    if (std.mem.startsWith(u8, mode, "pmem-patch-")) return client.patchGuestPmem(.{
        .id = id,
        .rate_limiter = limiter,
    });
    if (std.mem.startsWith(u8, mode, "pmem-put-")) return client.putGuestPmem(.{
        .id = id,
        .path_on_host = if (empty) "" else "/images/pmem \"quoted\"\\disk\n",
        .root_device = if (full or empty) false else null,
        .read_only = if (full) true else if (empty) false else null,
        .rate_limiter = limiter,
    });
    return error.InvalidArguments;
}
