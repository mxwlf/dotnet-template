#!/usr/bin/env python3
"""Compare selected shared settings with a reviewed git-template checkout."""
import argparse
import json
import sys
from pathlib import Path
import yaml


def load(path):
    return yaml.safe_load(path.read_text(encoding='utf-8'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True, help='path to a reviewed git-template checkout')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    baseline = args.baseline.resolve()
    errors = []
    source_hooks = load(baseline / '.pre-commit-config.yaml')['repos']
    target_hooks = {repo['repo']: repo for repo in load(root / '.pre-commit-config.yaml')['repos']}
    for source in source_hooks:
        if source['repo'] == 'local':
            continue
        if target_hooks.get(source['repo']) != source:
            errors.append(f"pre-commit configuration differs: {source['repo']}")
    for file in ('.github/workflows/actions-lock.yml', '.github/workflows/security.yml'):
        expected = (baseline / file).read_text(encoding='utf-8')
        actual = (root / file).read_text(encoding='utf-8').replace('eng/scripts/security_exceptions.py', 'scripts/security_exceptions.py')
        if expected != actual:
            errors.append(f'configuration differs: {file}')
    if (baseline / 'scripts/security_exceptions.py').read_bytes() != (root / 'eng/scripts/security_exceptions.py').read_bytes():
        errors.append('security exception validators differ')
    path = '.github/dependabot.yml'
    def actions_config(directory):
        matches = [entry for entry in load(directory / path)['updates'] if entry['package-ecosystem'] == 'github-actions']
        if len(matches) != 1:
            raise ValueError('expected exactly one GitHub Actions update configuration')
        return matches[0]
    if actions_config(baseline) != actions_config(root):
        errors.append(f'GitHub Actions update settings differ: {path}')
    exceptions = json.loads((root / '.github/git-baseline-exceptions.json').read_text(encoding='utf-8'))
    if not isinstance(exceptions, list):
        raise ValueError('baseline exceptions must be a list')
    allowed = {}
    for item in exceptions:
        if (not isinstance(item, dict) or set(item) != {'difference', 'reason'}
                or not isinstance(item['difference'], str) or not item['difference'].strip()
                or not isinstance(item['reason'], str) or not item['reason'].strip()
                or item['difference'] in allowed):
            raise ValueError('each baseline exception requires a unique difference and reason')
        allowed[item['difference']] = item['reason']
    unmatched = [entry for entry in allowed if entry not in errors]
    if unmatched:
        errors.extend('unused baseline exception: ' + entry for entry in unmatched)
    remaining = [error for error in errors if error not in allowed]
    for difference in allowed:
        print(f'Accepted difference: {difference} — {allowed[difference]}')
    if remaining:
        print('\n'.join(remaining), file=sys.stderr)
        return 1
    print('Selected shared Git baseline settings match.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, KeyError, TypeError, ValueError, yaml.YAMLError) as error:
        print(f'baseline check: {error}', file=sys.stderr)
        sys.exit(1)
