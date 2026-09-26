#!/usr/bin/env python3
"""Check the compiled TypeScript API with owned Redis and fictional credentials; no provider calls."""
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

root = Path(__file__).resolve().parent.parent
entrypoint = root / 'Backend/dist/main.js'
node = shutil.which('node')
redis = shutil.which('redis-server')
if not entrypoint.is_file() or not redis or not node:
    raise SystemExit('Run npm --prefix Backend run build and install Node.js 24 and redis-server before the runtime check.')

def call(port, path, body=None, authenticated=False):
    headers = {'Content-Type': 'application/json'}
    if authenticated:
        headers['Authorization'] = 'Bearer ' + 'a' * 43
    request = urllib.request.Request(f'http://127.0.0.1:{port}{path}', data=body, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=2)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.read()

with tempfile.TemporaryDirectory(prefix='th-api-runtime-', dir='/tmp') as temporary:
    directory = Path(temporary)
    unix = directory / 'rate.sock'
    environment = dict(os.environ, OPENROUTER_API_KEY='sk-or-' + 'a' * 32,
        OPENROUTER_MODEL='typesafe/jev-1.13', THREAD_CLIENT_TOKENS=json.dumps({'fixture': 'a' * 43}),
        THREAD_REDIS_URL='unix://' + str(unix), THREAD_API_HOST='127.0.0.1')
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    environment['THREAD_API_PORT'] = str(port)
    for name in ('THREAD_MAX_IN_FLIGHT', 'THREAD_MAX_CONNECTIONS'):
        environment.pop(name, None)
    store = subprocess.Popen([redis, '--port', '0', '--unixsocket', str(unix),
        '--unixsocketperm', '700', '--save', '', '--appendonly', 'no'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    api = None
    try:
        deadline = time.monotonic() + 2
        while not unix.exists() and store.poll() is None and time.monotonic() < deadline:
            time.sleep(.01)
        assert unix.exists() and store.poll() is None, 'Owned Redis startup failed'
        api = subprocess.Popen([node, str(entrypoint)], env=environment,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        ready = False
        deadline = time.monotonic() + 3
        while api.poll() is None and time.monotonic() < deadline:
            try:
                ready = call(port, '/health/ready')[0] == 204
                if ready:
                    break
            except (OSError, urllib.error.URLError):
                pass  # Bounded startup probe; final failure is asserted below.
            time.sleep(.01)
        assert ready, 'TypeScript API did not become ready'
        assert call(port, '/v1/decisions', b'{}')[0] == 401
        assert call(port, '/v1/decisions', b'{}', True)[0] == 400
        assert call(port, '/unknown')[0] == 404
        assert subprocess.run([node, str(entrypoint), 'healthcheck'], env=environment,
            timeout=2, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        store.terminate()
        store.wait(timeout=2)
        assert call(port, '/health/ready')[0] == 503
        fixture = (root / 'Backend/test/fixtures/membership.json').read_bytes()
        status, body = call(port, '/v1/decisions', fixture, True)
        assert status == 503 and json.loads(body) == {'error': 'rate_store_unavailable'}
        assert subprocess.run([node, str(entrypoint), 'healthcheck'], env=environment,
            timeout=2, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 1
        api.send_signal(signal.SIGTERM)
        api.wait(timeout=6)
        assert api.returncode == 0, 'SIGTERM was not graceful'
    finally:
        for process in (api, store):
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=2)
print('Passed: compiled TypeScript API startup, readiness, auth/validation, Redis outage rejection and graceful SIGTERM.')
