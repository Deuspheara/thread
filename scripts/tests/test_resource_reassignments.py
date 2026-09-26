"""Focused correction report checks; no app build, user history or remote requests."""
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

SCRIPT = Path(__file__).resolve().parents[1] / 'report-resource-reassignments.py'
spec = importlib.util.spec_from_file_location('reassignments', SCRIPT)
reassignments = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reassignments)


class ResourceReassignmentReportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.database = Path(self.temporary.name) / 'fixture.sqlite'
        self.end = datetime(2026, 9, 26, tzinfo=timezone.utc)
        with sqlite3.connect(self.database) as connection:
            connection.execute('''CREATE TABLE resource_reassignments (
                id TEXT PRIMARY KEY, timestamp REAL, resource_kind TEXT, origin TEXT, status TEXT, outcome TEXT,
                decision_record_id TEXT, source_thread_id TEXT, target_thread_id TEXT)''')
            connection.execute('CREATE INDEX reassignment_timestamp ON resource_reassignments(timestamp)')
            connection.execute('''CREATE TABLE decision_records (
                id TEXT PRIMARY KEY, timestamp REAL, origin TEXT, kind TEXT, payload BLOB)''')

    def decision(self, identity, origin, kind='membership', offset=0):
        with sqlite3.connect(self.database) as connection:
            connection.execute('INSERT INTO decision_records VALUES (?, ?, ?, ?, ?)',
                (identity, self.end.timestamp() + offset, origin, kind, b'PRIVATE_PAYLOAD'))

    def correction(self, identity, receipt=None, origin='inferred', kind='file', status='confirmed', outcome='moved', offset=0):
        with sqlite3.connect(self.database) as connection:
            connection.execute('INSERT INTO resource_reassignments VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                (identity, self.end.timestamp() + offset, kind, origin, status, outcome, receipt, 'PRIVATE_SOURCE', 'PRIVATE_TARGET'))

    def report(self):
        return reassignments.report(self.database, self.end - timedelta(days=7), self.end)

    def test_exact_links_unknowns_manual_confirmation_and_read_only_cli(self):
        self.decision('local', 'local', offset=-10 * 86400)
        self.decision('remote', 'remote')
        self.decision('fallback', 'localFallback')
        self.decision('wrong-kind', 'remote', kind='transition')
        self.decision('same-time-unreferenced', 'remote')
        self.correction('local-1', 'local')
        self.correction('local-2', 'local', kind='repository')
        self.correction('remote-1', 'remote')
        self.correction('fallback-1', 'fallback', status='provisional')
        self.correction('legacy')
        self.correction('missing', 'removed')
        self.correction('wrong', 'wrong-kind')
        self.correction('manual', origin='explicit', kind='workingDirectory', outcome='confirmed')
        self.correction('old', 'remote', offset=-8 * 86400)
        self.correction('future', 'remote', offset=1)
        before = hashlib.sha256(self.database.read_bytes()).digest()
        output = subprocess.run([sys.executable, str(SCRIPT), str(self.database), '--as-of', self.end.isoformat()],
                                capture_output=True, text=True, check=True).stdout
        result = json.loads(output)
        self.assertEqual(result['all']['recordCount'], 8)
        self.assertEqual(result['all']['priorAssignmentCounts'], {'inferred': 7, 'explicit': 1})
        self.assertEqual(result['all']['outcomeCounts'], {'moved': 7, 'confirmed': 1})
        self.assertEqual(result['all']['intentCounts'], {'inferredMove': 7, 'explicitMove': 0, 'inferredConfirmation': 0, 'explicitConfirmation': 1})
        self.assertEqual(result['all']['priorStatusCounts'], {'confirmed': 7, 'provisional': 1})
        self.assertEqual(result['all']['inferredRoutingCounts'], {'local': 2, 'remote': 1, 'localFallback': 1, 'unknown': 3})
        self.assertEqual(result['all']['inferredRoutingPercentages']['unknown'], 42.86)
        self.assertEqual(result['byResourceKind']['workingDirectory']['inferredRoutingCounts']['unknown'], 0)
        self.assertIsNone(result['byResourceKind']['workingDirectory']['inferredRoutingPercentages']['local'])
        self.assertNotIn('PRIVATE', output)
        self.assertEqual(hashlib.sha256(self.database.read_bytes()).digest(), before)

    def test_only_join_and_category_columns_are_read(self):
        self.decision('local', 'local')
        self.correction('sample', 'local')
        connect = sqlite3.connect
        allowed = {
            'resource_reassignments': {'id', 'timestamp', 'resource_kind', 'origin', 'status', 'outcome', 'decision_record_id'},
            'decision_records': {'id', 'kind', 'origin'},
        }
        reads = set()
        def restricted_connection(*args, **kwargs):
            connection = connect(*args, **kwargs)
            def authorize(action, table, column, *unused):
                if action == sqlite3.SQLITE_READ:
                    reads.add((table, column))
                    if column not in allowed.get(table, set()):
                        return sqlite3.SQLITE_DENY
                return sqlite3.SQLITE_OK
            connection.set_authorizer(authorize)
            return connection
        with patch.object(reassignments.sqlite3, 'connect', restricted_connection):
            self.assertEqual(self.report()['all']['inferredRoutingCounts']['local'], 1)
        self.assertEqual(reads, {(table, column) for table, columns in allowed.items() for column in columns})

    def test_empty_missing_file_schema_and_naive_time_are_explicit(self):
        result = self.report()
        self.assertEqual(result['all']['recordCount'], 0)
        self.assertTrue(all(value is None for value in result['all']['inferredRoutingPercentages'].values()))
        missing = self.database.with_name('missing.sqlite')
        for path, arguments in [(missing, []), (self.database, ['--as-of', '2026-09-26T00:00:00'])]:
            output = subprocess.run([sys.executable, str(SCRIPT), str(path), *arguments], capture_output=True, text=True)
            self.assertEqual(output.returncode, 1)
            self.assertNotIn(str(path), output.stderr)
        self.assertFalse(missing.exists())
        with sqlite3.connect(self.database) as connection:
            connection.execute('DROP TABLE decision_records')
        output = subprocess.run([sys.executable, str(SCRIPT), str(self.database)], capture_output=True, text=True)
        self.assertEqual(output.returncode, 1)
        self.assertNotIn(str(self.database), output.stderr)

    def test_sample_cap_uses_latest_rows_without_claiming_completeness(self):
        for index in range(3):
            self.correction(str(index), offset=-index, origin='explicit' if index == 2 else 'inferred')
        with patch.object(reassignments, 'LIMIT', 2):
            result = self.report()
        self.assertTrue(result['sampleTruncated'])
        self.assertEqual(result['recordingCompleteness'], 'unknown')
        self.assertEqual(result['all']['priorAssignmentCounts'], {'inferred': 2, 'explicit': 0})

    def test_invalid_record_categories_and_joined_origins_fail_closed(self):
        cases = [{'kind': 'PRIVATE_KIND'}, {'origin': 'PRIVATE_ORIGIN'}, {'status': 'PRIVATE_STATUS'}, {'outcome': 'PRIVATE_OUTCOME'}]
        for index, arguments in enumerate(cases):
            with sqlite3.connect(self.database) as connection:
                connection.execute('DELETE FROM resource_reassignments')
            self.correction(str(index), **arguments)
            with self.assertRaises(ValueError):
                self.report()
        with sqlite3.connect(self.database) as connection:
            connection.execute('DELETE FROM resource_reassignments')
        self.decision('bad-origin', 'PRIVATE_PROVIDER_ORIGIN')
        self.correction('bad', 'bad-origin')
        output = subprocess.run([sys.executable, str(SCRIPT), str(self.database), '--as-of', self.end.isoformat()],
                                capture_output=True, text=True)
        self.assertEqual(output.returncode, 1)
        self.assertNotIn('PRIVATE', output.stderr)
        self.assertNotIn(str(self.database), output.stderr)


if __name__ == '__main__':
    unittest.main()
