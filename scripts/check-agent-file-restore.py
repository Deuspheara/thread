#!/usr/bin/env python3
"""Open only a saved disposable file through app client/XPC; inspect and close it before cleanup."""
import argparse
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / 'build/Thread.app/Contents/MacOS/Thread'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--switcher', action='store_true', help='Also reopen saved history for keyboard restoration through the UI')
parser.add_argument("--application", help="Open the disposable file in this explicit application bundle identifier")
arguments = parser.parse_args()

with tempfile.TemporaryDirectory(prefix='th-agent-file-restore-', dir='/private/tmp') as temporary:
    directory = Path(temporary) / 'data'
    directory.mkdir(mode=0o700)
    environment = dict(os.environ, THREAD_DATA_DIRECTORY=str(directory), THREAD_AGENT_FILE_RESTORE_CHECK='1')
    if arguments.application:
        environment["THREAD_FILE_RESTORE_APPLICATION"] = arguments.application
    for name in ('THREAD_AGENT_PROBE', 'THREAD_AGENT_RUNTIME_CHECK', 'THREAD_SKIP_ONBOARDING'):
        environment.pop(name, None)
    process = subprocess.Popen([str(BINARY)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        process.wait(timeout=25)
        result = directory / 'AgentFileRestoreResult'
        assert process.returncode == 0 and result.read_text() == 'passed'
        assert result.stat().st_mode & 0o777 == 0o600
        assert not (directory / 'Shell/activity.sock').exists()
        assert not (directory / 'Browser/activity.sock').exists()
        with sqlite3.connect(f'file:{directory / "Thread.sqlite"}?mode=ro', uri=True) as database:
            assert database.execute('SELECT COUNT(*) FROM threads WHERE title = ?', ('Saved file fixture',)).fetchone()[0] == 1
        print('Actual saved Thread → AgentClient → helper → file adapter returned restored.', flush=True)
        print('Inspect preferred application document:' if arguments.application else 'Inspect default-application document:', directory / 'SavedThreadRestore.txt', flush=True)
        input('After verifying the visible fixture contents and closing its document, press Enter to continue: ')
        if arguments.switcher:
            marker = directory / 'OnboardingComplete'
            marker.write_bytes(b'1')
            marker.chmod(0o600)
            environment.pop('THREAD_AGENT_FILE_RESTORE_CHECK')
            process = subprocess.Popen([str(BINARY)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print('Owned switcher fixture PID:', process.pid, flush=True)
            input('Select Saved file fixture with Return, inspect and close its restored TextEdit document, then Quit Thread and press Enter: ')
            process.wait(timeout=10)
            assert process.returncode == 0
            assert not (directory / 'Shell/activity.sock').exists()
            assert not (directory / 'Browser/activity.sock').exists()
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
print('Owned file restore fixture cleaned up.')
