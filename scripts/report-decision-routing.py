#!/usr/bin/env python3
"""Report bounded local inference routing metadata; never read activity payloads."""
import argparse
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import sqlite3
import sys
import time

ORIGINS = ('local', 'remote', 'localFallback')
KINDS = ('membership', 'transition', 'persistence')
LIMIT = 100_000


def summarize(rows):
    counts = {origin: 0 for origin in ORIGINS}
    elapsed = 0.0
    for origin, kind, milliseconds in rows:
        if origin not in ORIGINS or kind not in KINDS:
            raise ValueError('Invalid decision category')
        if not isinstance(milliseconds, (int, float)) or not math.isfinite(milliseconds) or not 0 <= milliseconds <= 3_600_000:
            raise ValueError('Invalid elapsed time')
        counts[origin] += 1
        elapsed += milliseconds
    total = len(rows)
    def percent(count):
        return round(100 * count / total, 2) if total else None
    return {
        'recordCount': total,
        'counts': counts,
        'localResultPercent': percent(counts['local'] + counts['localFallback']),
        'remoteResultPercent': percent(counts['remote']),
        'fallbackPercent': percent(counts['localFallback']),
        'meanRoutingMilliseconds': round(elapsed / total, 3) if total else None,
    }


def report(database, start, end):
    uri = database.resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(uri, uri=True, timeout=2) as connection:
        connection.execute('PRAGMA query_only = ON')
        deadline = time.monotonic() + 2
        connection.set_progress_handler(lambda: int(time.monotonic() > deadline), 1000)
        rows = connection.execute('''
            SELECT origin, kind, elapsed_milliseconds FROM decision_records
            WHERE timestamp >= ? AND timestamp <= ?
            ORDER BY timestamp DESC, id DESC LIMIT ?
            ''', (start.timestamp(), end.timestamp(), LIMIT + 1)).fetchall()
    truncated = len(rows) > LIMIT
    rows = rows[:LIMIT]
    return {
        'windowStartUTC': start.isoformat(),
        'windowEndUTC': end.isoformat(),
        'sampleTruncated': truncated,
        'recordingCompleteness': 'unknown',
        'all': summarize(rows),
        'byKind': {kind: summarize([row for row in rows if row[1] == kind]) for kind in KINDS},
        'interpretation': 'Inference routing only. Not applied assignments, accuracy, correction rates, false/missed switches or provider benefit.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('database', type=Path, help='Existing Thread.sqlite; opened read-only')
    parser.add_argument('--days', type=int, choices=range(1, 31), default=7, metavar='1..30')
    parser.add_argument('--as-of', help='ISO-8601 timestamp with timezone; defaults to now (UTC)')
    args = parser.parse_args()
    try:
        end = datetime.fromisoformat(args.as_of) if args.as_of else datetime.now(timezone.utc)
        if end.tzinfo is None:
            raise ValueError('Timezone required')
        end = end.astimezone(timezone.utc)
        result = report(args.database, end - timedelta(days=args.days), end)
    except (sqlite3.Error, OSError, ValueError, OverflowError):
        print('Decision routing report unavailable: check database schema, access and time arguments.', file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
