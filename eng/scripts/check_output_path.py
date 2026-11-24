"""Refuse unsafe recursive cleanup paths before removing any output."""
from pathlib import Path
import subprocess
import sys


def check_output_path(value):
    path = Path(value)
    if path.is_absolute() or path == Path('.') or any(part.lower() in ('..', '.git') for part in path.parts):
        raise ValueError(f'refusing to clean {value!r}: expected a repository-relative output directory')
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError(f'refusing to clean {value!r}: path crosses a symbolic link')
    if subprocess.check_output(['git', '--literal-pathspecs', 'ls-files', '--', str(path)]):
        raise ValueError(f'refusing to clean {value!r}: directory contains tracked files')


if __name__ == '__main__':
    try:
        for argument in sys.argv[1:]:
            check_output_path(argument)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
