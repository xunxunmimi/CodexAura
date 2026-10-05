#!/usr/bin/env python3
# Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
"""Fail packaging if a bundle leaks personal absolute development paths."""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('Usage: check_release_paths.py APP_BUNDLE')
root = Path(sys.argv[1])
if not root.is_dir() or root.suffix != '.app':
    raise SystemExit('Expected an existing .app bundle')
bad = []
for file in root.rglob('*'):
    if file.is_symlink():
        raise SystemExit('Unexpected symlink in release bundle')
    if not file.is_file():
        continue
    with file.open('rb') as stream:
        tail = b''
        while chunk := stream.read(1024 * 1024):
            data = tail + chunk
            if b'/Users/' in data:
                bad.append(str(file.relative_to(root)))
                break
            tail = data[-16:]
if bad:
    print('Personal path strings found in these bundle files:', file=sys.stderr)
    for name in bad:
        print(name, file=sys.stderr)
    raise SystemExit(1)
print('Release bundle personal-path scan passed')
