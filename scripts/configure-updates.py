#!/usr/bin/env python3
"""Add caller-supplied public update configuration; never create keys or endpoints."""
import base64
import os
from pathlib import Path
import plistlib
import sys
from urllib.parse import urlsplit


def configuration(feed, key):
    if feed is None and key is None:
        return {}
    if not feed or not key:
        raise ValueError('Both public configuration values are required')
    url = urlsplit(feed)
    if len(feed.encode()) > 2048 or url.scheme != 'https' or not url.hostname or url.username is not None or url.password is not None or '?' in feed or '#' in feed or not all(33 <= ord(c) <= 126 for c in feed) or (url.port is not None and not 1 <= url.port <= 65535):
        raise ValueError('Invalid update feed')
    decoded = base64.b64decode(key, validate=True)
    if len(decoded) != 32 or base64.b64encode(decoded).decode() != key:
        raise ValueError('Invalid public key')
    return {'SUFeedURL': feed, 'SUPublicEDKey': key}


def main():
    try:
        public = configuration(os.environ.get('THREAD_UPDATE_FEED_URL'), os.environ.get('THREAD_UPDATE_PUBLIC_KEY'))
        path = Path(sys.argv[1])
        value = plistlib.loads(path.read_bytes())
        for field in ('SUFeedURL', 'SUPublicEDKey'):
            value.pop(field, None)
        value.update(public)
        path.write_bytes(plistlib.dumps(value, sort_keys=False))
    except (ValueError, OSError, IndexError):
        print('Update configuration unavailable: provide a valid HTTPS feed and public Ed25519 key together.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
