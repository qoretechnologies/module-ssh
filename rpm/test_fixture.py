#!/usr/bin/python3
# Copyright (C) 2026 Qore Technologies, s.r.o.
# SPDX-License-Identifier: MIT
"""Check strict artifact selection and isolation of installed SSH tests."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

loader = importlib.util.spec_from_file_location('fixture', Path(__file__).with_name('run-tests.py'))
fixture = importlib.util.module_from_spec(loader)
loader.loader.exec_module(fixture)


class FixtureTests(unittest.TestCase):
    def populate(self, root, nested):
        native = root / 'ssh-api-1.0.qmod'
        native.touch()
        aot = root if nested else root / 'qlib-qmod'
        for name in fixture.MODULES:
            path = aot / name / (name + '.qmod') if nested else aot / (name + '.qmod')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        return native

    def test_selects_build_and_installed_artifacts(self):
        for installed in (False, True):
            with self.subTest(installed=installed), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                native = self.populate(root, installed)
                env = {}
                with patch.object(fixture.subprocess, 'check_output', return_value=str(root) + '\n'):
                    paths = fixture.module_paths(None if installed else root, env)
                self.assertEqual(native, paths[0])
                self.assertEqual(5, len(paths))
                self.assertTrue(all(path.is_file() for path in paths))
                self.assertEqual('1', env['QORE_MODULE_DIR_ONLY'])
                self.assertNotIn('qlib:', env['QORE_MODULE_DIR'])

    def test_missing_native_or_compiled_module_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(fixture.subprocess, 'check_output', return_value=str(root)):
                with self.assertRaisesRegex(RuntimeError, 'one native SSH'):
                    fixture.module_paths(root, {})
                (root / 'ssh-api-1.0.qmod').touch()
                with self.assertRaisesRegex(RuntimeError, 'SftpServerDataProvider'):
                    fixture.module_paths(root, {})

    def test_ambiguous_native_and_compiled_modules_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.populate(root, False)
            with patch.object(fixture.subprocess, 'check_output', return_value=str(root)):
                duplicate = root / 'ssh-api-2.0.qmod'
                duplicate.touch()
                with self.assertRaisesRegex(RuntimeError, 'one native SSH'):
                    fixture.module_paths(root, {})
                duplicate.unlink()
                name = fixture.MODULES[0]
                nested = root / 'qlib-qmod' / name / (name + '.qmod')
                nested.parent.mkdir()
                nested.touch()
                with self.assertRaisesRegex(RuntimeError, 'SftpServerDataProvider'):
                    fixture.module_paths(root, {})

    def test_copy_preserves_key_paths_without_source_modules(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            (source / 'test/data').mkdir(parents=True)
            (source / 'examples').mkdir()
            (source / 'test/data/key').write_bytes(b'public test identity')
            (source / 'test/TestLoggerInterface.qm').write_text('%modern\n')
            (source / 'test/one.qtest').write_text('%modern\n%prepend-module-path "../qlib"\n%requires ssh\n')
            (source / 'examples/demo.qr').write_text('%prepend-module-path "../qlib"\n%requires ssh\n')
            destination = root / 'copy'
            destination.mkdir()
            fixture.copy_fixtures(source, destination)
            self.assertEqual('%modern\n%requires ssh\n', (destination / 'test/one.qtest').read_text())
            self.assertEqual('%requires ssh\n', (destination / 'examples/demo.qr').read_text())
            self.assertEqual(b'public test identity', (destination / 'test/data/key').read_bytes())
            self.assertTrue((destination / 'test/TestLoggerInterface.qm').is_file())
            self.assertFalse((destination / 'qlib').exists())

    def test_root_execution_is_rejected_before_module_loading(self):
        with patch.object(fixture.os, 'getuid', return_value=0), \
                patch.object(fixture, 'module_paths') as paths:
            with self.assertRaisesRegex(RuntimeError, 'unprivileged'):
                fixture.run()
            paths.assert_not_called()


if __name__ == '__main__':
    unittest.main()
