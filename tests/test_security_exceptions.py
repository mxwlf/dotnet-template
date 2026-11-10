"""Behavior checks for the dependency-review exception policy."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'eng/scripts' / 'security_exceptions.py'


class SecurityExceptionsTests(unittest.TestCase):
    def run_check(self, entries):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / '.github').mkdir()
            (root / '.github/security-exceptions.json').write_text(json.dumps(entries))
            return subprocess.run([sys.executable, str(SCRIPT)], cwd=root,
                                  capture_output=True, text=True, check=False)

    def test_valid_and_empty_entries(self):
        valid = {'id': 'GHSA-2345-2345-2345', 'reason': 'Reviewed', 'expires': '2099-12-31'}
        self.assertEqual(self.run_check([]).returncode, 0)
        result = self.run_check([valid])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), valid['id'])

    def test_invalid_entries_are_rejected(self):
        valid = {'id': 'GHSA-2345-2345-2345', 'reason': 'Reviewed', 'expires': '2099-12-31'}
        bad_entries = [[dict(valid, expires='2020-01-01')], [dict(valid, reason='')],
                       [dict(valid, id='bad')], [valid, valid], [dict(valid, expires='invalid')]]
        for entries in bad_entries:
            with self.subTest(entries=entries):
                self.assertNotEqual(self.run_check(entries).returncode, 0)


if __name__ == '__main__':
    unittest.main()
