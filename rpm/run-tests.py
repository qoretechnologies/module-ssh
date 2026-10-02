#!/usr/bin/python3
# Copyright (C) 2026 Qore Technologies, s.r.o.
# SPDX-License-Identifier: MIT
"""Qualify the compiled SSH modules with loopback services and public test keys."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

MODULES = ('SftpServerDataProvider', 'SshServerAuthProvider',
           'SshServerConnections', 'SshServerCommandProvider')


def module_paths(build, env):
    paths = subprocess.check_output(['/usr/bin/qore', '--module-path'], env=env, text=True).strip().split(':')
    native_dirs = [build.resolve()] if build else [Path(path) for path in paths]
    natives = [file for directory in native_dirs for file in directory.glob('ssh-api-*.qmod')]
    if len(natives) != 1:
        raise RuntimeError('Expected one native SSH module: ' + repr(natives))
    aot_dir = build.resolve() / 'qlib-qmod' if build else natives[0].parent
    modules = []
    for name in MODULES:
        candidates = [path for path in (aot_dir / (name + '.qmod'), aot_dir / name / (name + '.qmod'))
                      if path.is_file()]
        if len(candidates) != 1:
            raise RuntimeError('Expected one compiled artifact for ' + name)
        modules.append(candidates[0])
    env.update(QORE_MODULE_DIR=':'.join(dict.fromkeys([str(natives[0].parent), str(aot_dir), *paths])),
               QORE_MODULE_DIR_ONLY='1')
    return [*natives, *modules]


def copy_fixtures(source, root):
    """Keep relative example/key paths while removing development module search paths."""
    for folder, suffixes in (('test', ('.qtest', '.qm')), ('examples', ('.qtest', '.qr'))):
        destination = root / folder
        destination.mkdir()
        for path in sorted((source / folder).iterdir()):
            if path.suffix in suffixes and path.is_file():
                text = re.sub(r'^%prepend-module-path .*\n', '', path.read_text(), flags=re.M)
                (destination / path.name).write_text(text)
    shutil.copytree(source / 'test/data', root / 'test/data')


def run(build=None, compiler=False):
    if os.getuid() == 0:
        raise RuntimeError('SSH package tests must run unprivileged')
    source = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    for key in ('QORE_MODULE_DIR', 'QORE_MODULE_DIR_ONLY', 'QORE_INCLUDE_DIR', 'LD_LIBRARY_PATH', 'LD_PRELOAD'):
        env.pop(key, None)
    env.update(LC_ALL='C.UTF-8', TZ='UTC')
    modules = module_paths(build, env)
    qore = ['/usr/bin/qore', '-b', '--enable-debug']
    for module in modules:
        qore += ['-l', str(module)]
    suites = sorted((source / 'test').glob('*.qtest'))
    if len(suites) != 15:
        raise RuntimeError('Review the SSH suite inventory before qualification')
    with tempfile.TemporaryDirectory(prefix='qore-ssh-rpm-') as directory:
        root = Path(directory)
        copy_fixtures(source, root)
        env['QORE_MODULE_DIR'] += ':' + str(root / 'test')
        for suite in suites:
            if suite.name == 'Scaffold.qtest':
                if not build:
                    continue
                path = suite
            else:
                path = root / 'test' / suite.name
            print('=== ' + suite.name + ' ===', flush=True)
            subprocess.run([*qore, str(path), '-v'], env=env, cwd=root, check=True, timeout=240)
        examples = sorted(path for path in (root / 'examples').iterdir() if path.suffix in ('.qr', '.qtest'))
        if len(examples) != 6:
            raise RuntimeError('Review the SSH example inventory before qualification')
        for example in examples:
            print('=== ' + example.name + ' ===', flush=True)
            subprocess.run([*qore, str(example)], env=env, cwd=root, check=True, timeout=240)
        if compiler:
            text = (source / 'debian/tests/compiler').read_text().split("<<'EOF'\n", 1)[1].split('\nEOF', 1)[0]
            (root / 'ssh-smoke.q').write_text(text + '\n')
            subprocess.run(['/usr/bin/qcc', '-o', str(root / 'ssh-smoke'), str(root / 'ssh-smoke.q')],
                           env=env, cwd=root, check=True, timeout=120)
            subprocess.run([str(root / 'ssh-smoke')], env=env, cwd=root, check=True, timeout=30)
        print('SSH suites and examples passed against compiled modules.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--build-dir', type=Path)
    mode.add_argument('--installed', action='store_true')
    parser.add_argument('--compiler', action='store_true')
    arguments = parser.parse_args()
    run(arguments.build_dir, arguments.compiler)
