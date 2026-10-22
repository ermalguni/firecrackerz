#!/usr/bin/env python3
"""Disposable real-child/Unix-HTTP scenarios; no KVM or host networking required."""
import os
import pathlib
import subprocess
import sys
import tempfile

FIXTURE = r'''#!/usr/bin/env python3
import json, os, pathlib, signal, socket, sys, time
mode = MODE
root = pathlib.Path(__file__).parent
if sys.argv[1:] == ['--version']:
    (root / 'probe-pid').write_text(str(os.getpid()))
    if mode == 'combined-deadline' and not (root / 'preflight-done').exists():
        time.sleep(0.4)
        (root / 'preflight-done').touch()
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
        route = request.split(b' ')[1]
        status = 200
        if mode == 'fault':
            status, body = 503, b'{"fault_message":"unavailable"}'
        elif route == b'/version':
            body = json.dumps({'firecracker_version': '1.17.1' if mode == 'mismatch' else '1.17.0'}).encode()
        elif route == b'/':
            body = json.dumps({'id': 'runtime-test', 'state': 'Not started', 'vmm_version': '1.17.0', 'app_name': 'Firecracker'}).encode()
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
        run = subprocess.run([runner, str(binary), directory, expected], capture_output=True, text=True, timeout=8)
        if run.returncode:
            raise AssertionError(f'{fixture}/{expected}: {run.returncode}\n{run.stdout}\n{run.stderr}')
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
