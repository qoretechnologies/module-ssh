SSH server examples
===================

Copyright 2026 Qore Technologies, s.r.o.

``demos/`` contains executable virtual SFTP and SSH command examples, plus
two QUnit examples. Their relative ``../test/data`` paths resolve to the public
test identities shipped here. These keys are published source fixtures; use
newly generated private keys for deployed services.

With qore-ssh-module installed, run an example as a normal user::

    qore -b --enable-debug demos/VirtualSftpServer.qr
    qore -b --enable-debug demos/VirtualSshCommandLiveServer.qr

The examples use ephemeral loopback ports and the distribution's OpenSSH
clients. They do not install or change an SSH service.
