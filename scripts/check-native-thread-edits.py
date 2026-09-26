#!/usr/bin/env python3
"""Interactive rename/archive/restart/unarchive fixture; never an unattended test.

Rename the fixture Thread to Native renamed and archive it through the app UI.
Press Return here, then after restart find it through search and unarchive it.
Press Return again to validate the retained identity and clean owned data.
"""
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time
import uuid

binary = Path(__file__).resolve().parent.parent / 'build/Thread.app/Contents/MacOS/Thread'
with tempfile.TemporaryDirectory(prefix='th-native-edits-', dir='/private/tmp') as temporary:
    directory = Path(temporary) / 'data'
    directory.mkdir(mode=0o700)
    (directory / 'OnboardingComplete').write_bytes(b'1')
    (directory / 'OnboardingComplete').chmod(0o600)
    environment = dict(os.environ, THREAD_DATA_DIRECTORY=str(directory))
    environment.pop('THREAD_SKIP_ONBOARDING', None)
    process = subprocess.Popen([str(binary)], env=environment,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    database = directory / 'Thread.sqlite'
    socket = directory / 'Shell/activity.sock'

    def until(check):
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            assert process.poll() is None, 'Owned app exited'
            if check():
                return
            time.sleep(0.1)
        raise AssertionError('Fixture startup/save timed out')

    def rows():
        with sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True) as connection:
            return connection.execute('SELECT id, title, archived FROM threads').fetchall()

    def stop():
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
                raise AssertionError('Owned app did not stop promptly')

    try:
        until(lambda: socket.exists() and database.exists())
        project = Path(temporary) / 'native-edits'
        subprocess.run(['git', 'init', '-q', '-b', 'gui-check', str(project)], check=True)
        subprocess.run([str(binary.with_name('ThreadShellSend')), 'directory', str(uuid.uuid4()),
                        str(os.getpid()), '1', str(project), '', ''], check=True,
                       env=dict(environment, THREAD_SOCKET_PATH=str(socket)))
        until(lambda: any(row[1] == 'native-edits · gui-check' for row in rows()))
        identifier = next(row[0] for row in rows() if row[1] == 'native-edits · gui-check')
        print('Owned fixture PID:', process.pid, 'Database:', database, flush=True)
        print('Rename to Native renamed and archive through UI; enter newline afterward.', flush=True)
        input()
        until(lambda: (identifier, 'Native renamed', 1) in rows())
        stop()
        process = subprocess.Popen([str(binary)], env=environment,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        until(lambda: socket.exists() and (identifier, 'Native renamed', 1) in rows())
        print('Restarted. Search Native renamed and unarchive through UI; enter newline afterward.', flush=True)
        input()
        until(lambda: (identifier, 'Native renamed', 0) in rows())
        assert sum(row[1] == 'Native renamed' for row in rows()) == 1
        print('Native rename/archive survived restart; unarchive retained the same Thread ID.', flush=True)
    finally:
        stop()
