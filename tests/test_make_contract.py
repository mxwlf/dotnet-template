"""Boundary checks for Make targets that select tests or remove generated output."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from eng.scripts import run_solution_tests


class MakeContractTests(unittest.TestCase):
    def test_distclean_rejects_unsafe_paths_before_deleting_the_environment(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / 'repo'
            scripts = repo / 'eng/scripts'
            scripts.mkdir(parents=True)
            (scripts / 'check_output_path.py').write_bytes((root / 'eng/scripts/check_output_path.py').read_bytes())
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            subprocess.run(['git', 'add', 'eng'], cwd=repo, check=True)
            (repo / 'linked').symlink_to(tmp, target_is_directory=True)
            sentinel = repo / '.venv/keep'
            sentinel.parent.mkdir()
            sentinel.touch()
            for path in ('', '.', '..', '../outside', tmp, '.git', 'linked/output', 'eng'):
                with self.subTest(path=path):
                    result = subprocess.run(
                        ['make', '-f', str(root / 'Makefile'), 'distclean', f'ARTIFACTS_DIR={path}',
                         f'PYTHON={sys.executable}'], cwd=repo, capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('refusing to clean', result.stderr)
                    self.assertTrue(sentinel.exists())

    def test_suite_selection_uses_solution_membership_and_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            solution = Path(tmp) / 'example.slnx'
            solution.write_text('<Solution><Project Path="test/unit/A.csproj"/>'
                                '<Project Path="test/integration/B.csproj"/></Solution>')
            def properties(project, configuration):
                return {'IsTestProject': 'true', 'TargetFrameworks': '', 'TargetPath': str(project.with_suffix('.dll'))}

            with patch.object(run_solution_tests, 'project_properties', side_effect=properties):
                for suite, expected in ((None, ['A', 'B']), ('unit', ['A']), ('integration', ['B'])):
                    with self.subTest(suite=suite):
                        modules = run_solution_tests.test_modules(solution, 'Release', suite)
                        self.assertEqual([name for name, _ in modules], expected)
