#!/usr/bin/env python3
"""Create and check an unsigned, portable release bundle."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
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
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    if (not isinstance(manifest, dict) or manifest.get('schema_version') != 1
            or not isinstance(manifest.get('version'), str) or not manifest['version'].strip()
            or not isinstance(manifest.get('source_commit'), str) or not manifest['source_commit'].strip()):
        raise ValueError('invalid bundle metadata')
    payload = root / 'files'
    paths = files_under(payload)
    if not paths or manifest.get('files') != describe(payload, paths):
        raise ValueError('payload does not match the manifest')
    print(f'Verified {root}', flush=True)
    return {
        'schema_version': 1,
        'version': manifest['version'],
        'source_commit': manifest['source_commit'],
        'manifest_sha256': hashlib.sha256(manifest_bytes).hexdigest(),
    }


def accept(args):
    if args.evidence.resolve().is_relative_to(args.bundle.resolve()):
        raise ValueError('acceptance evidence must be outside the bundle')
    identity = verify(args)
    subprocess.run(args.check, check=True)
    if verify(args) != identity:
        raise ValueError('bundle changed during candidate acceptance')
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    with args.evidence.open('x', encoding='utf-8') as stream:
        json.dump(identity, stream, indent=2)
        stream.write('\n')


def verify_accepted(args):
    identity = verify(args)
    if identity['source_commit'] != args.commit or identity['version'] != args.version:
        raise ValueError('candidate does not match the expected source commit and version')
    if json.loads(args.evidence.read_bytes()) != identity:
        raise ValueError('candidate does not match acceptance evidence')



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
    accepted = commands.add_parser('accept')
    accepted.add_argument('bundle', type=Path)
    accepted.add_argument('evidence', type=Path)
    accepted.add_argument('check', nargs=argparse.REMAINDER)
    accepted.set_defaults(run=accept)
    gate = commands.add_parser('verify-accepted')
    gate.add_argument('bundle', type=Path)
    gate.add_argument('evidence', type=Path)
    gate.add_argument('--version', required=True)
    gate.add_argument('--commit', required=True)
    gate.set_defaults(run=verify_accepted)
    args = parser.parse_args()
    if args.command == 'accept' and not args.check:
        parser.error('accept requires a candidate test command')

    try:
        args.run(args)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'release bundle: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
