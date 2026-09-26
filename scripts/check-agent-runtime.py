#!/usr/bin/env python3
"""Exercise helper commands and kill/recover only an authenticated disposable fixture helper."""
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / 'build/Thread.app/Contents/MacOS/Thread'


def until(check, description, process):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        assert process.poll() is None, 'Owned fixture app exited early'
        if check():
            return
        time.sleep(0.05)
    raise AssertionError(description)


with tempfile.TemporaryDirectory(prefix='th-agent-runtime-', dir='/private/tmp') as temporary:
    directory = Path(temporary) / 'data'
    directory.mkdir(mode=0o700)
    project = Path(temporary) / 'project'
    subprocess.run(['/usr/bin/git', 'init', '-q', '-b', 'runtime-check', str(project)], check=True)
    environment = dict(os.environ, THREAD_DATA_DIRECTORY=str(directory), THREAD_AGENT_RUNTIME_CHECK='1')
    process = subprocess.Popen([str(BINARY)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        ready = directory / 'AgentRuntimeReady'
        until(ready.exists, 'Helper startup did not complete', process)
        agent = int(ready.read_text())
        assert agent > 0 and agent != process.pid and ready.stat().st_mode & 0o777 == 0o600
        subprocess.run([str(BINARY.with_name('ThreadShellSend')), 'directory', str(uuid.uuid4()),
                        str(os.getpid()), '1', str(project), '', ''],
                       env=dict(environment, THREAD_SOCKET_PATH=str(directory / 'Shell/activity.sock')), check=True)
        kill_ready = directory / 'AgentRuntimeKillReady'
        until(kill_ready.exists, 'Helper command checks did not complete', process)
        assert int(kill_ready.read_text()) == agent and kill_ready.stat().st_mode & 0o777 == 0o600
        cancellation = directory / 'AgentCancellationResult'
        assert cancellation.stat().st_mode & 0o777 == 0o600
        counts = dict(item.split('=') for item in cancellation.read_text().split())
        assert set(counts) == {'reads', 'cancelled', 'busy'}
        assert sum(map(int, counts.values())) == 32 and int(counts['reads']) > 0
        print('Bounded cancellation check:', cancellation.read_text(), flush=True)
        with sqlite3.connect(f'file:{directory / "Thread.sqlite"}?mode=ro', uri=True) as database:
            original = database.execute('SELECT id, title FROM threads').fetchall()
            assert len(original) == 1 and original[0][1] == 'Recovered fixture'
        # PID is scoped to this live signed connection; never search/kill unrelated Thread helpers.
        peer = subprocess.run(['/bin/ps', '-p', str(agent), '-o', 'uid=', '-o', 'comm='], capture_output=True, text=True, check=True)
        identity = peer.stdout.strip().split(maxsplit=1)
        assert len(identity) == 2 and int(identity[0]) == os.getuid()
        assert Path(identity[1]) == BINARY.parents[1] / 'XPCServices/ThreadAgent.xpc/Contents/MacOS/ThreadAgent'
        os.kill(agent, signal.SIGKILL)
        process.wait(timeout=20)
        assert process.returncode == 0 and (directory / 'AgentRuntimeResult').read_text() == 'passed'
        recovered = int((directory / 'AgentRuntimeRecovered').read_text())
        assert recovered > 0 and recovered not in (agent, process.pid)
        with sqlite3.connect(f'file:{directory / "Thread.sqlite"}?mode=ro', uri=True) as database:
            assert database.execute('SELECT id, title FROM threads').fetchall() == original
        assert not (directory / 'Shell/activity.sock').exists()
        assert not (directory / 'Browser/activity.sock').exists()
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
print('Actual XPC: rename/pin/archive, search/detail, exclusions, bounded validation, owned helper crash/recovery and explicit socket shutdown passed.')
