#!/usr/bin/env python3
"""Check a NuGet vulnerability JSON report against reviewed exceptions."""
import json
import re
import subprocess
import sys
from pathlib import Path


def main():
    # The shared validator checks expiry and metadata before yielding IDs.
    result = subprocess.run([sys.executable, 'eng/scripts/security_exceptions.py'],
                            check=True, capture_output=True, text=True)
    allowed = set(filter(None, result.stdout.strip().split(',')))
    scan = subprocess.run(['dotnet', 'package', 'list', '--vulnerable', '--include-transitive',
                           '--format', 'json', '--output-version', '1', '--no-restore'],
                          check=True, capture_output=True, text=True)
    if scan.stderr.strip():
        raise ValueError('NuGet reported warnings or errors: ' + scan.stderr.strip())
    report = json.loads(scan.stdout)
    if (not isinstance(report, dict) or report.get('version') != 1
            or not isinstance(report.get('projects'), list) or not report['projects']
            or not isinstance(report.get('sources'), list) or not report['sources']
            or report.get('problems')):
        raise ValueError('NuGet report is incomplete or reports problems')
    findings = []
    for project in report['projects']:
        for framework in project.get('frameworks', []):
            for key in ('topLevelPackages', 'transitivePackages'):
                for package in framework.get(key, []):
                    for vuln in package.get('vulnerabilities', []):
                        severity = vuln.get('severity', '').lower()
                        if severity not in ('low', 'moderate', 'high', 'critical'):
                            raise ValueError('unknown vulnerability severity')
                        if severity not in ('high', 'critical'):
                            continue
                        url = vuln.get('advisoryurl', '')
                        match = re.fullmatch(r'https://github.com/advisories/(GHSA-[23456789cfghjmpqrvwx]{4}-[23456789cfghjmpqrvwx]{4}-[23456789cfghjmpqrvwx]{4})', url)
                        if not match or match.group(1) not in allowed:
                            findings.append(f"{package.get('id', '?')} {severity}: {url}")
                        else:
                            print(f"Reviewed exception: {package.get('id', '?')} {match.group(1)}")
    if findings:
        print('\n'.join(findings), file=sys.stderr)
        return 1
    print('No unexcepted high or critical vulnerabilities in the solution report.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, TypeError, KeyError, subprocess.CalledProcessError) as error:
        print(f'NuGet audit failed: {error}', file=sys.stderr)
        sys.exit(1)
