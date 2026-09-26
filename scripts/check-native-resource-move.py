#!/usr/bin/env python3
"""Interactive native Directory Move/restart fixture; not part of unattended checks.

Use the app UI to move project-a's Directory to project-b, then press Return here.
After restart, reopen project-b details and verify Directory · Assigned by you;
press Return again to verify saved IDs and clean the owned app/data.
"""
import os, subprocess, tempfile, time, uuid, sqlite3
from pathlib import Path
binary = Path(__file__).resolve().parent.parent / "build/Thread.app/Contents/MacOS/Thread"
with tempfile.TemporaryDirectory(prefix="th-native-ui-", dir="/private/tmp") as temporary:
    directory = Path(temporary) / "data"
    directory.mkdir(mode=0o700)
    (directory / "OnboardingComplete").write_bytes(b"1")
    environment = dict(os.environ, THREAD_DATA_DIRECTORY=str(directory))
    environment.pop("THREAD_SKIP_ONBOARDING", None)
    process = subprocess.Popen([str(binary)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    def until(check):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            assert process.poll() is None, "Test app exited"
            if check(): return
            time.sleep(0.05)
        raise AssertionError("Fixture startup/inference timed out")
    try:
        socket = directory / "Shell/activity.sock"
        database = directory / "Thread.sqlite"
        until(lambda: socket.exists() and database.exists())
        session = str(uuid.uuid4())
        for sequence, name in enumerate(["project-a", "project-b"], start=1):
            project = Path(temporary) / name
            subprocess.run(["git", "init", "-q", "-b", "gui-check", str(project)], check=True)
            subprocess.run([str(binary.with_name("ThreadShellSend")), "directory", session, str(os.getpid()), str(sequence), str(project), "", ""],
                env=dict(environment, THREAD_SOCKET_PATH=str(socket)), check=True)
            def saved():
                try:
                    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
                        return connection.execute("SELECT count(*) FROM threads WHERE title = ?", (name + " · gui-check",)).fetchone()[0] == 1
                except sqlite3.OperationalError: return False
            until(saved)
        print("Owned fixture PID:", process.pid, "Database:", database, flush=True)
        print("Ready for native resource Move. Enter newline after verifying it in the UI.", flush=True)
        input()
        with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
            records = connection.execute("SELECT id, resource_kind, origin, status, outcome, source_thread_id, target_thread_id FROM resource_reassignments").fetchall()
            assert len(records) == 1, records
            record = records[0]
            assert record[1:5] == ('workingDirectory', 'inferred', 'confirmed', 'moved'), record
            titles = dict(connection.execute("SELECT id, title FROM threads"))
            assert titles[record[5]] == 'project-a · gui-check' and titles[record[6]] == 'project-b · gui-check'
            before = connection.execute("SELECT * FROM user_corrections").fetchall()
            assert len(before) == 1
        process.terminate(); process.wait(timeout=5)
        process = subprocess.Popen([str(binary)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        until(lambda: socket.exists() and process.poll() is None)
        print("Restarted owned fixture. Reopen and inspect the moved resource, then enter newline.", flush=True)
        input()
        with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
            assert connection.execute("SELECT id FROM resource_reassignments").fetchall() == [(record[0],)]
            assert connection.execute("SELECT * FROM user_corrections").fetchall() == before
        print("Native Move and restart retained the same correction and reassignment record.", flush=True)
    finally:
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=5)
                raise AssertionError("Test app did not stop promptly")
