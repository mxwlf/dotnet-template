#!/usr/bin/env python3
"""Check the example NuGet package against the assembly used in acceptance."""
import json
import sys
from pathlib import Path
from xml.etree import ElementTree
from zipfile import BadZipFile, ZipFile


def check(bundle, build):
    manifest = json.loads((bundle / 'manifest.json').read_bytes())
    package = bundle / 'files' / f"mxwlf.net.library.example.{manifest['version']}.nupkg"
    with ZipFile(package) as archive:
        metadata = ElementTree.fromstring(archive.read('mxwlf.net.library.example.nuspec'))
        if metadata.findtext('./{*}metadata/{*}version') != manifest['version']:
            raise ValueError('package version does not match the candidate')
        if archive.testzip() is not None:
            raise ValueError('package contains corrupt entries')
        if archive.read('lib/net10.0/library.example.dll') != (build / 'library.example.dll').read_bytes():
            raise ValueError('packaged assembly differs from the tested build')
    with ZipFile(package.with_suffix('.snupkg')) as symbols:
        if symbols.testzip() is not None or 'lib/net10.0/library.example.pdb' not in symbols.namelist():
            raise ValueError('symbol package is corrupt or missing its symbols')


if __name__ == '__main__':
    try:
        check(*map(Path, sys.argv[1:]))
    except (BadZipFile, ElementTree.ParseError, KeyError, OSError, ValueError) as error:
        sys.exit(f'example package: {error}')
