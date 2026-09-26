#!/usr/bin/env python3
"""Summarize explicit reassignment metadata with exact retained inference provenance, read-only."""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sqlite3
import sys
import time

KINDS = ('application', 'window', 'browserPage', 'terminal', 'workingDirectory', 'repository', 'branch', 'file')
ORIGINS = ('inferred', 'explicit')
STATUSES = ('confirmed', 'provisional')
OUTCOMES = ('moved', 'confirmed')
ROUTING = ('local', 'remote', 'localFallback', 'unknown')
INTENTS = ('inferredMove', 'explicitMove', 'inferredConfirmation', 'explicitConfirmation')
LIMIT = 100_000


def summarize(rows):
    origins = dict.fromkeys(ORIGINS, 0)
    statuses = dict.fromkeys(STATUSES, 0)
    outcomes = dict.fromkeys(OUTCOMES, 0)
    routing = dict.fromkeys(ROUTING, 0)
    intents = dict.fromkeys(INTENTS, 0)
    for kind, origin, status, outcome, decision_origin in rows:
        if kind not in KINDS or origin not in origins or status not in statuses or outcome not in outcomes:
            raise ValueError('Invalid reassignment category')
        origins[origin] += 1
        statuses[status] += 1
        outcomes[outcome] += 1
        intents[origin + ('Move' if outcome == 'moved' else 'Confirmation')] += 1
        if origin == 'inferred':
            source = decision_origin if decision_origin is not None else 'unknown'
            if source not in ROUTING or decision_origin == 'unknown':
                raise ValueError('Invalid inference origin')
            routing[source] += 1
        elif decision_origin is not None:
            raise ValueError('Unexpected explicit inference attribution')
    inferred = origins['inferred']
    return {
        'recordCount': len(rows), 'priorAssignmentCounts': origins,
        'priorStatusCounts': statuses, 'outcomeCounts': outcomes, 'intentCounts': intents,
        'inferredRoutingCounts': routing,
        'inferredRoutingPercentages': {origin: round(100 * count / inferred, 2) if inferred else None
                                      for origin, count in routing.items()},
    }


def report(database, start, end):
    with sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True, timeout=2) as connection:
        connection.execute('PRAGMA query_only = ON')
        deadline = time.monotonic() + 2
        connection.set_progress_handler(lambda: int(time.monotonic() > deadline), 1000)
        rows = connection.execute('''
            SELECT r.resource_kind, r.origin, r.status, r.outcome, d.origin
            FROM resource_reassignments r
            LEFT JOIN decision_records d ON r.origin = 'inferred'
                AND r.decision_record_id = d.id AND d.kind = 'membership'
            WHERE r.timestamp >= ? AND r.timestamp <= ?
            ORDER BY r.timestamp DESC, r.id DESC LIMIT ?
            ''', (start.timestamp(), end.timestamp(), LIMIT + 1)).fetchall()
    truncated = len(rows) > LIMIT
    rows = rows[:LIMIT]
    return {
        'windowStartUTC': start.isoformat(), 'windowEndUTC': end.isoformat(),
        'sampleTruncated': truncated, 'recordingCompleteness': 'unknown',
        'all': summarize(rows),
        'byResourceKind': {kind: summarize([row for row in rows if row[0] == kind]) for kind in KINDS},
        'interpretation': 'Recorded explicit Move intents and confirmations. Inferred routing uses exact retained membership IDs; missing links are unknown. Not unique resources, correction rate, accuracy, durable commits or provider benefit.',
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
        print('Reassignment report unavailable: check database schema, access and time arguments.', file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
