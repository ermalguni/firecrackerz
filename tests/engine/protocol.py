#!/usr/bin/env python3
"""Behavioral connection scenarios; never contacts a production socket."""
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import quote

runner = sys.argv[1]

with tempfile.TemporaryDirectory(prefix="firecrackerz-") as directory:
    root = pathlib.Path(directory)
    binary = root / "firecracker"
    endpoint = str(root / "api.sock")
    drive_requests = {
        "minimal": {
            "drive_id": "rootfs",
            "is_root_device": True,
            "path_on_host": "/images/rootfs.ext4",
        },
        "full": {
            "drive_id": "data._~-01",
            "is_root_device": False,
            "partuuid": 'partition "quoted"\\id',
            "cache_type": "Writeback",
            "path_on_host": '/images/data "quoted"\\disk\nnext',
            "io_engine": "Async",
            "socket": '/run/vhost "quoted"\\socket',
            "is_read_only": False,
            "discard": False,
            "blk_size": 0,
            "rate_limiter": {
                "bandwidth": {"size": 0, "refill_time": 100, "one_time_burst": 0},
                "ops": {"size": 200, "refill_time": 0, "one_time_burst": 300},
            },
            "topology": {
                "physical_block_exp": 0,
                "alignment_offset": 1,
                "min_io_size": 0,
                "opt_io_size": 8,
            },
        },
        "vhost": {
            "drive_id": "vhost0",
            "is_root_device": False,
            "socket": "/run/vhost.sock",
        },
        "empty": {
            "drive_id": "empty",
            "is_root_device": False,
            "partuuid": "",
            "cache_type": "",
            "path_on_host": "",
            "io_engine": "",
            "socket": "",
            "rate_limiter": {},
            "topology": {},
        },
        "nested": {
            "drive_id": "nested",
            "is_root_device": False,
            "path_on_host": "/images/data.ext4",
            "rate_limiter": {"bandwidth": {"size": 0, "refill_time": 0}},
            "topology": {"min_io_size": 0},
        },
        "escaped": {
            "drive_id": 'disk/other?mode=rw#frag %"\\\n',
            "is_root_device": False,
            "path_on_host": "/images/data.ext4",
        },
        "empty-id": {
            "drive_id": "",
            "is_root_device": False,
            "path_on_host": "/images/data.ext4",
        },
    }
    network_requests = {
        "minimal": {"iface_id": "eth0", "host_dev_name": "tap0"},
        "full": {
            "iface_id": "eth._~-01",
            "host_dev_name": 'tap "quoted"\\name',
            "guest_mac": "06:00:00:00:00:01",
            "mtu": 9000,
            "rx_rate_limiter": {
                "bandwidth": {"size": 1000, "refill_time": 100, "one_time_burst": 0},
                "ops": {"size": 0, "refill_time": 0},
            },
            "tx_rate_limiter": {
                "ops": {"size": 200, "refill_time": 50, "one_time_burst": 300},
            },
        },
        "empty": {
            "iface_id": "", "host_dev_name": "", "guest_mac": "", "mtu": 0,
            "rx_rate_limiter": {}, "tx_rate_limiter": {},
        },
        "escaped": {"iface_id": 'net/other?mode=rw#frag %"\\\n', "host_dev_name": "tap0"},
        "long": {"iface_id": "a" * 600, "host_dev_name": "tap0"},
    }

    def executable(output="Firecracker v1.17.0", command=None):
        binary.write_text("#!/bin/sh\n" + (command or "printf '%s\\n' '" + output + "'") + "\n")
        binary.chmod(0o755)

    drive_updates = {
        "path": {"drive_id": "rootfs", "path_on_host": '/images/new "disk"\\file'},
        "rate": {"drive_id": "rootfs", "rate_limiter": {"bandwidth": {"size": 0, "refill_time": 0}}},
        "both": {"drive_id": "rootfs", "path_on_host": "", "rate_limiter": {"ops": {"size": 10, "refill_time": 100, "one_time_burst": 0}}},
        "id": {"drive_id": "rootfs"},
        "escaped": {"drive_id": "disk/other?x#% "},
        "long": {"drive_id": "x" * 600},
    }

    network_updates = {
        "rx": {"iface_id": "eth0", "rx_rate_limiter": {"bandwidth": {"size": 1048576, "refill_time": 100}}},
        "tx": {"iface_id": "eth0", "tx_rate_limiter": {"ops": {"size": 10, "refill_time": 100, "one_time_burst": 20}}},
        "both": {
            "iface_id": "eth0",
            "rx_rate_limiter": {"ops": {"size": 5, "refill_time": 50}},
            "tx_rate_limiter": {
                "bandwidth": {"size": 0, "refill_time": 0, "one_time_burst": 0},
                "ops": {"size": 0, "refill_time": 0},
            },
        },
        "empty": {"iface_id": "", "rx_rate_limiter": {}},
        "id": {"iface_id": "eth0"},
        "escaped": {"iface_id": 'eth/other?x#% "\\\n'},
        "long": {"iface_id": "x" * 600},
    }

    device_requests = {
        "vsock-minimal": {"guest_cid": 3, "uds_path": '/run/vsock "quoted"\\socket\n'},
        "vsock-full": {"guest_cid": 3, "uds_path": '/run/vsock "quoted"\\socket\n', "vsock_id": "guest"},
        "vsock-empty": {"guest_cid": 0, "uds_path": "", "vsock_id": ""},
        "entropy-minimal": {},
        "entropy-empty": {"rate_limiter": {}},
        "entropy-full": {"rate_limiter": {
            "bandwidth": {"size": 0, "refill_time": 10, "one_time_burst": 0},
            "ops": {"size": 20, "refill_time": 0},
        }},
        "serial-minimal": {},
        "serial-rate": {"rate_limiter": {"size": 0, "refill_time": 0}},
        "serial-empty": {"serial_out_path": ""},
        # Serial takes a TokenBucket directly, not bandwidth/ops wrappers.
        "serial-full": {"serial_out_path": '/logs/serial "quoted"\\output\n',
                        "rate_limiter": {"size": 0, "refill_time": 10, "one_time_burst": 0}},
    }
    for operation in ("put", "patch"):
        for variant in ("minimal", "full", "empty", "escaped", "long"):
            identifier = {"empty": "", "escaped": 'pmem/other?mode=rw#frag %"\\\n',
                          "long": "x/" * 600}.get(variant, "pm._~-01")
            configuration = {"id": identifier}
            if operation == "put":
                configuration["path_on_host"] = "" if variant == "empty" else '/images/pmem "quoted"\\disk\n'
                if variant in ("full", "empty"):
                    configuration.update(root_device=False, read_only=variant == "full")
            if variant == "empty":
                configuration["rate_limiter"] = {}
            elif variant == "full":
                configuration["rate_limiter"] = {
                    "bandwidth": {"size": 0, "refill_time": 0},
                    "ops": {"size": 10, "refill_time": 100, "one_time_burst": 0},
                }
            device_requests[f"pmem-{operation}-{variant}"] = configuration

    def run(expected, body=None, status=200, raw=None, delay=0, search=False, machine=False, put=None, boot=None, drive=None, start=False, instance=False, network=None, observability=None, vm=None, ctrl_alt_del=False, snapshot=None, export=False, patch_machine=None, cpu=None, patch_drive=None, patch_network=None, balloon=None, hotplug=None, device=None):
        machine = machine or device is not None or hotplug is not None or balloon is not None or put is not None or boot is not None or drive is not None or start or instance or network is not None or observability is not None or vm is not None or ctrl_alt_del or snapshot is not None or export or patch_machine is not None or cpu is not None or patch_drive is not None or patch_network is not None
        failures = []
        client_finished = threading.Event() if device or hotplug or balloon or start or network or observability or vm or ctrl_alt_del or snapshot or patch_machine or cpu or patch_drive or patch_network else None
        if body is not None or raw is not None or delay:
            server = socket.socket(socket.AF_UNIX)
            server.bind(endpoint)
            server.listen(1)
            server.settimeout(3)

            def serve():
                try:
                    path = "/" if instance else "/actions" if start or ctrl_alt_del else "/drives/" + quote(drive_requests[drive]["drive_id"], safe="") if drive else "/boot-source" if boot else "/machine-config" if machine else "/version"
                    if network:
                        path = "/network-interfaces/" + quote(network_requests[network]["iface_id"], safe="")
                    if observability:
                        path = "/actions" if observability == "flush" else "/" + observability.split("-")[0]
                    if vm:
                        path = "/vm"
                    if snapshot:
                        path = "/snapshot/load" if snapshot.startswith("load-") else "/snapshot/create"
                    if export:
                        path = "/vm/config"
                    if cpu:
                        path = "/cpu-config"
                    if patch_drive:
                        path = "/drives/" + quote(drive_updates[patch_drive]["drive_id"], safe="")
                    if patch_network:
                        path = "/network-interfaces/" + quote(network_updates[patch_network]["iface_id"], safe="")
                    if balloon:
                        path = "/balloon/statistics" if balloon == "statistics" or balloon.startswith("interval-") else "/balloon"
                        if balloon.startswith("hinting-"):
                            path = "/balloon/hinting/" + balloon.split("-")[1]
                    if hotplug:
                        path = "/hotplug/memory"
                    if device:
                        path = "/pmem/" + quote(device_requests[device]["id"], safe="") if device.startswith("pmem-") else "/" + device.split("-")[0]
                    responses = [(path, body, status, raw, delay)]
                    if machine:
                        responses.insert(0, ("/version", '{"firecracker_version":"1.17.0"}', 200, None, 0))
                        if expected == "full":
                            responses.append(("/machine-config", '{"vcpu_count":1,"mem_size_mib":128}', 200, None, 0))
                        if instance and expected == "transition":
                            responses.append(("/", '{"id":"second","state":"Running","vmm_version":"1.17.0","app_name":"Firecracker"}', 200, None, 0))
                        if export and expected == "resources":
                            responses.append(("/vm/config", "{}", 200, None, 0))
                    for path, response_body, response_status, response_raw, response_delay in responses:
                        connection, _ = server.accept()
                        with connection:
                            request = b""
                            while b"\r\n\r\n" not in request:
                                chunk = connection.recv(4096)
                                if not chunk:
                                    raise AssertionError("client disconnected before request")
                                request += chunk
                            method = "PUT" if (balloon or cpu or put or boot or drive or start or network or observability or ctrl_alt_del or snapshot) and path != "/version" else "GET"
                            if balloon in ("read", "statistics"):
                                method = "GET"
                            if balloon and balloon.startswith("patch-") and path == "/balloon":
                                method = "PATCH"
                            if balloon and balloon.startswith("interval-") and path == "/balloon/statistics":
                                method = "PATCH"
                            if balloon and balloon.startswith("hinting-") and path != "/version":
                                method = "GET" if balloon == "hinting-status" else "PATCH"
                            if (vm and path == "/vm") or (patch_machine and path == "/machine-config") or (patch_drive and path.startswith("/drives/")) or (patch_network and path.startswith("/network-interfaces/")):
                                method = "PATCH"
                            if hotplug and path == "/hotplug/memory":
                                method = "GET" if hotplug == "read" else "PATCH" if hotplug.startswith("patch-") else "PUT"
                            if device and path != "/version":
                                method = "PATCH" if device.startswith("pmem-patch-") else "PUT"
                            assert request.startswith(f"{method} {path} HTTP/1.1\r\n".encode()), request
                            if method in ("PUT", "PATCH"):
                                header_block, request_body = request.split(b"\r\n\r\n", 1)
                                headers = dict(line.split(b":", 1) for line in header_block.lower().split(b"\r\n")[1:])
                                assert headers[b"content-type"].strip() == b"application/json"
                                size = int(headers[b"content-length"])
                                while len(request_body) < size:
                                    chunk = connection.recv(size - len(request_body))
                                    assert chunk, "truncated PUT body"
                                    request_body += chunk
                                configuration = request_body if balloon == "hinting-stop" else json.loads(request_body)
                                if snapshot and snapshot.startswith("load-"):
                                    wanted = {"snapshot_path": '/snapshots/state "quoted"\\path\n'}
                                    if snapshot in ("load-legacy", "load-both"):
                                        wanted["mem_file_path"] = "/snapshots/memory"
                                    if snapshot == "load-legacy":
                                        wanted["enable_diff_snapshots"] = True
                                    elif snapshot != "load-missing":
                                        uffd = snapshot == "load-uffd"
                                        wanted["mem_backend"] = {
                                            "backend_type": "Uffd" if uffd else "File",
                                            "backend_path": "/run/uffd.sock" if uffd else "/snapshots/memory",
                                        }
                                        if snapshot == "load-full" or uffd:
                                            wanted.update(
                                                resume_vm=True, track_dirty_pages=True, clock_realtime=True,
                                                huge_pages="2M" if uffd else "None",
                                                network_overrides=[
                                                    {"iface_id": "eth0", "host_dev_name": 'tap"\\\n'},
                                                    {"iface_id": "eth1", "host_dev_name": "tap1"},
                                                ],
                                                vsock_override={"uds_path": '/run/vsock "quoted"\\socket'},
                                            )
                                        elif snapshot == "load-false":
                                            wanted.update(resume_vm=False, track_dirty_pages=False,
                                                          enable_diff_snapshots=False, clock_realtime=False,
                                                          network_overrides=[], huge_pages="Snapshot")
                                elif snapshot:
                                    wanted = {
                                        "mem_file_path": '/snapshots/memory "quoted"\\path\n',
                                        "snapshot_path": "/snapshots/state with spaces",
                                    }
                                    if snapshot != "minimal":
                                        wanted.update(snapshot_type="Full" if snapshot == "full" else "Diff",
                                                      sync_snapshot_files=snapshot == "full")
                                elif device:
                                    wanted = device_requests[device]
                                elif vm:
                                    wanted = {"state": "Paused" if vm == "pause" else "Resumed"}
                                elif ctrl_alt_del:
                                    wanted = {"action_type": "SendCtrlAltDel"}
                                elif start:
                                    wanted = {"action_type": "InstanceStart"}
                                elif observability == "flush":
                                    wanted = {"action_type": "FlushMetrics"}
                                elif observability and observability.startswith("logger-"):
                                    wanted = {}
                                    if observability != "logger-minimal":
                                        empty = observability == "logger-empty"
                                        wanted = {
                                            "log_path": "" if empty else '/logs/"quoted"\\path\n',
                                            "level": "" if empty else "Debug",
                                            "show_level": not empty,
                                            "show_log_origin": False,
                                            "module": "" if empty else "api_server::request",
                                        }
                                elif observability and observability.startswith("metrics-"):
                                    empty = observability == "metrics-empty"
                                    wanted = {"metrics_path": "" if empty else '/metrics/"quoted"\\path\n'}
                                    if observability != "metrics-minimal":
                                        wanted.update(emit_id=not empty, properties={} if empty else {
                                            'key"\\\n': 'value"\\\n', "empty": "",
                                        })
                                elif network:
                                    wanted = network_requests[network]
                                elif patch_network:
                                    wanted = network_updates[patch_network]
                                elif patch_drive:
                                    wanted = drive_updates[patch_drive]
                                elif drive:
                                    wanted = drive_requests[drive]
                                elif boot:
                                    wanted = {"kernel_image_path": '/images/kernel "quoted"\\path'}
                                    if boot == "full":
                                        wanted.update(boot_args='console=ttyS0 key="value"\nnext', initrd_path="/images/initrd with spaces")
                                    elif boot == "empty":
                                        wanted["boot_args"] = ""
                                elif patch_machine:
                                    wanted = {} if patch_machine == "empty" else {"mem_size_mib": 1024} if patch_machine == "memory" else {
                                        "vcpu_count": 0, "mem_size_mib": 0, "smt": False,
                                        "track_dirty_pages": False, "cpu_template": "", "huge_pages": 'quoted"\\\n',
                                    }
                                elif cpu:
                                    wanted = cpu_requests[cpu]
                                elif hotplug:
                                    if hotplug.startswith("patch-"):
                                        wanted = {} if hotplug == "patch-empty" else {"requested_size_mib": 0 if hotplug == "patch-zero" else -1 if hotplug == "patch-negative" else 256}
                                    else:
                                        wanted = {} if hotplug == "put-empty" else {"total_size_mib": 0 if hotplug == "put-zero" else -1 if hotplug == "put-negative" else 1024}
                                        if hotplug in ("put-full", "put-zero"):
                                            wanted.update(slot_size_mib=128 if hotplug == "put-full" else 0, block_size_mib=2 if hotplug == "put-full" else 0)
                                elif balloon == "hinting-stop":
                                    wanted = b""
                                elif balloon and balloon.startswith("hinting-start"):
                                    wanted = {} if balloon == "hinting-start" else {"acknowledge_on_stop": balloon.endswith("-true")}
                                elif balloon and balloon.startswith("interval-"):
                                    wanted = {"stats_polling_interval_s": 0 if balloon == "interval-zero" else -1 if balloon == "interval-negative" else 7}
                                elif balloon and balloon.startswith("patch-"):
                                    wanted = {"amount_mib": 0 if balloon == "patch-zero" else -1 if balloon == "patch-negative" else 32}
                                elif balloon:
                                    wanted = {"amount_mib": 64 if balloon == "full" else 0, "deflate_on_oom": balloon == "full"}
                                    if balloon != "minimal":
                                        wanted.update(stats_polling_interval_s=5 if balloon == "full" else 0,
                                                      free_page_hinting=balloon == "full", free_page_reporting=balloon == "full")
                                else:
                                    wanted = {"vcpu_count": 4, "mem_size_mib": 512}
                                    if put == "full":
                                        wanted.update(smt=True, track_dirty_pages=False, cpu_template="T2", huge_pages="2M")
                                assert configuration == wanted, configuration
                            time.sleep(response_delay)
                            data = response_body.encode() if response_body is not None else b""
                            response = response_raw if response_raw is not None else (
                                f"HTTP/1.1 {response_status} Response\r\nContent-Length: {len(data)}\r\nConnection: close\r\n\r\n".encode() + data
                            )
                            try:
                                connection.sendall(response)
                            except BrokenPipeError:
                                if not response_delay:
                                    raise
                    if client_finished:
                        # Keep the listener alive until the client exits so queued retries
                        # cannot disappear when the expected response closes.
                        client_finished.wait()
                        server.settimeout(0)
                        try:
                            extra, _ = server.accept()
                        except BlockingIOError:
                            pass
                        else:
                            extra.close()
                            raise AssertionError("write automatically retried")
                except Exception as error:
                    failures.append(error)
                finally:
                    server.close()

            worker = threading.Thread(target=serve)
            worker.start()
        else:
            worker = None
        try:
            command = [runner, endpoint, str(root if search else binary), expected,
                       "search" if search else "explicit"]
            if machine:
                command.append("ctrl-alt-del" if ctrl_alt_del else vm if vm else observability if observability else "network-" + network if network else "instance" if instance else "start" if start else "drive-" + drive if drive else "boot-" + boot if boot else "put-" + put if put else "machine")
                if snapshot:
                    command[-1] = "snapshot-" + snapshot
                if export:
                    command[-1] = "vm-config"
                if patch_machine:
                    command[-1] = "patch-machine-" + patch_machine
                if cpu:
                    command[-1] = "cpu-" + cpu
                if patch_drive:
                    command[-1] = "patch-drive-" + patch_drive
                if patch_network:
                    command[-1] = "patch-network-" + patch_network
                if balloon:
                    command[-1] = "balloon-" + balloon
                if hotplug:
                    command[-1] = "hotplug-" + hotplug
                if device:
                    command[-1] = "device-" + device
            subprocess.run(command, check=True, timeout=5)
        finally:
            if client_finished:
                client_finished.set()
            if worker:
                worker.join()
                pathlib.Path(endpoint).unlink()
        if failures:
            raise failures[0]
        if device:
            print("PASS device-" + device, expected)
        if hotplug:
            print("PASS hotplug-" + hotplug, expected)
        if balloon:
            print("PASS balloon-" + balloon, expected)
        if patch_network:
            print("PASS patch-network-" + patch_network, expected)
        if patch_drive:
            print("PASS patch-drive-" + patch_drive, expected)
        if cpu:
            print("PASS cpu-" + cpu, expected)
        if patch_machine:
            print("PASS patch-machine-" + patch_machine, expected)
        if export:
            print("PASS vm-config", expected)
        if snapshot:
            print("PASS snapshot-" + snapshot, expected)
        print("PASS", "ctrl-alt-del" if ctrl_alt_del else vm if vm else observability if observability else "network-" + network if network else "instance" if instance else "start" if start else "drive-" + drive if drive else "boot" if boot else "put" if put else "machine" if machine else "connection", expected, "PATH" if search else "explicit")

    executable()
    cpu_requests = {
        "minimal": {},
        "empty": {key: [] for key in ("cpuid_modifiers", "msr_modifiers", "reg_modifiers", "vcpu_features", "kvm_capabilities")},
        "x86": {
            "cpuid_modifiers": [
                {"leaf": "0x1", "subleaf": "0", "flags": 0, "modifiers": [
                    {"register": "ecx", "bitmap": "0bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx0"},
                    {"register": "edx", "bitmap": "0b1"},
                ]},
                {"leaf": "0x7", "subleaf": "0x0", "flags": 1, "modifiers": []},
            ],
            "msr_modifiers": [{"addr": "0x10a", "bitmap": "0bxxxx_0001"}],
            "kvm_capabilities": ["121", "!122"],
        },
        "arm": {
            "reg_modifiers": [{"addr": "0x603000000013c020", "bitmap": "0bxxxx_0001"}],
            "vcpu_features": [{"index": 0, "bitmap": "0b1"}],
            "kvm_capabilities": ["121", "!122"],
        },
        "invalid": {"msr_modifiers": [{"addr": "", "bitmap": 'invalid"\\\n'}]},
    }
    for mode in ("minimal", "empty", "x86", "arm"):
        run("success", "", status=204, cpu=mode)
    run("fault", '{"fault_message":"denied"}', status=400, cpu="invalid")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, cpu="x86")
    run("Timeout", delay=0.4, cpu="x86")
    run("EndOfStream", raw=b"", cpu="x86")
    run("ResponseTooLarge", "x" * (65536 + 1), cpu="x86")
    run("success", "", status=204, patch_machine="memory")
    run("success", "", status=204, patch_machine="empty")
    run("fault", '{"fault_message":"denied"}', status=400, patch_machine="explicit")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, patch_machine="memory")
    run("Timeout", delay=0.4, patch_machine="memory")
    run("EndOfStream", raw=b"", patch_machine="memory")
    run("ResponseTooLarge", "x" * (65536 + 1), patch_machine="memory")
    resources = {
        "boot-source": {"kernel_image_path": "/kernel"},
        "machine-config": {"vcpu_count": 2, "mem_size_mib": 256},
        "drives": [{"drive_id": "root", "is_root_device": True, "path_on_host": "/disk",
                    "rate_limiter": {"bandwidth": {"size": 0, "refill_time": 0}},
                    "topology": {"min_io_size": 0}}],
        "network-interfaces": [{"iface_id": "eth0", "host_dev_name": "tap0"}],
        "cpu-config": {
            "cpuid_modifiers": [{"leaf": "0x1", "subleaf": "0x0", "flags": 0,
                                 "modifiers": [{"register": "eax", "bitmap": "0b1"}]}],
            "kvm_capabilities": ["1"],
            "msr_modifiers": [{"addr": "0x1", "bitmap": "0b1"}],
            "reg_modifiers": [{"addr": "0x2", "bitmap": "0b0"}],
            "vcpu_features": [{"index": 0, "bitmap": "0b1"}],
        },
        "balloon": {"amount_mib": 0, "deflate_on_oom": False, "free_page_hinting": True},
        "vsock": {"guest_cid": 3, "uds_path": "/vsock"},
        "entropy": {"rate_limiter": {"ops": {"size": 1, "refill_time": 10}}},
        "mmds-config": {"network_interfaces": ["eth0"], "version": "V2"},
        "logger": {"log_path": "/log"},
        "metrics": {"metrics_path": "/metrics", "properties": {"key": "value"}},
        "pmem": [{"id": "pm0", "path_on_host": "/pmem"}],
        "memory-hotplug": {"total_size_mib": 1024},
        "future-field": {"ignored": True},
    }
    run("resources", json.dumps(resources), export=True)
    run("restored", json.dumps({"boot-source": None, "machine-config": {
        "vcpu_count": 2, "mem_size_mib": 256, "smt": None, "cpu_template": None},
        "drives": []}), export=True)
    run("MissingField", '{"drives":[{"drive_id":"bad"}]}', export=True)
    run("UnexpectedToken", '{"network-interfaces":42}', export=True)
    run("SyntaxError", "{broken", export=True)
    run("fault", '{"fault_message":"denied"}', status=400, export=True)
    run("unexpected-status", '{"fault_message":"denied"}', status=202, export=True)
    run("Timeout", delay=0.4, export=True)
    run("EndOfStream", raw=b"", export=True)
    run("ResponseTooLarge", "x" * (65536 + 1), export=True)
    run("success", '{"firecracker_version":"1.17.0"}')
    run("success", raw=(
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        b"20\r\n{\"firecracker_version\":\"1.17.0\"}\r\n0\r\n\r\n"
    ))
    run("success", '{"firecracker_version":"1.17.0+build"}', search=True)
    run("VersionMismatch", '{"firecracker_version":"1.18.0"}')
    run("fault", '{"fault_message":"denied"}', status=400)
    run("SyntaxError", '{broken')
    run("Timeout", delay=0.4)
    run("ResponseTooLarge", 'x' * (65536 + 1))
    run("FileNotFound")
    instance_info = {"id": 'vm"one', "state": "Not started", "vmm_version": "1.17.0+build", "app_name": "Firecracker"}
    run("transition", json.dumps(instance_info), instance=True)
    for state in ("Running", "Paused", "Future state"):
        run(state, json.dumps(dict(instance_info, state=state, additional_field=True)), instance=True)
    for field in instance_info:
        missing = dict(instance_info)
        del missing[field]
        run("MissingField", json.dumps(missing), instance=True)
        run("UnexpectedToken", json.dumps(dict(instance_info, **{field: None})), instance=True)
    run("UnexpectedToken", json.dumps(dict(instance_info, state=42)), instance=True)
    run("SyntaxError", "{broken", instance=True)
    run("fault", '{"fault_message":"denied"}', status=400, instance=True)
    run("unexpected-status", '{"fault_message":"denied"}', status=202, instance=True)
    run("Timeout", delay=0.4, instance=True)
    run("EndOfStream", raw=b"", instance=True)
    run("ResponseTooLarge", "x" * (65536 + 1), instance=True)
    run("full", '{"vcpu_count":4,"mem_size_mib":512,"smt":true,"track_dirty_pages":false,"cpu_template":"T2","huge_pages":"2M"}', machine=True)
    run("minimal", '{"vcpu_count":4,"mem_size_mib":512}', machine=True)
    run("fault", '{"fault_message":"denied"}', status=400, machine=True)
    run("MissingField", '{"vcpu_count":4}', machine=True)
    run("SyntaxError", '{broken', machine=True)
    run("Timeout", delay=0.4, machine=True)
    run("ResponseTooLarge", 'x' * (65536 + 1), machine=True)
    run("EndOfStream", raw=b"", machine=True)
    run("success", "", status=204, put="minimal")
    run("success", "", status=204, put="full")
    run("fault", '{"fault_message":"denied"}', status=400, put="minimal")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, put="minimal")
    run("Timeout", delay=0.4, put="minimal")
    run("EndOfStream", raw=b"", put="minimal")
    run("ResponseTooLarge", 'x' * (65536 + 1), status=400, put="minimal")
    run("success", "", status=204, boot="minimal")
    run("success", "", status=204, boot="full")
    run("success", "", status=204, boot="empty")
    run("fault", '{"fault_message":"denied"}', status=400, boot="minimal")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, boot="minimal")
    run("Timeout", delay=0.4, boot="minimal")
    run("EndOfStream", raw=b"", boot="minimal")
    run("ResponseTooLarge", 'x' * (65536 + 1), status=400, boot="minimal")
    for mode in network_updates:
        run("success", "", status=204, patch_network=mode)
    run("fault", '{"fault_message":"denied"}', status=400, patch_network="rx")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, patch_network="tx")
    run("Timeout", delay=0.4, patch_network="both")
    run("EndOfStream", raw=b"", patch_network="rx")
    run("ResponseTooLarge", "x" * (65536 + 1), status=400, patch_network="tx")
    for mode in drive_updates:
        run("success", "", status=204, patch_drive=mode)
    run("fault", '{"fault_message":"denied"}', status=400, patch_drive="path")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, patch_drive="path")
    run("Timeout", delay=0.4, patch_drive="rate")
    run("EndOfStream", raw=b"", patch_drive="path")
    run("ResponseTooLarge", "x" * (65536 + 1), status=400, patch_drive="id")
    run("success", "", status=204, drive="minimal")
    run("success", "", status=204, drive="full")
    run("success", "", status=204, drive="vhost")
    run("success", "", status=204, drive="empty")
    run("success", "", status=204, drive="nested")
    run("fault", '{"fault_message":"denied"}', status=400, drive="escaped")
    run("fault", '{"fault_message":"denied"}', status=400, drive="empty-id")
    run("fault", '{"fault_message":"denied"}', status=400, drive="minimal")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, drive="minimal")
    run("Timeout", delay=0.4, drive="minimal")
    run("EndOfStream", raw=b"", drive="minimal")
    run("ResponseTooLarge", 'x' * (65536 + 1), status=400, drive="minimal")
    run("success", "", status=204, network="minimal")
    run("success", "", status=204, network="full")
    for mode in ("empty", "escaped", "long", "minimal"):
        run("fault", '{"fault_message":"denied"}', status=400, network=mode)
    run("unexpected-status", '{"fault_message":"denied"}', status=200, network="minimal")
    run("Timeout", delay=0.4, network="minimal")
    run("EndOfStream", raw=b"", network="minimal")
    run("ResponseTooLarge", "x" * (65536 + 1), status=400, network="minimal")
    run("success", "", status=204, start=True)
    run("fault", '{"fault_message":"denied"}', status=400, start=True)
    run("unexpected-status", '{"fault_message":"denied"}', status=200, start=True)
    run("Timeout", delay=0.4, start=True)
    run("EndOfStream", raw=b"", start=True)
    run("ResponseTooLarge", 'x' * (65536 + 1), status=400, start=True)
    run("success", "", status=204, ctrl_alt_del=True)
    run("fault", '{"fault_message":"denied"}', status=400, ctrl_alt_del=True)
    run("unexpected-status", '{"fault_message":"denied"}', status=200, ctrl_alt_del=True)
    run("Timeout", delay=0.4, ctrl_alt_del=True)
    run("EndOfStream", raw=b"", ctrl_alt_del=True)
    run("ResponseTooLarge", "x" * (65536 + 1), status=400, ctrl_alt_del=True)
    for operation in ("pause", "resume"):
        run("success", "", status=204, vm=operation)
        run("fault", '{"fault_message":"denied"}', status=400, vm=operation)
        run("unexpected-status", '{"fault_message":"denied"}', status=200, vm=operation)
        run("Timeout", delay=0.4, vm=operation)
        run("EndOfStream", raw=b"", vm=operation)
        run("ResponseTooLarge", "x" * (65536 + 1), status=400, vm=operation)
    for variant in ("minimal", "full", "diff"):
        run("success", "", status=204, snapshot=variant)
    run("fault", '{"fault_message":"denied"}', status=400, snapshot="diff")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, snapshot="full")
    run("Timeout", delay=0.4, snapshot="diff")
    run("EndOfStream", raw=b"", snapshot="full")
    for variant in ("load-minimal", "load-full", "load-uffd", "load-legacy", "load-false"):
        run("success", "", status=204, snapshot=variant)
    for variant in ("load-missing", "load-both", "load-minimal"):
        run("fault", '{"fault_message":"denied"}', status=400, snapshot=variant)
    run("unexpected-status", '{"fault_message":"denied"}', status=200, snapshot="load-full")
    run("Timeout", delay=0.4, snapshot="load-full")
    run("EndOfStream", raw=b"", snapshot="load-full")
    run("ResponseTooLarge", "x" * (65536 + 1), status=400, snapshot="load-minimal")
    for operation in ("logger", "metrics"):
        for variant in ("minimal", "full", "empty"):
            run("success", "", status=204, observability=operation + "-" + variant)
    for operation in ("logger-minimal", "metrics-minimal", "flush"):
        if operation == "flush":
            run("success", "", status=204, observability=operation)
        run("fault", '{"fault_message":"denied"}', status=400, observability=operation)
        run("unexpected-status", '{"fault_message":"denied"}', status=200, observability=operation)
        run("Timeout", delay=0.4, observability=operation)
        run("EndOfStream", raw=b"", observability=operation)
        run("ResponseTooLarge", "x" * (65536 + 1), status=400, observability=operation)
    for variant in ("minimal", "full", "zero"):
        run("success", "", status=204, balloon=variant)
    run("fault", '{"fault_message":"denied"}', status=400, balloon="minimal")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, balloon="minimal")
    run("Timeout", delay=0.4, balloon="minimal")
    run("EndOfStream", raw=b"", balloon="minimal")
    run("ResponseTooLarge", "x" * (65536 + 1), status=400, balloon="minimal")
    run("balloon-minimal", '{"amount_mib":0,"deflate_on_oom":false,"future":{"ignored":true}}', balloon="read")
    run("balloon-full", '{"amount_mib":64,"deflate_on_oom":true,"stats_polling_interval_s":5,"free_page_hinting":true,"free_page_reporting":true}', balloon="read")
    run("balloon-zero", '{"amount_mib":0,"deflate_on_oom":false,"stats_polling_interval_s":0,"free_page_hinting":false,"free_page_reporting":false}', balloon="read")
    run("balloon-minimal", '{"amount_mib":0,"deflate_on_oom":false,"stats_polling_interval_s":null,"free_page_hinting":null,"free_page_reporting":null}', balloon="read")
    for body in ('{"amount_mib":0}', '{"deflate_on_oom":false}'):
        run("MissingField", body, balloon="read")
    run("UnexpectedToken", '{"amount_mib":false,"deflate_on_oom":false}', balloon="read")
    run("SyntaxError", "{!", balloon="read")
    run("fault", '{"fault_message":"denied"}', status=400, balloon="read")
    run("unexpected-status", '{"fault_message":"denied"}', status=202, balloon="read")
    run("Timeout", delay=0.4, balloon="read")
    run("EndOfStream", raw=b"", balloon="read")
    run("ResponseTooLarge", "x" * (65536 + 1), balloon="read")
    for variant in ("patch-size", "patch-zero"):
        run("success", "", status=204, balloon=variant)
    run("fault", '{"fault_message":"denied"}', status=400, balloon="patch-negative")
    run("unexpected-status", '{"fault_message":"denied"}', status=200, balloon="patch-size")
    run("Timeout", delay=0.4, balloon="patch-size")
    run("EndOfStream", raw=b"", balloon="patch-size")
    run("ResponseTooLarge", "x" * (65536 + 1), status=400, balloon="patch-size")
    stats = {"target_pages": 16384, "actual_pages": 8192, "target_mib": 64, "actual_mib": 32}
    run("stats-minimal", json.dumps(stats), balloon="statistics")
    counters = dict(swap_in=9007199254740993, swap_out=2, major_faults=3, minor_faults=4,
                    free_memory=5, total_memory=6, available_memory=7, disk_caches=8,
                    hugetlb_allocations=9, hugetlb_failures=10, oom_kill=11, alloc_stall=12,
                    async_scan=13, direct_scan=14, async_reclaim=15, direct_reclaim=0)
    run("stats-full", json.dumps(stats | counters | {"future": {"ignored": True}}), balloon="statistics")
    run("stats-minimal", json.dumps(stats | dict.fromkeys(counters)), balloon="statistics")
    for missing in stats:
        run("MissingField", json.dumps({k: v for k, v in stats.items() if k != missing}), balloon="statistics")
    run("UnexpectedToken", json.dumps(stats | {"swap_in": False}), balloon="statistics")
    run("SyntaxError", "{!", balloon="statistics")
    run("fault", '{"fault_message":"denied"}', status=400, balloon="statistics")
    run("unexpected-status", '{"fault_message":"denied"}', status=202, balloon="statistics")
    run("Timeout", delay=0.4, balloon="statistics")
    run("EndOfStream", raw=b"", balloon="statistics")
    run("ResponseTooLarge", "x" * (65536 + 1), balloon="statistics")
    run("success", "", status=204, balloon="interval-positive")
    for variant in ("interval-zero", "interval-negative"):
        run("fault", '{"fault_message":"denied"}', status=400, balloon=variant)
    run("unexpected-status", '{"fault_message":"denied"}', status=200, balloon="interval-positive")
    run("Timeout", delay=0.4, balloon="interval-positive")
    run("EndOfStream", raw=b"", balloon="interval-positive")
    run("ResponseTooLarge", "x" * (65536 + 1), status=400, balloon="interval-positive")
    for operation in ("hinting-start", "hinting-start-true", "hinting-start-false", "hinting-stop"):
        run("success", "", status=204, balloon=operation)
    for operation in ("hinting-start", "hinting-stop", "hinting-status"):
        run("fault", '{"fault_message":"denied"}', status=400, balloon=operation)
        run("unexpected-status", '{"fault_message":"denied"}', status=202 if operation == "hinting-status" else 200, balloon=operation)
        run("Timeout", delay=0.4, balloon=operation)
        run("EndOfStream", raw=b"", balloon=operation)
        run("ResponseTooLarge", "x" * (65536 + 1), status=400, balloon=operation)
    run("hinting-minimal", '{"host_cmd":4294967295}', balloon="hinting-status")
    run("hinting-minimal", '{"host_cmd":4294967295,"guest_cmd":null}', balloon="hinting-status")
    run("hinting-full", '{"host_cmd":4294967295,"guest_cmd":42,"future":true}', balloon="hinting-status")
    run("hinting-zero", '{"host_cmd":4294967295,"guest_cmd":0}', balloon="hinting-status")
    run("MissingField", '{"guest_cmd":0}', balloon="hinting-status")
    run("UnexpectedToken", '{"host_cmd":false}', balloon="hinting-status")
    run("SyntaxError", "{!", balloon="hinting-status")
    for variant in ("put-full", "put-minimal", "patch-size", "patch-zero"):
        run("success", "", status=204, hotplug=variant)
    for variant in ("put-empty", "put-zero", "put-negative", "patch-empty", "patch-negative"):
        run("fault", '{"fault_message":"denied"}', status=400, hotplug=variant)
    for operation in ("put-full", "patch-size", "read"):
        run("fault", '{"fault_message":"denied"}', status=400, hotplug=operation)
        run("unexpected-status", '{"fault_message":"denied"}', status=202 if operation == "read" else 200, hotplug=operation)
        run("Timeout", delay=0.4, hotplug=operation)
        run("EndOfStream", raw=b"", hotplug=operation)
        run("ResponseTooLarge", "x" * (65536 + 1), status=400, hotplug=operation)
    run("hotplug-full", '{"total_size_mib":1024,"slot_size_mib":128,"block_size_mib":2,"plugged_size_mib":128,"requested_size_mib":256,"future":true}', hotplug="read")
    run("hotplug-empty", "{}", hotplug="read")
    hotplug_fields = ("total_size_mib", "slot_size_mib", "block_size_mib", "plugged_size_mib", "requested_size_mib")
    run("hotplug-empty", json.dumps(dict.fromkeys(hotplug_fields)), hotplug="read")
    run("hotplug-zero", json.dumps(dict.fromkeys(hotplug_fields, 0)), hotplug="read")
    run("UnexpectedToken", '{"requested_size_mib":false}', hotplug="read")
    run("SyntaxError", "{!", hotplug="read")
    for variant in device_requests:
        run("success", "", status=204, device=variant)
    for operation in ("vsock", "entropy", "serial", "pmem-put", "pmem-patch"):
        variant = operation + "-full"
        run("fault", '{"fault_message":"denied"}', status=400, device=variant)
        run("unexpected-status", '{"fault_message":"denied"}', status=200, device=variant)
        run("raw-fault", "unavailable\nnot JSON", status=503, device=variant)
        run("Timeout", delay=0.4, device=variant)
        run("EndOfStream", raw=b"", device=variant)
        run("ResponseTooLarge", "x" * (65536 + 1), status=400, device=variant)
    executable("Firecracker v1.18.0")
    run("UnsupportedVersion")
    executable("Firecracker v1.17.0-dev")
    run("PrereleaseVersion")
    executable("not a version")
    run("InvalidVersionOutput")
    executable(command="exit 7")
    run("ProcessFailed")
    executable(command="exec sleep 2")
    run("Timeout")
    executable("x" * 4097)
    run("OutputTooLong")
    binary.unlink()
    run("ExecutableNotFound")
    run("ExecutableNotFound", search=True)
