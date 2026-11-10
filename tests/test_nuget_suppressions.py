"""Verify that NuGet suppressions cannot outlive their review record."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADVISORY = 'GHSA-2345-2345-2345'


class NugetSuppressionsTests(unittest.TestCase):
    def check(self, entries, xml):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / '.github').mkdir()
            (root / 'eng/scripts').mkdir(parents=True)
            for file in ('security_exceptions.py', 'validate_nuget_suppressions.py'):
                shutil.copy(ROOT / 'eng/scripts' / file, root / 'eng/scripts' / file)
            (root / '.github/security-exceptions.json').write_text(json.dumps(entries))
            (root / '.github/nuget-audit-suppressions.props').write_text(xml)
            return subprocess.run([sys.executable, 'eng/scripts/validate_nuget_suppressions.py'],
                                  cwd=root, capture_output=True, text=True, check=False)

    def test_reviewed_advisory_matches_scoped_suppression(self):
        entry = {'id': ADVISORY, 'reason': 'Reviewed', 'expires': '2099-12-31'}
        xml = f'<Project><ItemGroup><NuGetAuditSuppress Include="https://github.com/advisories/{ADVISORY}" /></ItemGroup></Project>'
        self.assertEqual(self.check([entry], xml).returncode, 0)
        self.assertNotEqual(self.check([], xml).returncode, 0)
        self.assertNotEqual(self.check([dict(entry, expires='2020-01-01')], xml).returncode, 0)

    def test_extra_msbuild_properties_are_rejected(self):
        xml = '<Project><PropertyGroup><NuGetAudit>false</NuGetAudit></PropertyGroup></Project>'
        self.assertNotEqual(self.check([], xml).returncode, 0)


if __name__ == '__main__':
    unittest.main()
