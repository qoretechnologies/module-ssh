#!/bin/bash

set -e
set -x

ENV_FILE=/tmp/env.sh

. ${ENV_FILE}

cwd=`pwd`
if [ -z "${MODULE_SRC_DIR}" ]; then
    if [ -e "$cwd/src/ssh-module.h" ]; then
        MODULE_SRC_DIR=$cwd
    else
        MODULE_SRC_DIR=$WORKDIR/module-ssh
    fi
fi
echo "export MODULE_SRC_DIR=${MODULE_SRC_DIR}" >> ${ENV_FILE}

echo "export QORE_UID=999" >> ${ENV_FILE}
echo "export QORE_GID=999" >> ${ENV_FILE}

. ${ENV_FILE}

export MAKE_JOBS=4

echo && echo "-- building module --"
mkdir -p ${MODULE_SRC_DIR}/build
cd ${MODULE_SRC_DIR}/build
cmake .. -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}
make -j${MAKE_JOBS}
make install

# Verify that source-owned provider presentation catalogs match this checkout.
${MODULE_SRC_DIR}/test/docker_test/check-i18n.sh

groupadd -o -g ${QORE_GID} qore
useradd -o -m -d /home/qore -u ${QORE_UID} -g ${QORE_GID} qore

chown -R qore:qore ${MODULE_SRC_DIR}

export QORE_MODULE_DIR=${MODULE_SRC_DIR}/qlib:${MODULE_SRC_DIR}/build:${QORE_MODULE_DIR}
cd ${MODULE_SRC_DIR}
# the tests must load the modules that this job built, not the copies that the image already has
${MODULE_SRC_DIR}/test/docker_test/check-loaded-modules.sh ${MODULE_SRC_DIR}/build gosu qore:qore

for test in test/*.qtest; do
    gosu qore:qore qore --enable-debug $test -vv
done

# ... and they still do once the tests have run
${MODULE_SRC_DIR}/test/docker_test/check-loaded-modules.sh ${MODULE_SRC_DIR}/build gosu qore:qore
