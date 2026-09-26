#!/usr/bin/env python3
"""Summarize inferred focus policy outcomes without reading activity or Thread identities."""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sqlite3
import sys
import time

OUTCOMES = ('activated', 'switched', 'deferred', 'alreadyActive', 'declined', 'confidenceRejected', 'staleTime', 'obsoleteContext')
PHASES = ('context', 'review')
ORIGINS = ('local', 'remote', 'localFallback', 'unknown')
LIMIT = 100_000


def summarize(rows):
    counts = {outcome: 0 for outcome in OUTCOMES}
    routing = {origin: 0 for origin in ORIGINS}
    switches = routing.copy()
    activations = routing.copy()
    for phase, outcome, origin in rows:
        origin = origin or 'unknown'
        if origin not in routing:
            raise ValueError('Invalid routing category')
        routing[origin] += 1
        if outcome == 'switched':
            switches[origin] += 1
        if outcome == 'activated':
            activations[origin] += 1
        if phase not in PHASES or outcome not in counts:
            raise ValueError('Invalid transition category')
        counts[outcome] += 1
    total = len(rows)
    return {
        'recordCount': total,
        'routingCounts': routing,
        'switchRoutingCounts': switches,
        'activationRoutingCounts': activations,
        'counts': counts,
        'percentages': {outcome: round(100 * count / total, 2) if total else None
                        for outcome, count in counts.items()},
    }


def report(database, start, end):
    uri = database.resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(uri, uri=True, timeout=2) as connection:
        connection.execute('PRAGMA query_only = ON')
        deadline = time.monotonic() + 2
        connection.set_progress_handler(lambda: int(time.monotonic() > deadline), 1000)
        rows = connection.execute('''
            SELECT a.phase, a.outcome, d.origin FROM transition_applications a
            LEFT JOIN decision_records d ON a.decision_record_id = d.id AND d.kind = 'transition'
            WHERE a.timestamp >= ? AND a.timestamp <= ?
            ORDER BY a.timestamp DESC, a.id DESC LIMIT ?
            ''', (start.timestamp(), end.timestamp(), LIMIT + 1)).fetchall()
    truncated = len(rows) > LIMIT
    rows = rows[:LIMIT]
    return {
        'windowStartUTC': start.isoformat(),
        'windowEndUTC': end.isoformat(),
        'sampleTruncated': truncated,
        'recordingCompleteness': 'unknown',
        'all': summarize(rows),
        'byPhase': {phase: summarize([row for row in rows if row[0] == phase]) for phase in PHASES},
        'interpretation': 'Recorded inferred focus policy evaluations. Activated is initial focus; switched is a change between Threads. Context and review are separate evaluations, not provider request counts. Routing uses exact retained transition receipts; missing links are unknown. Not accuracy, false/missed switches, manual selection, durable commits or provider benefit.',
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
        print('Transition application report unavailable: check database schema, access and time arguments.', file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
