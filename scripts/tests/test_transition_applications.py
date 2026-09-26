"""Focused focus-report checks, using only disposable SQLite fixtures."""
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'report-transition-applications.py'
spec = importlib.util.spec_from_file_location('transitions', SCRIPT)
transitions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transitions)


class TransitionApplicationsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.database = Path(self.temporary.name) / 'fixture.sqlite'
        self.end = datetime(2026, 9, 26, tzinfo=timezone.utc)
        with sqlite3.connect(self.database) as connection:
            connection.execute('''CREATE TABLE transition_applications (
                id TEXT PRIMARY KEY, timestamp REAL, phase TEXT, outcome TEXT,
                previous_thread_id TEXT, target_thread_id TEXT, decision_record_id TEXT)''')
            connection.execute('CREATE TABLE decision_records (id TEXT PRIMARY KEY, kind TEXT, origin TEXT, payload TEXT)')
            connection.execute('CREATE INDEX transition_applications_timestamp ON transition_applications(timestamp)')

    def insert(self, phase, outcome, offset=0, identifier=None, receipt=None):
        with sqlite3.connect(self.database) as connection:
            connection.execute('INSERT INTO transition_applications VALUES (?, ?, ?, ?, ?, ?, ?)',
                (identifier or phase + outcome, self.end.timestamp() + offset, phase, outcome,
                 'PRIVATE_PREVIOUS', 'PRIVATE_TARGET', receipt))

    def report(self):
        return transitions.report(self.database, self.end - timedelta(days=7), self.end)

    def test_review_is_not_an_extra_switch_and_cli_is_read_only(self):
        self.insert('context', 'activated', -3)
        self.insert('context', 'deferred', -2)
        self.insert('review', 'switched', -1)
        self.insert('context', 'obsoleteContext')
        self.insert('review', 'switched', -8 * 86400, 'old')
        self.insert('review', 'switched', 1, 'future')
        before = hashlib.sha256(self.database.read_bytes()).digest()
        output = subprocess.run([sys.executable, str(SCRIPT), str(self.database), '--as-of', self.end.isoformat()],
                                capture_output=True, text=True, check=True).stdout
        result = json.loads(output)
        self.assertEqual(result['all']['recordCount'], 4)
        self.assertEqual(result['all']['counts']['switched'], 1)
        self.assertEqual(result['all']['counts']['activated'], 1)
        self.assertEqual(result['all']['percentages']['switched'], 25)
        self.assertEqual(result['byPhase']['context']['recordCount'], 3)
        self.assertEqual(result['byPhase']['context']['counts']['switched'], 0)
        self.assertEqual(result['byPhase']['review']['percentages']['switched'], 100)
        self.assertNotIn('PRIVATE', output)
        self.assertEqual(hashlib.sha256(self.database.read_bytes()).digest(), before)

    def test_query_never_reads_thread_identities_or_other_tables(self):
        self.insert('context', 'alreadyActive')
        connect = sqlite3.connect
        reads = set()
        allowed = {('transition_applications', column) for column in
                   ['id', 'timestamp', 'phase', 'outcome', 'decision_record_id']}
        allowed |= {('decision_records', column) for column in ['id', 'kind', 'origin']}
        def restricted_connection(*args, **kwargs):
            connection = connect(*args, **kwargs)
            def authorize(action, table, column, *unused):
                if action == sqlite3.SQLITE_READ:
                    reads.add((table, column))
                    if (table, column) not in allowed:
                        return sqlite3.SQLITE_DENY
                return sqlite3.SQLITE_OK
            connection.set_authorizer(authorize)
            return connection
        with patch.object(transitions.sqlite3, 'connect', restricted_connection):
            self.assertEqual(self.report()['all']['counts']['alreadyActive'], 1)
        self.assertEqual(reads, allowed)

    def test_exact_receipts_attribute_switch_once_and_ignore_wrong_kind(self):
        with sqlite3.connect(self.database) as connection:
            connection.executemany('INSERT INTO decision_records VALUES (?, ?, ?, ?)', [
                ('first', 'transition', 'local', 'PRIVATE'),
                ('shared', 'transition', 'remote', 'PRIVATE'),
                ('wrong', 'membership', 'localFallback', 'PRIVATE'),
                ('unreferenced', 'transition', 'localFallback', 'PRIVATE')])
        self.insert('context', 'activated', -3, receipt='first')
        self.insert('context', 'deferred', -2, receipt='shared')
        self.insert('review', 'switched', -1, receipt='shared')
        self.insert('context', 'declined', receipt='wrong')
        self.insert('context', 'alreadyActive', receipt='missing')
        result = self.report()['all']
        self.assertEqual(result['routingCounts'],
                         dict(local=1, remote=2, localFallback=0, unknown=2))
        self.assertEqual(result['switchRoutingCounts'],
                         dict(local=0, remote=1, localFallback=0, unknown=0))
        self.assertEqual(result['activationRoutingCounts']['local'], 1)

    def test_empty_missing_schema_and_missing_storage_are_explicit(self):
        result = self.report()
        for group in [result['all'], *result['byPhase'].values()]:
            self.assertEqual(group['recordCount'], 0)
            self.assertTrue(all(value is None for value in group['percentages'].values()))
        missing = self.database.with_name('missing.sqlite')
        for path in [missing, self.database]:
            if path == self.database:
                with sqlite3.connect(path) as connection:
                    connection.execute('DROP TABLE transition_applications')
            output = subprocess.run([sys.executable, str(SCRIPT), str(path)], capture_output=True, text=True)
            self.assertEqual(output.returncode, 1)
            self.assertNotIn(str(path), output.stderr)
        self.assertFalse(missing.exists())

    def test_limit_marks_partial_latest_sample_without_claiming_completeness(self):
        self.insert('context', 'activated', -2)
        self.insert('context', 'deferred', -1)
        self.insert('review', 'switched')
        with patch.object(transitions, 'LIMIT', 2):
            result = self.report()
        self.assertTrue(result['sampleTruncated'])
        self.assertEqual(result['recordingCompleteness'], 'unknown')
        self.assertEqual(result['all']['recordCount'], 2)
        self.assertEqual(result['all']['counts']['activated'], 0)
        self.assertEqual(result['all']['counts']['switched'], 1)

    def test_invalid_phase_outcome_and_naive_time_fail_with_bounded_errors(self):
        for phase, outcome in [('PRIVATE_PHASE', 'switched'), ('context', 'PRIVATE_OUTCOME')]:
            with sqlite3.connect(self.database) as connection:
                connection.execute('DELETE FROM transition_applications')
            self.insert(phase, outcome)
            output = subprocess.run([sys.executable, str(SCRIPT), str(self.database), '--as-of', self.end.isoformat()],
                                    capture_output=True, text=True)
            self.assertEqual(output.returncode, 1)
            self.assertNotIn('PRIVATE', output.stderr)
            self.assertNotIn(str(self.database), output.stderr)
        output = subprocess.run([sys.executable, str(SCRIPT), str(self.database), '--as-of', '2026-09-26T00:00:00'],
                                capture_output=True, text=True)
        self.assertEqual(output.returncode, 1)
        self.assertNotIn(str(self.database), output.stderr)


if __name__ == '__main__':
    unittest.main()
