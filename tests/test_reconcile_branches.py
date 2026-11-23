import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'eng/scripts/reconcile_branches.py'


class ReconcileBranchesTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.remote = self.directory / 'remote.git'
        self.seed = self.directory / 'seed'
        self.clone = self.directory / 'clone'
        self.env = {
            **os.environ,
            'GIT_CONFIG_GLOBAL': os.devnull,
            'GIT_CONFIG_NOSYSTEM': '1',
            'GIT_AUTHOR_NAME': 'Template Test',
            'GIT_AUTHOR_EMAIL': 'template@example.invalid',
            'GIT_COMMITTER_NAME': 'Template Test',
            'GIT_COMMITTER_EMAIL': 'template@example.invalid',
            'GIT_TERMINAL_PROMPT': '0',
        }

    def git(self, *args, cwd=None, stdin=None):
        return subprocess.run(
            ['git', *args], cwd=cwd or self.directory, env=self.env, input=stdin,
            capture_output=True, text=True, check=True,
        ).stdout.strip()

    def seed_origin(self, default='develop', include_all=False, clone_args=()):
        self.git('init', '--bare', f'--initial-branch={default}', self.remote)
        self.git('init', f'--initial-branch={default}', self.seed)
        (self.seed / 'snapshot.txt').write_text(f'{default}\n', encoding='utf-8')
        self.git('add', 'snapshot.txt', cwd=self.seed)
        self.git('commit', '-m', 'Initial commit', cwd=self.seed)
        self.git('push', self.remote, default, cwd=self.seed)
        if include_all:
            self.git('switch', '--orphan', 'main', cwd=self.seed)
            (self.seed / 'snapshot.txt').write_text('main\n', encoding='utf-8')
            self.git('add', 'snapshot.txt', cwd=self.seed)
            self.git('commit', '-m', 'Initial commit', cwd=self.seed)
            self.git('push', self.remote, 'main', cwd=self.seed)
        self.git('clone', *clone_args, self.remote, self.clone)

    def remote_heads(self):
        return self.git('show-ref', '--heads', cwd=self.remote)

    def reconcile(self):
        return subprocess.run(
            [sys.executable, SCRIPT], cwd=self.clone, env=self.env,
            capture_output=True, text=True,
        )

    def assert_success(self):
        result = self.reconcile()
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def assert_stops(self, message):
        before = self.remote_heads()
        result = self.reconcile()
        self.assertEqual(result.returncode, 1)
        self.assertIn(message, result.stderr)
        self.assertEqual(self.remote_heads(), before)

    def test_creates_main_and_can_be_run_again(self):
        self.seed_origin()
        initial = self.git('rev-parse', 'develop', cwd=self.remote)
        self.assertIn('Creating origin/main', self.assert_success())
        self.assertEqual(self.git('rev-parse', 'main', cwd=self.remote), initial)
        self.assertEqual(self.git('rev-parse', 'develop', cwd=self.remote), initial)
        self.assertIn('already share history', self.assert_success())

    def test_creates_develop_when_main_is_the_only_initial_branch(self):
        self.seed_origin(default='main')
        self.assertIn('Creating origin/develop', self.assert_success())
        self.assertEqual(self.git('rev-parse', 'develop', cwd=self.remote),
                         self.git('rev-parse', 'main', cwd=self.remote))

    def test_aligns_unrelated_main_even_in_a_single_branch_clone(self):
        self.seed_origin(include_all=True, clone_args=('--single-branch',))
        initial = self.git('rev-parse', 'develop', cwd=self.remote)
        copied = self.git('rev-parse', 'main', cwd=self.remote)
        self.git('push', self.remote, 'main:refs/heads/copied', cwd=self.seed)
        self.assertEqual(self.git('show', 'main:snapshot.txt', cwd=self.remote), 'main')
        self.assertIn('Aligning origin/main', self.assert_success())
        self.assertEqual(self.git('rev-parse', 'main', cwd=self.remote), initial)
        self.assertEqual(self.git('rev-parse', 'origin/main', cwd=self.clone), initial)
        self.assertEqual(self.git('show', 'main:snapshot.txt', cwd=self.remote), 'develop')
        self.assertEqual(self.git('rev-parse', 'copied', cwd=self.remote), copied)

    def test_leaves_an_existing_local_main_checkout_intact(self):
        self.seed_origin(include_all=True)
        self.git('switch', 'main', cwd=self.clone)
        original = self.git('rev-parse', 'HEAD', cwd=self.clone)
        self.assertIn('Local main still points to its original commit', self.assert_success())
        self.assertEqual(self.git('rev-parse', 'HEAD', cwd=self.clone), original)
        self.assertEqual((self.clone / 'snapshot.txt').read_text(encoding='utf-8'), 'main\n')

    def test_stops_for_a_local_commit_on_another_branch(self):
        self.seed_origin(include_all=True)
        self.git('switch', '-c', 'feature', cwd=self.clone)
        self.git('commit', '--allow-empty', '-m', 'Local work', cwd=self.clone)
        self.git('switch', 'develop', cwd=self.clone)
        self.assert_stops('feature (')

    def test_stops_for_a_commit_in_the_detached_checkout(self):
        self.seed_origin()
        self.git('switch', '--detach', cwd=self.clone)
        self.git('commit', '--allow-empty', '-m', 'Detached work', cwd=self.clone)
        self.assert_stops('HEAD (current checkout)')

    def test_stops_for_a_commit_pushed_after_the_clone(self):
        self.seed_origin(include_all=True)
        self.git('commit', '--allow-empty', '-m', 'Published work', cwd=self.seed)
        self.git('push', self.remote, 'main', cwd=self.seed)
        self.assert_stops('origin/main (')

    def test_stops_for_a_shallow_clone_until_history_is_fetched(self):
        self.seed_origin()
        shallow = self.directory / 'shallow'
        self.git('clone', '--depth=1', self.remote.as_uri(), shallow)
        self.clone = shallow
        self.assert_stops('git fetch --unshallow origin')
        self.git('fetch', '--unshallow', 'origin', cwd=self.clone)
        self.assertIn('Creating origin/main', self.assert_success())

    def test_stops_when_a_remote_feature_branch_has_additional_commits(self):
        self.seed_origin()
        self.git('commit', '--allow-empty', '-m', 'Published work', cwd=self.seed)
        self.git('push', self.remote, 'HEAD:refs/heads/feature', cwd=self.seed)
        self.assert_stops('origin/feature (')

    def test_already_related_branches_with_additional_commits_are_a_noop(self):
        self.seed_origin()
        self.git('push', 'origin', 'develop:main', cwd=self.clone)
        self.git('commit', '--allow-empty', '-m', 'Published work', cwd=self.clone)
        self.git('push', 'origin', 'develop', cwd=self.clone)
        before = self.remote_heads()
        self.assertIn('already share history', self.assert_success())
        self.assertEqual(self.remote_heads(), before)

    def test_reports_server_rejection_without_changing_branches(self):
        self.seed_origin(include_all=True)
        self.git('config', 'receive.denyNonFastForwards', 'true', cwd=self.remote)
        self.assert_stops('non-fast-forward')

    def test_skips_a_local_repository_without_origin(self):
        self.git('init', self.clone)
        self.assertIn('has no origin remote', self.assert_success())


if __name__ == '__main__':
    unittest.main()
