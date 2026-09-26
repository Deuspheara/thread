"""Focused read-only membership report checks; no Swift build or provider request."""
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

SCRIPT = Path(__file__).resolve().parents[1] / 'report-membership-applications.py'
spec = importlib.util.spec_from_file_location('applications', SCRIPT)
applications = importlib.util.module_from_spec(spec)
spec.loader.exec_module(applications)


class MembershipApplicationsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.database = Path(self.temporary.name) / 'fixture.sqlite'
        self.end = datetime(2026, 9, 26, tzinfo=timezone.utc)
        with sqlite3.connect(self.database) as connection:
            connection.execute('''CREATE TABLE membership_applications (
                id TEXT PRIMARY KEY, timestamp REAL, outcome TEXT, thread_id TEXT, decision_record_id TEXT)''')
            connection.execute('CREATE INDEX membership_applications_timestamp ON membership_applications(timestamp)')
            connection.execute('CREATE TABLE decision_records (id TEXT PRIMARY KEY, timestamp REAL, kind TEXT, origin TEXT, payload BLOB)')

    def insert(self, rows):
        with sqlite3.connect(self.database) as connection:
            connection.executemany('INSERT INTO membership_applications (id, timestamp, outcome, thread_id) VALUES (?, ?, ?, ?)', rows)

    def test_window_counts_read_only_and_no_thread_identity(self):
        now = self.end.timestamp()
        self.insert([(str(index), now, outcome, 'PRIVATE_THREAD_ID')
                     for index, outcome in enumerate(applications.OUTCOMES)] + [
            ('old', now - 8 * 86400, 'confirmedAttachment', 'PRIVATE_THREAD_ID'),
            ('future', now + 1, 'confirmedAttachment', 'PRIVATE_THREAD_ID'),
        ])
        before = hashlib.sha256(self.database.read_bytes()).digest()
        output = subprocess.run([sys.executable, str(SCRIPT), str(self.database), '--as-of', self.end.isoformat()],
                                capture_output=True, text=True, check=True).stdout
        result = json.loads(output)
        self.assertEqual(result['recordCount'], 4)
        self.assertEqual(result['counts'], {outcome: 1 for outcome in applications.OUTCOMES})
        self.assertEqual(result['percentages'], {outcome: 25 for outcome in applications.OUTCOMES})
        self.assertNotIn('PRIVATE_THREAD_ID', output)
        self.assertEqual(hashlib.sha256(self.database.read_bytes()).digest(), before)

    def test_empty_missing_schema_and_missing_file_do_not_claim_zero_or_create_storage(self):
        result = applications.report(self.database, self.end - timedelta(days=1), self.end)
        self.assertTrue(all(value is None for value in result['percentages'].values()))
        missing = self.database.with_name('missing.sqlite')
        for path in [missing, self.database]:
            if path == self.database:
                with sqlite3.connect(path) as connection:
                    connection.execute('DROP TABLE membership_applications')
            output = subprocess.run([sys.executable, str(SCRIPT), str(path)], capture_output=True, text=True)
            self.assertEqual(output.returncode, 1)
            self.assertNotIn(str(path), output.stderr)
        self.assertFalse(missing.exists())

    def test_cap_uses_latest_records_and_marks_incomplete_sample(self):
        self.insert([(str(index), self.end.timestamp() - index, outcome, None)
                     for index, outcome in enumerate(applications.OUTCOMES)])
        with patch.object(applications, 'LIMIT', 2):
            result = applications.report(self.database, self.end - timedelta(days=1), self.end)
        self.assertTrue(result['sampleTruncated'])
        self.assertEqual(result['recordCount'], 2)
        self.assertEqual(result['counts']['waiting'], 1)
        self.assertEqual(result['counts']['confirmedAttachment'], 1)
        self.assertEqual(result['counts']['provisionalAttachment'], 0)
        self.assertEqual(result['recordingCompleteness'], 'unknown')

    def test_exact_receipts_attribute_outcomes_without_timestamp_guessing(self):
        now = self.end.timestamp()
        with sqlite3.connect(self.database) as connection:
            connection.executemany('INSERT INTO decision_records VALUES (?, ?, ?, ?, ?)', [
                ('local', now - 40 * 86400, 'membership', 'local', b'PRIVATE_PAYLOAD'),
                ('remote', now, 'membership', 'remote', b'PRIVATE_PAYLOAD'),
                ('fallback', now, 'membership', 'localFallback', b'PRIVATE_PAYLOAD'),
                ('wrong-kind', now, 'transition', 'remote', b'PRIVATE_PAYLOAD'),
            ])
            connection.executemany('INSERT INTO membership_applications VALUES (?, ?, ?, ?, ?)', [
                ('a', now, 'confirmedAttachment', 'PRIVATE_THREAD', 'local'),
                ('b', now, 'provisionalAttachment', 'PRIVATE_THREAD', 'remote'),
                ('c', now, 'waiting', 'PRIVATE_THREAD', 'fallback'),
                ('d', now, 'noAttachment', 'PRIVATE_THREAD', 'wrong-kind'),
                ('e', now, 'waiting', 'PRIVATE_THREAD', 'missing'),
                ('f', now, 'confirmedAttachment', 'PRIVATE_THREAD', None),
            ])
        result = applications.report(self.database, self.end - timedelta(days=1), self.end)
        self.assertEqual(result['routingCounts'], dict(local=1, remote=1, localFallback=1, unknown=3))
        self.assertEqual(result['routingByOutcome']['confirmedAttachment']['local'], 1)
        self.assertEqual(result['routingByOutcome']['confirmedAttachment']['unknown'], 1)
        self.assertEqual(result['routingByOutcome']['provisionalAttachment']['remote'], 1)
        self.assertEqual(result['routingByOutcome']['noAttachment']['unknown'], 1)
        output = json.dumps(result)
        self.assertNotIn('PRIVATE', output)
        self.assertNotIn('wrong-kind', output)

    def test_invalid_category_and_timezone_fail_without_sensitive_diagnostics(self):
        self.insert([('private-record', self.end.timestamp(), 'PRIVATE_INVALID_OUTCOME', 'PRIVATE_THREAD_ID')])
        for arguments in [['--as-of', self.end.isoformat()], ['--as-of', '2026-09-26T00:00:00']]:
            output = subprocess.run([sys.executable, str(SCRIPT), str(self.database), *arguments], capture_output=True, text=True)
            self.assertEqual(output.returncode, 1)
            self.assertNotIn('PRIVATE', output.stderr)
            self.assertNotIn(str(self.database), output.stderr)


if __name__ == '__main__':
    unittest.main()
