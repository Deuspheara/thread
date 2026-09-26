"""Focused reporting checks; run directly, without building the app."""
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'report-decision-routing.py'
spec = importlib.util.spec_from_file_location('routing', SCRIPT)
routing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(routing)


class DecisionRoutingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.database = Path(self.temporary.name) / 'fixture.sqlite'
        self.end = datetime(2026, 9, 26, tzinfo=timezone.utc)
        with sqlite3.connect(self.database) as connection:
            connection.execute('''CREATE TABLE decision_records (
                id TEXT PRIMARY KEY, timestamp REAL, origin TEXT, kind TEXT,
                elapsed_milliseconds REAL, payload BLOB)''')
            connection.execute('CREATE INDEX decision_records_timestamp ON decision_records(timestamp)')

    def insert(self, rows):
        with sqlite3.connect(self.database) as connection:
            connection.executemany('INSERT INTO decision_records VALUES (?, ?, ?, ?, ?, ?)', rows)

    def test_window_rates_and_read_only_cli(self):
        now = self.end.timestamp()
        self.insert([
            ('a', now, 'local', 'membership', 100, b'SENSITIVE_PAYLOAD'),
            ('b', now, 'remote', 'membership', 200, b'SENSITIVE_PAYLOAD'),
            ('c', now, 'localFallback', 'transition', 300, b'SENSITIVE_PAYLOAD'),
            ('old', now - 8 * 86400, 'remote', 'persistence', 999, b''),
            ('future', now + 1, 'remote', 'persistence', 999, b''),
        ])
        before = hashlib.sha256(self.database.read_bytes()).digest()
        result = routing.report(self.database, self.end - timedelta(days=7), self.end)
        self.assertEqual(result['all']['recordCount'], 3)
        self.assertEqual(result['all']['meanRoutingMilliseconds'], 200)
        self.assertEqual(result['all']['localResultPercent'], 66.67)
        self.assertEqual(result['all']['remoteResultPercent'], 33.33)
        self.assertEqual(result['all']['fallbackPercent'], 33.33)
        self.assertEqual(result['byKind']['membership']['remoteResultPercent'], 50)
        output = subprocess.run([sys.executable, str(SCRIPT), str(self.database), '--as-of', self.end.isoformat()],
                                capture_output=True, text=True, check=True).stdout
        self.assertNotIn('SENSITIVE_PAYLOAD', output)
        self.assertEqual(hashlib.sha256(self.database.read_bytes()).digest(), before)

    def test_empty_and_missing_database_are_not_zero_latency_or_new_storage(self):
        result = routing.report(self.database, self.end - timedelta(days=1), self.end)
        self.assertIsNone(result['all']['meanRoutingMilliseconds'])
        self.assertIsNone(result['all']['remoteResultPercent'])
        missing = self.database.with_name('missing.sqlite')
        output = subprocess.run([sys.executable, str(SCRIPT), str(missing)], capture_output=True, text=True)
        self.assertEqual(output.returncode, 1)
        self.assertFalse(missing.exists())
        self.assertNotIn(str(missing), output.stderr)

    def test_record_cap_marks_partial_sample(self):
        self.insert((str(index), self.end.timestamp(), 'local', 'membership', 1, b'')
                    for index in range(routing.LIMIT + 1))
        result = routing.report(self.database, self.end - timedelta(days=1), self.end)
        self.assertTrue(result['sampleTruncated'])
        self.assertEqual(result['all']['recordCount'], routing.LIMIT)
        self.assertEqual(result['recordingCompleteness'], 'unknown')


if __name__ == '__main__':
    unittest.main()
