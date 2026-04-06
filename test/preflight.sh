#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

export QORE_MODULE_DIR="build:$(pwd)/qlib${QORE_MODULE_DIR:+:$QORE_MODULE_DIR}"

cmake --build build

qore --enable-debug test/Scaffold.qtest -v
qore --enable-debug test/SshSession.qtest -v
qore --enable-debug test/SshCommandSession.qtest -v
qore --enable-debug test/SftpSession.qtest -v
qore --enable-debug test/SshServerConnections.qtest -v
qore --enable-debug test/SshServerAuthProvider.qtest -v
qore --enable-debug test/SshServerCommandProvider.qtest -v
qore --enable-debug test/SftpServerDataProvider.qtest -v
qore --enable-debug test/SftpServerDataProviderDataProvider.qtest -v
qore --enable-debug test/VirtualSftpServer.qtest -v
qore --enable-debug test/VirtualSftpInboundPolicyServer.qtest -v
qore --enable-debug test/SshServer.qtest -v

qore --enable-debug examples/VirtualSshCommandLiveServer.qr
qore --enable-debug examples/VirtualSftpServer.qr
qore --enable-debug examples/VirtualSftpInboundPolicyServer.qr

cmake --build build --target docs
