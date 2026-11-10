#!/usr/bin/env python3
"""Ensure NuGet suppressions exactly match validated, unexpired exceptions."""
import subprocess
import sys
import xml.etree.ElementTree as ET


def main():
    result = subprocess.run([sys.executable, 'eng/scripts/security_exceptions.py'],
                            check=True, text=True, capture_output=True)
    expected = {'https://github.com/advisories/' + item
                for item in result.stdout.strip().split(',') if item}
    root = ET.parse('.github/nuget-audit-suppressions.props').getroot()
    if root.tag != 'Project' or root.attrib or len(root) != 1 or root[0].tag != 'ItemGroup' or root[0].attrib:
        raise ValueError('expected one unconditional ItemGroup')
    urls = []
    for item in root[0]:
        if item.tag != 'NuGetAuditSuppress' or set(item.attrib) != {'Include'} or len(item):
            raise ValueError('unexpected suppression item')
        urls.append(item.attrib['Include'])
    if len(urls) != len(set(urls)) or set(urls) != expected:
        raise ValueError('NuGet suppressions do not match unexpired security exceptions')
    print('NuGet suppressions match the reviewed exceptions.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f'NuGet suppressions: {error}', file=sys.stderr)
        sys.exit(1)
