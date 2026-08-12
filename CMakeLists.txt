cmake_minimum_required(VERSION 3.5...3.31)

project(qore-ssh-module VERSION 1.0.0)

include(CheckCXXCompilerFlag)
find_package(Qore 2.3 REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBSSH REQUIRED libssh)

include_directories(${LIBSSH_INCLUDE_DIRS})
include_directories(${CMAKE_SOURCE_DIR}/src)
include_directories(${CMAKE_BINARY_DIR})

# Optional libssh feature probe: the file-format export API
# (ssh_file_format_e + ssh_pki_export_*_format()) was added in libssh 0.11.0.
# Detect it by symbol presence rather than a version macro so the module also
# builds against vendor backports/patched libssh where the version int lags.
include(CheckSymbolExists)
set(_saved_cmake_required_includes "${CMAKE_REQUIRED_INCLUDES}")
set(_saved_cmake_required_libraries "${CMAKE_REQUIRED_LIBRARIES}")
list(APPEND CMAKE_REQUIRED_INCLUDES ${LIBSSH_INCLUDE_DIRS})
# ssh_pki_export_privkey_file_format is a function, so check_symbol_exists must
# link libssh to resolve it; without the library it fails with a spurious
# "undefined reference" even though the declaration is present.
if (LIBSSH_LINK_LIBRARIES)
    list(APPEND CMAKE_REQUIRED_LIBRARIES ${LIBSSH_LINK_LIBRARIES})
else()
    list(APPEND CMAKE_REQUIRED_LIBRARIES ${LIBSSH_LDFLAGS})
endif()
check_symbol_exists(ssh_pki_export_privkey_file_format "libssh/libssh.h"
    HAVE_SSH_FILE_FORMAT)
set(CMAKE_REQUIRED_INCLUDES "${_saved_cmake_required_includes}")
set(CMAKE_REQUIRED_LIBRARIES "${_saved_cmake_required_libraries}")
if (HAVE_SSH_FILE_FORMAT)
    message(STATUS "libssh file-format export API: present (HAVE_SSH_FILE_FORMAT)")
else()
    message(STATUS "libssh file-format export API: absent "
        "(libssh < 0.11.0; non-default key formats will raise a runtime error)")
endif()

# explicit_bzero() is a glibc/BSD secure-erase primitive; it is not available
# on all platforms (notably macOS), so probe for it and fall back to a portable
# volatile-write erase in ssh-module.h when absent
check_symbol_exists(explicit_bzero "string.h;strings.h" HAVE_EXPLICIT_BZERO)
if (HAVE_EXPLICIT_BZERO)
    message(STATUS "secure memory erase: explicit_bzero() (HAVE_EXPLICIT_BZERO)")
else()
    message(STATUS "secure memory erase: portable volatile-write fallback")
endif()

configure_file(${CMAKE_SOURCE_DIR}/cmake/config.h.cmake
    ${CMAKE_BINARY_DIR}/config.h)

CHECK_CXX_COMPILER_FLAG("-std=c++11" COMPILER_SUPPORTS_CXX11)
if(COMPILER_SUPPORTS_CXX11)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")
else()
    message(FATAL_ERROR "The compiler ${CMAKE_CXX_COMPILER} has no C++11 support.")
endif()

set(module_name "ssh")

set(QPP_SRC
    src/QC_SftpSession.qpp
    src/QC_SshCommandSession.qpp
    src/QC_SshKey.qpp
    src/QC_SshServer.qpp
    src/QC_SshSession.qpp
    src/ssh.qpp
)

set(CPP_SRC
)

set(QORE_DOX_TMPL_SRC
  docs/mainpage.doxygen.tmpl
  docs/binary-typed-symbols.doxygen.tmpl
  docs/getting-started.doxygen.tmpl
  docs/authentication.doxygen.tmpl
  docs/sftp-backends.doxygen.tmpl
  docs/ssh-key-management.doxygen.tmpl
  docs/cookbook.doxygen.tmpl
  docs/typed-contracts.doxygen.tmpl
  docs/release-notes.doxygen.tmpl
)

qore_wrap_qpp_value(QPP_SOURCES METALIST QPP_META_SRC ${QPP_SRC})

add_library(${module_name} MODULE ${CPP_SRC} ${QPP_SOURCES})
qore_external_binary_module(${module_name} ${PROJECT_VERSION} ${LIBSSH_LDFLAGS})

if (COMMAND qore_install_qpp_metadata)
    qore_install_qpp_metadata(${module_name} ${QPP_META_SRC})
else()
    install(FILES ${QPP_META_SRC}
            DESTINATION ${CMAKE_INSTALL_DATADIR}/qore/metadata)
endif()

if (DOXYGEN_FOUND)
    qore_wrap_dox(QORE_DOX_SRC ${QORE_DOX_TMPL_SRC})
    add_custom_target(QORE_MOD_DOX_FILES DEPENDS ${QORE_DOX_SRC})
    add_dependencies(docs-module QORE_MOD_DOX_FILES)

    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/doxygen/qlib/SftpServerDataProvider")
    file(WRITE
        "${CMAKE_BINARY_DIR}/doxygen/qlib/SftpServerDataProvider/generic-sftp-server-exchange-logo.svg.dox.h"
        "/** @file generic-sftp-server-exchange-logo.svg.dox.h\n"
        "    @brief Generic SFTP Server Exchange DataProvider logo file.\n"
        "*/\n"
    )
endif()

qore_external_user_module("qlib/SftpServerDataProvider" "")
qore_external_user_module("qlib/SshServerAuthProvider" "")
qore_external_user_module("qlib/SshServerConnections" "")
qore_external_user_module("qlib/SshServerCommandProvider" "SshServerConnections")

# Reconcile the installed i18n catalog root against the fragments these modules
# currently own.  Installing catalogs is otherwise additive: a fragment installed by
# an earlier generation of these sources survives every later install, is still
# discovered, and makes catalog composition fail as soon as the current generation
# describes the same app differently.
#
# This must come after every call above that installs catalogs, both because those
# calls record the fragment set and because install() rules run in declaration order,
# which is what publishes the manifest after the fragments it describes.  Removals are
# scoped to this project, so fragments Qore and other products install into the same
# shared catalog root are untouched.  Guarded because the helper arrived in Qore 2.3.
if (COMMAND qore_finalize_catalog_install)
    qore_finalize_catalog_install()
endif()

# Two-phase doc build so the binary module's mainpage and doc pages can @ref
# into user sub-module symbols.  qore_external_user_module() already wires
# ssh.tag into each user module's TAGFILES for the reverse direction, and the
# SshServerCommandProvider -> SshServerConnections cross-reference is supplied
# via that macro's dependency list above.
qore_binary_module_two_phase_docs(${module_name}
    "SftpServerDataProvider;SshServerAuthProvider;SshServerConnections;SshServerCommandProvider")
