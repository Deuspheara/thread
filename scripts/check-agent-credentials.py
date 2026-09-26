#!/usr/bin/env python3
"""Verify real helper Keychain save/read/removal using a unique fictional endpoint."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
app = root / 'build/Thread.app/Contents'
with (app / 'XPCServices/ThreadAgent.xpc/Contents/Info.plist').open('rb') as source:
    configuration = plistlib.load(source)
assert configuration['XPCService'].get('JoinExistingSession') is True, 'Helper lacks the user security session'
with tempfile.TemporaryDirectory(prefix='th-agent-credential-', dir='/private/tmp') as temporary:
    directory = Path(temporary) / 'data'
    directory.mkdir(mode=0o700)
    environment = dict(os.environ, THREAD_DATA_DIRECTORY=str(directory), THREAD_AGENT_CREDENTIAL_CHECK='1')
    process = subprocess.Popen([str(app / 'MacOS/Thread')], env=environment,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        process.wait(timeout=25)
        result = directory / 'AgentCredentialResult'
        assert result.exists(), 'Helper credential fixture did not produce a result'
        assert result.read_text() == 'passed', 'Helper credential fixture failed at ' + result.read_text()
        assert process.returncode == 0, 'Helper credential fixture exited unsuccessfully'
        assert result.stat().st_mode & 0o777 == 0o600, 'Credential fixture result is not private'
        assert not (directory / 'Thread.sqlite').exists(), 'Credential fixture started persistence'
        assert not (directory / 'Browser/activity.sock').exists(), 'Credential fixture started observation'
        assert not (directory / 'Shell/activity.sock').exists(), 'Credential fixture started observation'
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
print('Embedded helper Keychain: fictional credential saved, read without prompts, removed; no observation or provider requests.')
