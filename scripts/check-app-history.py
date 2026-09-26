#!/usr/bin/env python3
"""Exercise an actual debug app restart with isolated database and observation sockets."""
import os
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid

root = Path(__file__).resolve().parent.parent
binary = root / "build/Thread.app/Contents/MacOS/Thread"
sender = binary.with_name("ThreadShellSend")

def until(check, description):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.1)
    raise AssertionError(description)

def stop(process):
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
        raise AssertionError("Test app did not stop promptly")

with tempfile.TemporaryDirectory(prefix="th-history-", dir="/private/tmp") as temporary:
    data = Path(temporary) / "data"
    project = Path(temporary) / "project"
    subprocess.run(["/usr/bin/git", "init", "-q", "-b", "history-check", str(project)], check=True)
    environment = dict(os.environ, THREAD_DATA_DIRECTORY=str(data), THREAD_SKIP_ONBOARDING="1")
    database = data / "Thread.sqlite"
    socket = data / "Shell/activity.sock"
    process = subprocess.Popen([str(binary)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        until(lambda: process.poll() is None and database.exists() and socket.exists(), "Isolated debug app did not start")
        until(lambda: (data / "AgentRuntimePID").exists(), "Helper ownership was not published")
        agent_pid = int((data / "AgentRuntimePID").read_text())
        assert agent_pid > 0 and agent_pid != process.pid, "Runtime remained in the UI process"
        subprocess.run([str(sender), "directory", str(uuid.uuid4()), str(os.getpid()), "1", str(project), "", ""],
                       env=dict(environment, THREAD_SOCKET_PATH=str(socket)), check=True)
        def saved():
            with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
                return (connection.execute("SELECT COUNT(*) FROM threads").fetchone()[0] == 1
                        and connection.execute("SELECT COUNT(*) FROM events").fetchone()[0] >= 2
                        and connection.execute("SELECT COUNT(*) FROM snapshots").fetchone()[0] >= 1
                        and connection.execute("SELECT COUNT(*) FROM decision_records").fetchone()[0] >= 1
                        and connection.execute("SELECT COUNT(*) FROM membership_applications WHERE outcome = 'confirmedAttachment'").fetchone()[0] >= 1
                        and connection.execute("SELECT COUNT(*) FROM transition_applications WHERE outcome = 'activated'").fetchone()[0] >= 1)
        until(saved, "Live inference was not saved")
        with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
            original = connection.execute("SELECT id, title FROM threads").fetchall()
            original_decisions = {row[0] for row in connection.execute("SELECT id FROM decision_records")}
            original_applications = {row[0] for row in connection.execute("SELECT id FROM membership_applications")}
            assert connection.execute("SELECT COUNT(*) FROM membership_applications a LEFT JOIN decision_records d ON d.id = a.decision_record_id AND d.kind = 'membership' WHERE d.id IS NULL").fetchone()[0] == 0, "Missing exact membership receipt"
            assert connection.execute("SELECT COUNT(*) FROM transition_applications a LEFT JOIN decision_records d ON d.id = a.decision_record_id AND d.kind = 'transition' WHERE a.outcome = 'activated' AND d.id IS NULL").fetchone()[0] == 0, "Missing exact transition receipt"
            original_transitions = {row[0] for row in connection.execute("SELECT id FROM transition_applications")}
            assert {row[1] for row in connection.execute("PRAGMA table_info(resource_reassignments)")} == {"id", "timestamp", "resource_kind", "origin", "status", "outcome", "source_thread_id", "target_thread_id", "decision_record_id"}
            assert connection.execute("SELECT COUNT(*) FROM resource_reassignments").fetchone()[0] == 0, "Observation recorded a user reassignment"
            assert {row[1] for row in connection.execute("PRAGMA table_info(transition_applications)")} == {"id", "timestamp", "phase", "outcome", "previous_thread_id", "target_thread_id", "decision_record_id"}
            assert all(row[0] in {item[0] for item in original} for row in connection.execute("SELECT target_thread_id FROM transition_applications"))
            assert {row[1] for row in connection.execute("PRAGMA table_info(membership_applications)")} == {"id", "timestamp", "outcome", "thread_id", "decision_record_id"}
            assert all(row[0] in {item[0] for item in original} for row in connection.execute("SELECT thread_id FROM membership_applications WHERE thread_id IS NOT NULL"))
            assert {row[0] for row in connection.execute("SELECT kind FROM decision_records")} == {"membership", "transition", "persistence"}
            assert {row[0] for row in connection.execute("SELECT origin FROM decision_records")} == {"local"}
            for (payload,) in connection.execute("SELECT payload FROM decision_records"):
                assert set(json.loads(payload)) == {"id", "timestamp", "origin", "elapsedMilliseconds", "decision", "candidates"}, "Unexpected decision metadata"
            kinds = {row[0] for row in connection.execute("SELECT kind FROM resources")}
            assert "terminal" not in kinds, "Session terminal persisted in graph"
            assert "workingDirectory" in kinds, "Durable terminal directory missing"
            for (payload,) in connection.execute("SELECT tr.payload FROM thread_resources tr JOIN resources r ON r.identity = tr.resource_id WHERE r.kind = 'workingDirectory'"):
                receipt = json.loads(payload)["membershipRecordID"]["rawValue"]
                assert connection.execute("SELECT kind FROM decision_records WHERE id = ?", (receipt,)).fetchone() == ("membership",)
            for (payload,) in connection.execute("SELECT payload FROM snapshots"):
                assert all(edge["persistence"] == "durable" for edge in json.loads(payload)["resources"]), "Non-durable snapshot resource"
    finally:
        stop(process)
    process = subprocess.Popen([str(binary)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        def hydrated():
            assert process.poll() is None, "Restarted app exited"
            result = subprocess.run(["/usr/bin/log", "show", "--last", "30s", "--info", "--style", "compact",
                                     "--predicate", 'subsystem == "app.thread.desktop" AND category == "classification"'],
                                    capture_output=True, text=True, check=True)
            return any(f"Thread[{process.pid}:" in line and "Inferred Thread count: 1" in line for line in result.stdout.splitlines())
        until(hydrated, "Restarted app did not publish hydrated history")
        with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
            assert connection.execute("SELECT id, title FROM threads").fetchall() == original
            assert connection.execute("SELECT COUNT(*) FROM resources WHERE kind = 'terminal'").fetchone()[0] == 0
            assert original_decisions <= {row[0] for row in connection.execute("SELECT id FROM decision_records")}
            assert original_applications <= {row[0] for row in connection.execute("SELECT id FROM membership_applications")}
            assert original_transitions <= {row[0] for row in connection.execute("SELECT id FROM transition_applications")}
            assert connection.execute("SELECT COUNT(*) FROM resource_reassignments").fetchone()[0] == 0, "Restart recorded a user reassignment"
        focus_report = json.loads(subprocess.run([sys.executable, str(root / "scripts/report-transition-applications.py"), str(database)],
                                                capture_output=True, text=True, check=True).stdout)
        assert focus_report["all"]["counts"]["activated"] >= 1
        assert focus_report["all"]["counts"]["switched"] == 0
        assert focus_report["byPhase"]["context"]["counts"]["activated"] >= 1
        assert focus_report["all"]["activationRoutingCounts"]["local"] >= 1
        assert focus_report["all"]["switchRoutingCounts"]["local"] == 0
        assert focus_report["recordingCompleteness"] == "unknown"
        correction_report = json.loads(subprocess.run([sys.executable, str(root / "scripts/report-resource-reassignments.py"), str(database)],
                                                     capture_output=True, text=True, check=True).stdout)
        assert correction_report["all"]["recordCount"] == 0
        assert all(value is None for value in correction_report["all"]["inferredRoutingPercentages"].values())
        assert correction_report["recordingCompleteness"] == "unknown"
        print("Actual app: durable graph/cwd, snapshots, decisions, membership and activation outcomes saved; no terminal session persisted; same Thread/decision/application/transition IDs retained after restart.")
    finally:
        stop(process)
