#!/usr/bin/env python3
"""Summarize bounded local graph membership outcomes without reading activity or Thread identities."""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sqlite3
import sys
import time

OUTCOMES = ('waiting', 'confirmedAttachment', 'provisionalAttachment', 'noAttachment')
ORIGINS = ('local', 'remote', 'localFallback', 'unknown')
LIMIT = 100_000


def summarize(rows):
    counts = {outcome: 0 for outcome in OUTCOMES}
    routing = {origin: 0 for origin in ORIGINS}
    by_outcome = {outcome: routing.copy() for outcome in OUTCOMES}
    for outcome, origin in rows:
        origin = origin or 'unknown'
        if origin not in routing:
            raise ValueError('Invalid routing category')
        if outcome not in counts:
            raise ValueError('Invalid membership outcome')
        counts[outcome] += 1
        routing[origin] += 1
        by_outcome[outcome][origin] += 1
    return counts, routing, by_outcome


def report(database, start, end):
    uri = database.resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(uri, uri=True, timeout=2) as connection:
        connection.execute('PRAGMA query_only = ON')
        deadline = time.monotonic() + 2
        connection.set_progress_handler(lambda: int(time.monotonic() > deadline), 1000)
        rows = connection.execute('''
            SELECT a.outcome, d.origin FROM membership_applications a
            LEFT JOIN decision_records d ON a.decision_record_id = d.id AND d.kind = 'membership'
            WHERE a.timestamp >= ? AND a.timestamp <= ?
            ORDER BY a.timestamp DESC, a.id DESC LIMIT ?
            ''', (start.timestamp(), end.timestamp(), LIMIT + 1)).fetchall()
    truncated = len(rows) > LIMIT
    rows = rows[:LIMIT]
    counts, routing, by_outcome = summarize(rows)
    total = len(rows)
    return {
        'windowStartUTC': start.isoformat(),
        'windowEndUTC': end.isoformat(),
        'recordCount': total,
        'sampleTruncated': truncated,
        'recordingCompleteness': 'unknown',
        'counts': counts,
        'routingCounts': routing,
        'routingByOutcome': by_outcome,
        'percentages': {outcome: round(100 * count / total, 2) if total else None
                        for outcome, count in counts.items()},
        'interpretation': 'Recorded live-graph membership acceptance per context. Routing uses exact retained membership receipts; missing links are unknown. Not unique resources, durable commits, active switches, accuracy, correction rates or provider benefit.',
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
        print('Membership application report unavailable: check database schema, access and time arguments.', file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
