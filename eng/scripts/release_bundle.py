#!/usr/bin/env python3
"""Create and check an unsigned, portable release bundle."""
import argparse
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path


def files_under(root):
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f'not a regular directory: {root}')
    result = []
    for directory, names, filenames in os.walk(root, followlinks=False):
        base = Path(directory)
        for name in names:
            if (base / name).is_symlink():
                raise ValueError(f'symbolic links are not supported: {base / name}')
        for name in filenames:
            path = base / name
            if path.is_symlink() or not path.is_file():
                raise ValueError(f'not a regular file: {path}')
            result.append(path.relative_to(root).as_posix())
    return sorted(result)


def describe(root, paths):
    entries = []
    for name in paths:
        path = root / name
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        entries.append({'path': name, 'size': path.stat().st_size, 'sha256': digest.hexdigest()})
    return entries


def create(args):
    source = args.input.resolve()
    output = args.output.absolute()
    if args.input.is_symlink() or source == output.resolve() or source in output.resolve().parents or output.resolve() in source.parents:
        raise ValueError('input and output must be separate directories, and input cannot be a symlink')
    if not args.version.strip() or not args.commit.strip():
        raise ValueError('version and source commit are required')
    paths = files_under(source)
    if not paths:
        raise ValueError('input must contain at least one file')
    output.mkdir(parents=True, exist_ok=False)
    try:
        payload = output / 'files'
        payload.mkdir()
        for name in paths:
            target = payload / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / name, target)
        manifest = {'schema_version': 1, 'version': args.version, 'source_commit': args.commit,
                    'files': describe(payload, paths)}
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    except Exception:
        shutil.rmtree(output)
        raise
    print(f'Created {output}')


def verify(args):
    root = args.bundle
    if root.is_symlink() or not root.is_dir():
        raise ValueError('bundle must be a regular directory')
    if {p.name for p in root.iterdir()} != {'manifest.json', 'files'}:
        raise ValueError('bundle must contain only manifest.json and files/')
    manifest_path = root / 'manifest.json'
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ValueError('manifest must be a regular file')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if (not isinstance(manifest, dict) or manifest.get('schema_version') != 1
            or not isinstance(manifest.get('version'), str) or not manifest['version'].strip()
            or not isinstance(manifest.get('source_commit'), str) or not manifest['source_commit'].strip()):
        raise ValueError('invalid bundle metadata')
    payload = root / 'files'
    paths = files_under(payload)
    if not paths or manifest.get('files') != describe(payload, paths):
        raise ValueError('payload does not match the manifest')
    print(f'Verified {root}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    new = commands.add_parser('create')
    new.add_argument('--input', type=Path, required=True)
    new.add_argument('--output', type=Path, required=True)
    new.add_argument('--version', required=True)
    new.add_argument('--commit', required=True)
    new.set_defaults(run=create)
    check = commands.add_parser('verify')
    check.add_argument('bundle', type=Path)
    check.set_defaults(run=verify)
    args = parser.parse_args()
    try:
        args.run(args)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f'release bundle: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
