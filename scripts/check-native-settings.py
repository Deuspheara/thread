#!/usr/bin/env python3
"""Interactive disposable Settings save/reload and disabled remote validation fixture."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

BINARY = Path(__file__).resolve().parent.parent / 'build/Thread.app/Contents/MacOS/Thread'
with tempfile.TemporaryDirectory(prefix='th-native-settings-', dir='/private/tmp') as temporary:
    directory = Path(temporary) / 'data'
    directory.mkdir(mode=0o700)
    marker = directory / 'OnboardingComplete'
    marker.write_bytes(b'1')
    marker.chmod(0o600)
    environment = dict(os.environ, THREAD_DATA_DIRECTORY=str(directory))
    for name in ('THREAD_SKIP_ONBOARDING', 'THREAD_AGENT_PROBE', 'THREAD_AGENT_RUNTIME_CHECK'):
        environment.pop(name, None)
    process = None

    def launch():
        owned = subprocess.Popen([str(BINARY)], env=environment,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            assert owned.poll() is None, 'Owned settings app exited'
            if (directory / 'Shell/activity.sock').exists():
                return owned
            time.sleep(0.05)
        owned.terminate()
        owned.wait(timeout=5)
        raise AssertionError('Owned settings runtime did not start')

    def stop():
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)

    try:
        process = launch()
        print('Owned Settings fixture PID:', process.pid, 'Data:', directory, flush=True)
        print('Save org.example.fixture and ignored.example exclusions. Reject an HTTP endpoint with remote disabled. Enter newline afterward.', flush=True)
        input()
        preferences = directory / 'ObservationPreferences.json'
        assert json.loads(preferences.read_text()) == {'applications': ['org.example.fixture'], 'domains': ['ignored.example']}
        assert preferences.stat().st_mode & 0o777 == 0o600
        remote = directory / 'RemoteInference.json'
        if remote.exists():
            value = json.loads(remote.read_text())
            assert value['enabled'] is False and value.get('endpoint') is None
        stop()
        process = launch()
        print('Restarted: verify saved exclusions reload in Settings and remote remains disabled; enter newline afterward.', flush=True)
        input()
        assert json.loads(preferences.read_text()) == {'applications': ['org.example.fixture'], 'domains': ['ignored.example']}
        print('Native Settings: private exclusions saved/reloaded after restart; invalid remote endpoint left consent disabled.', flush=True)
    finally:
        stop()
