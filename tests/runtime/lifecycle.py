#!/usr/bin/env python3
"""Disposable real-child/Unix-HTTP scenarios; no KVM or host networking required."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

FIXTURE = r'''#!/usr/bin/env python3
import json, os, pathlib, signal, socket, sys, time
mode = MODE
root = pathlib.Path(__file__).parent
if sys.argv[1:] == ['--version']:
    (root / 'probe-pid').write_text(str(os.getpid()))
    if mode == 'combined-deadline' and not (root / 'preflight-done').exists():
        time.sleep(0.4)
        (root / 'preflight-done').touch()
    if mode == 'boot-budget':
        time.sleep(0.3)
    if mode in ('probe-hang', 'probe-closed'):
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if mode == 'probe-closed':
            os.close(1)
            os.close(2)
        time.sleep(30)
    if mode == 'probe-failed':
        sys.exit(7)
    if mode == 'wrong-banner':
        print('Not Firecracker')
    elif mode == 'unsupported':
        print('Firecracker v1.17.1')
    elif mode == 'prerelease':
        print('Firecracker v1.17.0-dev')
    else:
        print('Firecracker v1.17.0')
    sys.exit(0)
assert len(sys.argv) == 3 and sys.argv[1] == '--api-sock', sys.argv
(root / 'pid').write_text(str(os.getpid()))
if mode == 'rollback':
    pathlib.Path(sys.argv[2]).with_name('borrowed').write_text('keep')
    sys.exit(23)
if mode == 'exit':
    sys.exit(23)
if mode == 'silent':
    time.sleep(30)
if mode == 'kill':
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
if mode == 'delayed':
    time.sleep(0.15)
if mode == 'combined-deadline':
    time.sleep(0.4)
server = socket.socket(socket.AF_UNIX)
server.bind(sys.argv[2])
server.listen()
running = False
hung_connections = []
while True:
    conn, _ = server.accept()
    with conn:
        request = b''
        while b'\r\n\r\n' not in request:
            part = conn.recv(4096)
            if not part:
                break
            request += part
        if not request:
            continue
        if mode == 'hang':
            time.sleep(30)
        headers, body = request.split(b'\r\n\r\n', 1)
        method, route, _ = headers.split(b'\r\n', 1)[0].decode().split(' ')
        content_length = 0
        for header in headers.split(b'\r\n')[1:]:
            name, value = header.split(b':', 1)
            if name.lower() == b'content-length':
                content_length = int(value)
        while len(body) < content_length:
            part = conn.recv(content_length - len(body))
            if not part:
                raise AssertionError('incomplete request body')
            body += part
        payload = json.loads(body) if body else None
        with (root / 'requests.jsonl').open('a') as log:
            log.write(json.dumps({'method': method, 'path': route, 'body': payload}) + '\n')
        if mode == 'boot-budget' and route in ('/version', '/machine-config'):
            time.sleep(0.3)
        status = 200
        if mode == 'fault':
            status, body = 503, b'{"fault_message":"unavailable"}'
        elif route == '/version':
            assert method == 'GET' and payload is None
            body = json.dumps({'firecracker_version': '1.17.1' if mode == 'mismatch' else '1.17.0'}).encode()
        elif route == '/':
            assert method == 'GET' and payload is None
            body = json.dumps({'id': 'runtime-test', 'state': 'Running' if running else 'Not started', 'vmm_version': '1.17.0', 'app_name': 'Firecracker'}).encode()
        elif mode.startswith('boot-'):
            assert method == 'PUT', (method, route)
            assert route in ('/machine-config', '/boot-source', '/drives/rootfs', '/drives/data', '/actions'), route
            if route == '/boot-source':
                (root / 'config-entered').touch()
                if mode in ('boot-rollback', 'boot-fault-rollback'):
                    pathlib.Path(sys.argv[2]).with_name('borrowed').write_text('keep')
                if mode in ('boot-exit', 'boot-rollback'):
                    sys.exit(23)
                if mode == 'boot-cancel':
                    time.sleep(30)
            rejected = {
                'boot-reject-machine': '/machine-config',
                'boot-reject-source': '/boot-source',
                'boot-reject-drive': '/drives/rootfs',
                'boot-reject-start': '/actions',
                'boot-fault-rollback': '/boot-source',
            }.get(mode)
            if route == rejected:
                status, body = 422, b'{"fault_message":"boot rejected"}'
            else:
                if route == '/actions':
                    assert payload == {'action_type': 'InstanceStart'}, payload
                    if mode == 'boot-timeout':
                        # Keep this response pending but continue accepting,
                        # so an accidental retry is recorded, not hidden by
                        # a blocked single-connection fixture.
                        hung_connections.append(conn.dup())
                        continue
                    running = True
                status, body = 204, b''
        else:
            raise AssertionError(route)
        conn.sendall(f'HTTP/1.1 {status} OK\r\nContent-Length: {len(body)}\r\nConnection: close\r\n\r\n'.encode() + body)
'''

runner = sys.argv[1]
for fixture, expected in [
    ('missing', 'ExecutableNotFound'),
    ('noexec', 'NotExecutable'),
    ('directory', 'NotExecutable'),
    ('wrong-banner', 'InvalidVersionOutput'),
    ('unsupported', 'UnsupportedVersion'),
    ('prerelease', 'PrereleaseVersion'),
    ('probe-failed', 'ProcessFailed'),
    ('exit', 'ProcessExited'),
    ('silent', 'StartupTimeout'),
    ('silent', 'cancel'),
    ('hang', 'StartupTimeout'),
    ('probe-hang', 'StartupTimeout'),
    ('probe-hang', 'cancel'),
    ('probe-closed', 'StartupTimeout'),
    ('probe-closed', 'cancel'),
    ('combined-deadline', 'StartupTimeout'),
    ('mismatch', 'VersionMismatch'),
    ('fault', 'fault'),
    ('delayed', 'success'),
    ('kill', 'kill'),
    ('kill', 'shutdown-cancel'),
    ('rollback', 'rollback'),
    ('normal', 'cleanup'),
    ('boot-success', 'boot-success'),
    ('boot-reject-machine', 'boot-reject-machine'),
    ('boot-reject-source', 'boot-reject-source'),
    ('boot-reject-drive', 'boot-reject-drive'),
    ('boot-reject-start', 'boot-reject-start'),
    ('boot-timeout', 'boot-timeout'),
    ('boot-cancel', 'boot-cancel'),
    ('boot-exit', 'boot-exit'),
    ('boot-rollback', 'boot-rollback'),
    ('boot-fault-rollback', 'boot-fault-rollback'),
    ('boot-budget', 'boot-budget'),
]:
    with tempfile.TemporaryDirectory(prefix='fcz-') as directory:
        root = pathlib.Path(directory)
        binary = root / 'fire cracker;literal'
        if fixture == 'directory':
            binary.mkdir()
        elif fixture != 'missing':
            binary.write_text(FIXTURE.replace('MODE', repr(fixture)))
            binary.chmod(0o600 if fixture == 'noexec' else 0o700)
        sentinel = root / 'borrowed'
        sentinel.write_bytes(b'preserve me')
        artifacts = {
            'kernel image': b'borrowed kernel',
            'initrd': b'borrowed initrd',
            'root disk': b'borrowed root disk',
            'data disk': b'borrowed writable disk',
        }
        if fixture.startswith('boot-'):
            for name, content in artifacts.items():
                (root / name).write_bytes(content)
        started_at = time.monotonic()
        run = subprocess.run([runner, str(binary), directory, expected], capture_output=True, text=True, timeout=8)
        if run.returncode:
            raise AssertionError(f'{fixture}/{expected}: {run.returncode}\n{run.stdout}\n{run.stderr}')
        elapsed = time.monotonic() - started_at
        if fixture.startswith('boot-'):
            for name, content in artifacts.items():
                assert (root / name).read_bytes() == content, (fixture, name)
            requests = [json.loads(line) for line in (root / 'requests.jsonl').read_text().splitlines()]
            expected_requests = [
                {'method': 'GET', 'path': '/version', 'body': None},
                {'method': 'PUT', 'path': '/machine-config', 'body': {
                    'vcpu_count': 2, 'mem_size_mib': 256, 'smt': False, 'track_dirty_pages': True,
                }},
                {'method': 'PUT', 'path': '/boot-source', 'body': {
                    'kernel_image_path': str(root / 'kernel image'),
                    'initrd_path': str(root / 'initrd'),
                    'boot_args': 'console=ttyS0 reboot=k panic=1 pci=off',
                }},
                {'method': 'PUT', 'path': '/drives/rootfs', 'body': {
                    'drive_id': 'rootfs', 'is_root_device': True, 'is_read_only': True,
                    'path_on_host': str(root / 'root disk'),
                }},
                {'method': 'PUT', 'path': '/drives/data', 'body': {
                    'drive_id': 'data', 'is_root_device': False, 'is_read_only': False,
                    'path_on_host': str(root / 'data disk'),
                }},
                {'method': 'PUT', 'path': '/actions', 'body': {'action_type': 'InstanceStart'}},
            ]
            request_count = {
                'boot-reject-machine': 2,
                'boot-reject-source': 3,
                'boot-reject-drive': 4,
                'boot-reject-start': 6,
                'boot-timeout': 6,
                'boot-cancel': 3,
                'boot-exit': 3,
                'boot-rollback': 3,
                'boot-fault-rollback': 3,
            }.get(fixture)
            if fixture == 'boot-success':
                expected_requests.append({'method': 'GET', 'path': '/', 'body': None})
            elif fixture == 'boot-budget':
                # A single 700ms budget cannot finish the 300ms preflight,
                # 300ms API check, and 300ms machine configuration.
                assert 1 <= len(requests) <= 2, requests
                expected_requests = expected_requests[:len(requests)]
            else:
                expected_requests = expected_requests[:request_count]
            assert requests == expected_requests, (fixture, requests, expected_requests)
            if fixture in ('boot-timeout', 'boot-budget'):
                assert elapsed < 3, (fixture, elapsed)
        assert sentinel.read_bytes() == b'preserve me'
        assert not [entry for entry in root.iterdir() if entry.is_dir() and entry != binary], list(root.iterdir())
        if fixture in ('missing', 'noexec', 'directory', 'wrong-banner', 'unsupported',
                       'prerelease', 'probe-failed', 'probe-hang', 'probe-closed'):
            assert not (root / 'pid').exists(), f'{fixture}: launched managed instance before validation'
        for name in ('pid', 'probe-pid'):
            pid_file = root / name
            if pid_file.exists():
                pid = int(pid_file.read_text())
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    pass
                else:
                    raise AssertionError(f'{fixture}: child {pid} still exists (running or zombie)')
        print(f'PASS {fixture}/{expected}: no remaining child or workspace; borrowed files preserved')
