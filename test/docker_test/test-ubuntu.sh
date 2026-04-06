#!/bin/bash

set -e
set -x

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

echo "module-ssh CI"
test -f design/api-spec.md
test -f CMakeLists.txt

# verify QPP generation (--dox-output avoids writing .dox.h into src/)
qpp -o /tmp/QC_SftpSession.cpp --dox-output=/tmp/QC_SftpSession.dox.h -m /tmp/QC_SftpSession.json src/QC_SftpSession.qpp
qpp -o /tmp/QC_SshCommandSession.cpp --dox-output=/tmp/QC_SshCommandSession.dox.h -m /tmp/QC_SshCommandSession.json src/QC_SshCommandSession.qpp
qpp -o /tmp/QC_SshServer.cpp --dox-output=/tmp/QC_SshServer.dox.h -m /tmp/QC_SshServer.json src/QC_SshServer.qpp
qpp -o /tmp/QC_SshSession.cpp --dox-output=/tmp/QC_SshSession.dox.h -m /tmp/QC_SshSession.json src/QC_SshSession.qpp
qpp -o /tmp/ssh.cpp --dox-output=/tmp/ssh.dox.h -m /tmp/ssh.json src/ssh.qpp

# run scaffold test
qore --enable-debug test/Scaffold.qtest -v

# build binary module and run tests if libssh-dev is available
if pkg-config --exists libssh 2>/dev/null; then
    cd "$repo_root"
    rm -rf build
    mkdir -p build
    cd build
    cmake ..
    make -j$(nproc)
    cd ..
    QORE_MODULE_DIR=build qore --enable-debug test/SshServer.qtest -v
QORE_MODULE_DIR=build qore --enable-debug test/SshServerConnections.qtest -v
QORE_MODULE_DIR=build qore --enable-debug test/SshServerCommandProvider.qtest -v
QORE_MODULE_DIR=build qore --enable-debug test/SshSession.qtest -v
    QORE_MODULE_DIR=build qore --enable-debug test/SshCommandSession.qtest -v
    QORE_MODULE_DIR=build qore --enable-debug test/SftpSession.qtest -v
    QORE_MODULE_DIR=build qore --enable-debug test/SftpServerDataProvider.qtest -v
    QORE_MODULE_DIR=build qore --enable-debug test/SftpServerDataProviderDataProvider.qtest -v
    QORE_MODULE_DIR=build qore --enable-debug test/VirtualSftpServer.qtest -v
    QORE_MODULE_DIR=build qore --enable-debug test/VirtualSftpInboundPolicyServer.qtest -v
else
    echo "SKIP: libssh-dev not available, skipping binary module build and tests"
fi
