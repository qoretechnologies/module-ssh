RPM packaging
=============

Copyright 2026 Qore Technologies, s.r.o.

The canonical qore-ssh-module.spec targets Fedora, Enterprise Linux and
openSUSE with the Qore 3.0 SDK and matching qore-rpm-macros. It packages native
SSH server/key bindings, four compiled/source provider modules, compiler
metadata and translations. System libssh 0.11 or later supplies SSH and full
private-key export support; cryptography is not bundled.

The documentation package includes five API references and six runnable
examples. Its public test identities retain the relative paths used by the
examples and are explicitly marked as unsuitable for deployed services.
Native sources retain LGPL-2.1-or-later terms; user modules, tests and examples
retain MIT terms. Both license texts are included.

From qore-packaging, prepare a committed source bundle and build it in an
isolated target SDK::

    python3 tools/packaging.py prepare --repo ../module-ssh --ref COMMIT \
      --name qore-ssh-module --version 1.0.0 --spec qore-ssh-module.spec \
      --output work/ssh-source
    python3 tools/build-local.py --source work/ssh-source \
      --image TARGET_SDK_IMAGE --output results/ssh-build --jobs 2

Tests and documentation are enabled by default and remain enabled for
repository qualification. Tests use the exact native and compiled artifacts
with debugging enabled, a temporary copy of test inputs, ephemeral loopback
listeners and OpenSSH clients. No external SSH server or user SSH configuration
is needed. The source-only scaffold suite runs only during builds.

Installed qualification runs outside the checkout with no development search
paths. On a disposable runtime image, run unprivileged::

    python3 -B -W error rpm/test_fixture.py -v
    python3 -B -W error rpm/run-tests.py --installed

Add ``--compiler`` on the SDK image to compile and execute the named-argument
key and virtual-filesystem example. Runtime tests require only Python, OpenSSH
clients and the installed runtime packages.

Installed documentation scripts use ``/usr/bin/qore`` so their interpreter
resolves to the packaged runtime. Source-checkout scripts retain their portable
``/usr/bin/env qore`` shebangs.
The package descriptions use plain terms recognized by distribution lint tools.
