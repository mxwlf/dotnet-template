"""Behavior checks for the release bundle CLI."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'eng' / 'scripts' / 'release_bundle.py'


class ReleaseBundleTests(unittest.TestCase):
    def run_bundle(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                              capture_output=True, text=True, check=False)

    def test_create_and_verify_preserves_payload_and_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'input'
            (source / 'nested').mkdir(parents=True)
            (source / 'nested' / 'app').write_bytes(b'release bytes\n')
            bundle = root / 'bundle'
            created = self.run_bundle('create', '--input', source, '--output', bundle,
                                      '--version', '1.2.3', '--commit', 'abc123')
            self.assertEqual(created.returncode, 0, created.stderr)
            self.assertEqual((bundle / 'files/nested/app').read_bytes(), b'release bytes\n')
            manifest = json.loads((bundle / 'manifest.json').read_text())
            self.assertEqual(manifest['version'], '1.2.3')
            self.assertEqual(manifest['source_commit'], 'abc123')
            self.assertEqual(self.run_bundle('verify', bundle).returncode, 0)

    def test_verify_rejects_changed_missing_and_extra_files(self):
        for kind in ('changed', 'missing', 'extra'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / 'input'
                source.mkdir()
                (source / 'file').write_text('original')
                bundle = root / 'bundle'
                self.assertEqual(self.run_bundle('create', '--input', source, '--output', bundle,
                                                 '--version', '1', '--commit', 'abc').returncode, 0)
                payload = bundle / 'files/file'
                if kind == 'changed':
                    payload.write_text('changed')
                elif kind == 'missing':
                    payload.unlink()
                else:
                    (bundle / 'files/extra').write_text('extra')
                self.assertNotEqual(self.run_bundle('verify', bundle).returncode, 0)

    def test_create_refuses_existing_destination_and_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'input'
            source.mkdir()
            (source / 'data').write_text('value')
            output = root / 'output'
            output.mkdir()
            (output / 'keep').write_text('keep')
            result = self.run_bundle('create', '--input', source, '--output', output,
                                     '--version', '1', '--commit', 'abc')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((output / 'keep').read_text(), 'keep')
            (source / 'link').symlink_to(source / 'data')
            result = self.run_bundle('create', '--input', source, '--output', root / 'new',
                                     '--version', '1', '--commit', 'abc')
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
