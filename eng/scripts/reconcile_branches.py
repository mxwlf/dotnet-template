#!/usr/bin/env python3
"""Establish shared main and develop history in a fresh template clone."""

import argparse
import subprocess
import sys


TRACKING = 'refs/remotes/origin/'


class ReconciliationError(Exception):
    pass


def git(*args, allowed=(0,)):
    result = subprocess.run(
        ['git', '--no-replace-objects', *args], capture_output=True, text=True,
    )
    if result.returncode not in allowed:
        detail = result.stderr.strip() or result.stdout.strip()
        raise ReconciliationError(detail or f'git {args[0]} exited with {result.returncode}')
    return result


def fetch_origin():
    # Fetch both branches even when the clone was made with --single-branch.
    git('fetch', '--prune', '--no-prune-tags', '--no-tags', '--no-recurse-submodules',
        '--refmap=', 'origin',
        f'+refs/heads/*:{TRACKING}*')
    return branch_tips(TRACKING)


def branch_tips(prefix):
    refs = git('for-each-ref', '--format=%(refname) %(objectname) %(symref)', prefix)
    tips = {}
    for line in refs.stdout.splitlines():
        ref, commit, symbolic_target = line.split(' ', 2)
        if not symbolic_target:
            tips[ref.removeprefix(prefix)] = commit
    return tips


def check_initial_history(remote):
    if git('rev-parse', '--is-shallow-repository').stdout.strip() == 'true':
        raise ReconciliationError(
            'A shallow clone cannot prove this is initial history. '
            'Run git fetch --unshallow origin, then retry.'
        )

    additional = []
    for name, commit in remote.items():
        history = git('rev-list', '--max-count=1', '--parents', commit).stdout.split()
        if len(history) != 1:
            additional.append(f'origin/{name} ({commit[:12]}) has commits after its initial commit')

    remote_tips = set(remote.values())
    local = branch_tips('refs/heads/')
    local['HEAD (current checkout)'] = git('rev-parse', '--verify', 'HEAD').stdout.strip()
    for name, commit in local.items():
        if commit not in remote_tips:
            additional.append(f'{name} ({commit[:12]}) has a commit outside the fetched branch tips')

    if additional:
        details = '\n  '.join(additional)
        raise ReconciliationError(
            f'Additional commits or unexpected history found:\n  {details}\n'
            'Automatic reconciliation requires the original template commits. '
            'Keep your work and reconcile the branches manually before retrying setup.'
        )


def reconcile():
    if 'origin' not in git('remote').stdout.splitlines():
        print('Branch reconciliation skipped because this repository has no origin remote.')
        return

    remote = fetch_origin()
    main = remote.get('main')
    develop = remote.get('develop')
    if main and develop and git('merge-base', main, develop, allowed=(0, 1)).returncode == 0:
        print('origin/main and origin/develop already share history.')
        return
    if not main and not develop:
        raise ReconciliationError('origin has neither main nor develop. Publish an initial branch and retry.')

    check_initial_history(remote)
    fetch_url = git('remote', 'get-url', 'origin').stdout.strip()
    push_urls = git('remote', 'get-url', '--push', '--all', 'origin').stdout.splitlines()
    if push_urls != [fetch_url]:
        raise ReconciliationError(
            'Reconciliation requires origin to fetch and push to the same single URL '
            'so the push updates the repository that was checked.'
        )

    target = 'main' if develop else 'develop'
    source = 'develop' if develop else 'main'
    ref = f'refs/heads/{target}'
    previous = remote.get(target, '')
    action = 'Aligning' if previous else 'Creating'
    print(f'{action} origin/{target} from origin/{source} ({remote[source][:12]}).', flush=True)
    git('-c', 'remote.origin.mirror=false', 'push', '--no-follow-tags', '--recurse-submodules=no',
        f'--force-with-lease={ref}:{previous}', 'origin', f'{remote[source]}:{ref}')

    print(f'Updated origin/{target}. Refreshing remote-tracking refs.', flush=True)
    updated = fetch_origin()
    if updated.get(target) != remote[source] or updated.get(source) != remote[source]:
        raise ReconciliationError(
            'origin changed during reconciliation. Review both branch tips and rerun the target.'
        )
    if previous and branch_tips('refs/heads/').get(target) == previous:
        print(f'Local {target} still points to its original commit. '
              f'See docs/branch-reconciliation.md to align it with origin/{target}.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    try:
        reconcile()
    except (OSError, ReconciliationError) as error:
        print(f'Branch reconciliation failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
