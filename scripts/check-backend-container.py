#!/usr/bin/env python3
"""Verify an owned backend image on an isolated Docker network with fictional credentials."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parent.parent
name = f'thread-api-check-{os.getpid()}'
api, store, network = name + '-api', name + '-redis', name + '-network'

def docker(*args, check=True):
    return subprocess.run(['docker', *args], check=check, capture_output=True, text=True, timeout=60)

def probe(path, authenticated=False, payload=None):
    script = """const http = require('node:http');
const input = JSON.parse(process.argv[1]);
const headers = {'content-type':'application/json'};
if (input.authenticated) headers.authorization = 'Bearer ' + 'a'.repeat(43);
const req = http.request({hostname:'127.0.0.1',port:8787,path:input.path,
method:input.payload === null ? 'GET' : 'POST',headers,signal:AbortSignal.timeout(1000)}, res => {
res.resume(); res.on('end', () => process.stdout.write(String(res.statusCode)));
}); req.on('error', () => {process.exitCode=1}); req.end(input.payload ?? undefined);"""
    result = docker('exec', api, 'node', '-e', script, json.dumps({'path': path, 'authenticated': authenticated, 'payload': payload}), check=False)
    return result.stdout.strip()

try:
    # Public templates are copied into an owned directory; never load the repository's private env.
    with tempfile.TemporaryDirectory(prefix='thread-compose-') as temporary:
        directory = Path(temporary)
        for file in ('compose.yaml', 'compose.host-tunnel.yaml'):
            (directory / file).write_bytes((root / 'Backend' / file).read_bytes())
        (directory / 'thread-api.env').write_text('OPENROUTER_API_KEY=sk-or-' + 'a' * 32 + '\nTHREAD_CLIENT_TOKENS=\'{"fixture":"' + 'a' * 43 + '"}\'\n')
        for files in [('compose.yaml',), ('compose.yaml', 'compose.host-tunnel.yaml')]:
            args = ['compose', '--project-directory', str(directory)]
            for file in files:
                args.extend(['-f', str(directory / file)])
            docker(*args, 'config', '--quiet')
    docker('network', 'create', '--internal', network)
    docker('run', '-d', '--name', store, '--network', network, '--network-alias', 'rate-store',
           'redis:7.4-alpine', 'redis-server', '--save', '', '--appendonly', 'no')
    docker('run', '-d', '--name', api, '--network', network, '--read-only', '--cap-drop', 'ALL',
           '--security-opt', 'no-new-privileges:true', '--memory', '256m', '--pids-limit', '64',
           '-e', 'THREAD_API_HOST=0.0.0.0', '-e', 'THREAD_REDIS_URL=redis://rate-store:6379/0',
           '-e', 'OPENROUTER_API_KEY=sk-or-' + 'a' * 32,
           '-e', 'THREAD_CLIENT_TOKENS=' + json.dumps({'fixture': 'a' * 43}), 'thread-api-check')
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and probe('/health/ready') != '204':
        time.sleep(.1)
    assert probe('/health/ready') == '204', 'Container readiness failed'
    assert docker('exec', api, 'id', '-u').stdout.strip() != '0', 'Runtime is root'
    assert probe('/v1/decisions', payload='{}') == '401'
    assert probe('/v1/decisions', True, '{}') == '400'
    assert docker('exec', api, 'node', 'dist/main.js', 'healthcheck', check=False).returncode == 0
    docker('stop', '--time', '2', store)
    assert probe('/health/ready') == '503'
    assert probe('/v1/decisions', True, '{}') == '503'
    assert docker('exec', api, 'node', 'dist/main.js', 'healthcheck', check=False).returncode == 1
    docker('stop', '--time', '6', api)
    assert docker('inspect', '--format', '{{.State.ExitCode}}', api).stdout.strip() == '0'
finally:
    for container in (api, store):
        docker('rm', '-f', container, check=False)
    docker('network', 'rm', network, check=False)
print('Passed: both Compose variants, non-root/read-only container, health/auth/validation, Redis outage and SIGTERM.')
