#!/usr/bin/env python3
"""Interactive AppKit Quit verification before setup and after observation, using disposable data."""
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time
import uuid

BINARY = Path(__file__).resolve().parent.parent / 'build/Thread.app/Contents/MacOS/Thread'


def until(check, process):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        assert process.poll() is None, 'Owned app exited before checkpoint'
        if check():
            return
        time.sleep(0.05)
    raise AssertionError('Owned observation startup timed out')


with tempfile.TemporaryDirectory(prefix='th-native-shutdown-', dir='/private/tmp') as temporary:
    directory = Path(temporary) / 'data'
    directory.mkdir(mode=0o700)
    environment = dict(os.environ, THREAD_DATA_DIRECTORY=str(directory))
    for name in ('THREAD_SKIP_ONBOARDING', 'THREAD_AGENT_PROBE', 'THREAD_AGENT_RUNTIME_CHECK'):
        environment.pop(name, None)
    for started in (False, True):
        if started:
            marker = directory / 'OnboardingComplete'
            marker.write_bytes(b'1')
            marker.chmod(0o600)
        process = subprocess.Popen([str(BINARY)], env=environment,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            if started:
                database = directory / 'Thread.sqlite'
                socket = directory / 'Shell/activity.sock'
                until(lambda: database.exists() and socket.exists(), process)
                project = Path(temporary) / 'shutdown-project'
                subprocess.run(['/usr/bin/git', 'init', '-q', '-b', 'quit-check', str(project)], check=True)
                subprocess.run([str(BINARY.with_name('ThreadShellSend')), 'directory', str(uuid.uuid4()),
                                str(os.getpid()), '1', str(project), '', ''],
                               env=dict(environment, THREAD_SOCKET_PATH=str(socket)), check=True)

                def saved():
                    with sqlite3.connect(f'file:{database}?mode=ro', uri=True) as connection:
                        return connection.execute('SELECT COUNT(*) FROM threads').fetchone()[0] >= 1
                until(saved, process)
            print('Owned fixture PID:', process.pid, 'Started observation:', started,
                  'Quit this instance through the Thread app menu.', flush=True)
            process.wait(timeout=90)
            assert process.returncode == 0, 'AppKit quit did not exit normally'
            assert not (directory / 'Shell/activity.sock').exists(), 'Shell observation survived Quit'
            assert not (directory / 'Browser/activity.sock').exists(), 'Browser observation survived Quit'
            if not started:
                assert not (directory / 'Thread.sqlite').exists(), 'Quit before consent created activity storage'
                assert not (directory / 'AgentRuntimePID').exists(), 'Quit before consent started the runtime'
                print('Before-setup Quit: no activity database or observation sockets created.', flush=True)
            else:
                assert saved(), 'Quit lost saved history'
                print('Active Quit: normal AppKit exit, saved history retained and both sockets removed.', flush=True)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
print('Native AppKit shutdown passed before setup and after active observation.')
