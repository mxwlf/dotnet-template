#!/usr/bin/env python3
"""Validate dependency-review exceptions and emit a comma-separated GHSA list."""
import datetime
import json
import re
import sys
from pathlib import Path


def main():
    entries = json.loads(Path('.github/security-exceptions.json').read_text(encoding='utf-8'))
    if not isinstance(entries, list):
        raise ValueError('exceptions must be a list')
    ids = []
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {'id', 'reason', 'expires'}:
            raise ValueError('each exception needs id, reason and expires')
        advisory = entry['id']
        if not isinstance(advisory, str) or not re.fullmatch(r'GHSA-[23456789cfghjmpqrvwx]{4}-[23456789cfghjmpqrvwx]{4}-[23456789cfghjmpqrvwx]{4}', advisory):
            raise ValueError('invalid advisory ID')
        if advisory in ids or not isinstance(entry['reason'], str) or not entry['reason'].strip():
            raise ValueError('duplicate advisory or missing reason')
        if not isinstance(entry['expires'], str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', entry['expires']):
            raise ValueError('expiry must be YYYY-MM-DD')
        if datetime.date.fromisoformat(entry['expires']) < datetime.datetime.now(datetime.timezone.utc).date():
            raise ValueError(f'expired exception: {advisory}')
        ids.append(advisory)
    print(','.join(ids))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, TypeError) as error:
        print(f'security exceptions: {error}', file=sys.stderr)
        sys.exit(1)
