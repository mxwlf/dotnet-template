"""Security behavior for NuGet audit results."""
import contextlib
import importlib.util
import io
import json
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / 'eng/scripts/nuget_audit.py'
spec = importlib.util.spec_from_file_location('nuget_audit', path)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
ADVISORY = 'GHSA-2345-2345-2345'


def report(severity='High'):
    return {'version': 1, 'sources': ['https://example.invalid'], 'projects': [
        {'path': 'app.csproj', 'frameworks': [{'framework': 'net10.0',
         'transitivePackages': [{'id': 'Example', 'vulnerabilities': [
             {'severity': severity, 'advisoryurl': 'https://github.com/advisories/' + ADVISORY}]}]}]}]}


class NugetAuditTests(unittest.TestCase):
    def run_audit(self, data, allowed=''):
        results = [subprocess.CompletedProcess([], 0, stdout=allowed, stderr=''),
                   subprocess.CompletedProcess([], 0, stdout=json.dumps(data), stderr='')]
        with patch.object(audit.subprocess, 'run', side_effect=results), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return audit.main()

    def test_blocks_high_and_critical_transitive_findings(self):
        for severity in ('High', 'Critical'):
            with self.subTest(severity=severity):
                self.assertEqual(self.run_audit(report(severity)), 1)

    def test_allows_reviewed_advisory_and_moderate_findings(self):
        self.assertEqual(self.run_audit(report(), ADVISORY), 0)
        self.assertEqual(self.run_audit(report('Moderate')), 0)

    def test_incomplete_report_does_not_pass(self):
        broken = report()
        broken['problems'] = [{'level': 'warning', 'text': 'source unavailable'}]
        with self.assertRaises(ValueError):
            self.run_audit(broken)
        broken = report()
        broken['sources'] = []
        with self.assertRaises(ValueError):
            self.run_audit(broken)


if __name__ == '__main__':
    unittest.main()
