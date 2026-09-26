#!/usr/bin/env python3
"""Verify signed embedded XPC readiness and an intentionally rejected peer in disposable data."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
binary = root / 'build/Thread.app/Contents/MacOS/Thread'
for rejected in (False, True):
    with tempfile.TemporaryDirectory(prefix='th-agent-xpc-', dir='/private/tmp') as temporary:
        directory = Path(temporary) / 'data'
        directory.mkdir(mode=0o700)
        environment = dict(os.environ, THREAD_DATA_DIRECTORY=str(directory), THREAD_AGENT_PROBE='1',
                           THREAD_AGENT_PROBE_REJECT='1' if rejected else '0')
        process = subprocess.Popen([str(binary)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            process.wait(timeout=8)
            assert process.returncode == 0, 'Owned probe app failed'
            outcome = json.loads((directory / 'AgentProbeResult.json').read_text())
            assert outcome['status'] == ('rejected' if rejected else 'ready'), 'Readiness/signing expectation failed'
            if not rejected:
                assert outcome['agent'] > 0 and outcome['agent'] != process.pid, 'Helper was not a separate process'
            assert (directory / 'AgentProbeResult.json').stat().st_mode & 0o777 == 0o600, 'Probe result is not private'
            assert not (directory / 'Browser/activity.sock').exists(), 'Probe started browser observation'
            assert not (directory / 'Thread.sqlite').exists(), 'Probe started persistence'
            assert not (directory / 'Shell/activity.sock').exists(), 'Probe started shell observation'
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
                    raise AssertionError('Owned probe app did not stop')
print('Embedded XPC helper: signed readiness from a separate process; stricter peer requirement rejected; no observation/storage started.')
