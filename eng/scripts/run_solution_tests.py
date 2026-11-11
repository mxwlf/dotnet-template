#!/usr/bin/env python3
"""Run the Microsoft.Testing.Platform apps declared by the solution."""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree


def project_properties(project, configuration, framework=None):
    command = [
        'dotnet', 'msbuild', str(project), '-nologo', f'-p:Configuration={configuration}',
        '-getProperty:IsTestProject,TargetFrameworks,TargetPath',
    ]
    if framework:
        command.append(f'-p:TargetFramework={framework}')
    output = subprocess.check_output(command, text=True)
    return json.loads(output)['Properties']


def test_modules(solution, configuration):
    for node in ElementTree.parse(solution).iter('Project'):
        project = solution.parent / node.attrib['Path'].replace('\\', '/')
        properties = project_properties(project, configuration)
        frameworks = [value.strip() for value in properties['TargetFrameworks'].split(';') if value.strip()]
        for framework in frameworks or [None]:
            target = project_properties(project, configuration, framework) if framework else properties
            if target['IsTestProject'].lower() != 'true':
                continue
            if not target['TargetPath']:
                raise ValueError(f'{project}: MSBuild returned no test output path')
            assembly = Path(target['TargetPath'])
            suffix = '.exe' if os.name == 'nt' else ''
            executable = assembly.with_suffix(suffix)
            name = f'{assembly.stem}.{framework}' if framework else assembly.stem
            yield name, executable


def prune_reports(directory, names, suffixes):
    if directory.is_absolute() or directory == Path('.') or not directory.is_dir():
        return
    for path in directory.iterdir():
        for suffix in suffixes:
            if path.name.endswith(suffix) and path.name.removesuffix(suffix) not in names and path.is_file():
                print(f'test: pruning stale report {path}', flush=True)
                path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('solution', type=Path)
    parser.add_argument('configuration')
    parser.add_argument('results', type=Path)
    parser.add_argument('history', type=Path)
    parser.add_argument('history_days')
    args = parser.parse_args()
    try:
        modules = list(test_modules(args.solution, args.configuration))
        if not modules:
            raise ValueError(f'{args.solution}: no test projects found')
        names = {name for name, _ in modules}
        if len(names) != len(modules):
            raise ValueError(f'{args.solution}: test project outputs must have unique report names')
        prune_reports(args.results, names, ('.trx', '.cobertura.xml'))
        prune_reports(args.history, names, ('.json', '.json.lock'))
        args.history.mkdir(parents=True, exist_ok=True)
        failed = False
        for name, executable in modules:
            if not executable.is_file() or not os.access(executable, os.X_OK):
                print(f'test: expected executable is missing or unusable: {executable}', file=sys.stderr)
                failed = True
                continue
            print(f'==> {executable}', flush=True)
            result = subprocess.run([
                str(executable), '--results-directory', str(args.results),
                '--report-xunit-trx', '--report-xunit-trx-filename', f'{name}.trx',
                '--report-gh', '--report-gh-history', str(args.history / f'{name}.json'),
                '--report-gh-history-window', args.history_days,
                '--coverage', '--coverage-output-format', 'cobertura',
                '--coverage-output', f'{name}.cobertura.xml',
            ], check=False)
            failed |= result.returncode != 0
        return int(failed)
    except (OSError, ValueError, ElementTree.ParseError, subprocess.CalledProcessError) as error:
        print(f'test: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
