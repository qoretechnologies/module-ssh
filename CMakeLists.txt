cmake_minimum_required(VERSION 3.5...3.31)

project(qore-ssh-module VERSION 1.0.0)

include(CheckCXXCompilerFlag)
find_package(Qore 2.0 REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBSSH REQUIRED libssh)

include_directories(${LIBSSH_INCLUDE_DIRS})
include_directories(${CMAKE_SOURCE_DIR}/src)

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

    # Two-phase doc build for the external binary module plus user sub-modules.
    # The initial docs-module pass generates ssh.tag. User-module docs are then
    # built with ssh.tag available, producing their own tag files. The final
    # docs-module-final pass rebuilds the binary module docs with user-module
    # tag files enabled so cross-references from the binary-module mainpage into
    # user-module symbols resolve deterministically.
    file(APPEND ${CMAKE_BINARY_DIR}/Doxyfile
        "\n# Suppress unresolved user-module cross-reference warnings in the initial pass\n"
        "WARN_IF_DOC_ERROR = NO\n")

    file(COPY_FILE ${CMAKE_BINARY_DIR}/Doxyfile ${CMAKE_BINARY_DIR}/Doxyfile.final)
    file(APPEND ${CMAKE_BINARY_DIR}/Doxyfile.final
        "\n# Final pass: enable user-module cross-references and re-enable doc error warnings\n"
        "TAGFILES = "
        "${CMAKE_BINARY_DIR}/SftpServerDataProvider.tag=../../SftpServerDataProvider/html "
        "${CMAKE_BINARY_DIR}/SshServerAuthProvider.tag=../../SshServerAuthProvider/html "
        "${CMAKE_BINARY_DIR}/SshServerConnections.tag=../../SshServerConnections/html "
        "${CMAKE_BINARY_DIR}/SshServerCommandProvider.tag=../../SshServerCommandProvider/html "
        "${CMAKE_BINARY_DIR}/QorusSshIntegration.tag=../../QorusSshIntegration/html "
        "\n")
    file(APPEND ${CMAKE_BINARY_DIR}/Doxyfile.final
        "WARN_IF_DOC_ERROR = YES\n")

    add_custom_target(docs-module-final
        COMMAND ${DOXYGEN_EXECUTABLE} ${CMAKE_BINARY_DIR}/Doxyfile.final
        COMMAND ${QORE_DOCS_ENV} ${QORE_QDX_COMMAND} --post ${CMAKE_BINARY_DIR}/docs/${module_name}/html
            ${CMAKE_BINARY_DIR}/docs/${module_name}/html/search
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Generating API documentation with Doxygen (final pass with user-module cross-references)"
        VERBATIM
    )
endif()

qore_external_user_module("qlib/SftpServerDataProvider" "")
qore_external_user_module("qlib/SshServerAuthProvider" "")
qore_external_user_module("qlib/SshServerConnections" "")
qore_external_user_module("qlib/SshServerCommandProvider" "")
qore_external_user_module("qlib/QorusSshIntegration" "")

if (DOXYGEN_FOUND)
    set(SSH_USER_MODULES
        SftpServerDataProvider
        SshServerAuthProvider
        SshServerConnections
        SshServerCommandProvider
        QorusSshIntegration
    )

    foreach(ssh_user_module IN LISTS SSH_USER_MODULES)
        file(APPEND ${CMAKE_BINARY_DIR}/doxygen/Doxyfile.${ssh_user_module}
            "\n# Suppress unresolved cross-reference warnings in the initial pass\n"
            "WARN_IF_DOC_ERROR = NO\n")

        file(COPY_FILE
            ${CMAKE_BINARY_DIR}/doxygen/Doxyfile.${ssh_user_module}
            ${CMAKE_BINARY_DIR}/doxygen/Doxyfile.${ssh_user_module}.final)

        set(ssh_user_tagfiles
            "TAGFILES = ${CMAKE_BINARY_DIR}/ssh.tag=../../ssh/html ")
        foreach(other_user_module IN LISTS SSH_USER_MODULES)
            if (NOT other_user_module STREQUAL ssh_user_module)
                string(APPEND ssh_user_tagfiles
                    "${CMAKE_BINARY_DIR}/${other_user_module}.tag=../../${other_user_module}/html ")
            endif()
        endforeach()

        file(APPEND ${CMAKE_BINARY_DIR}/doxygen/Doxyfile.${ssh_user_module}.final
            "\n# Final pass: enable cross-references to the binary module and all user modules\n"
            "${ssh_user_tagfiles}\n"
            "WARN_IF_DOC_ERROR = YES\n")

        add_custom_target(docs-${ssh_user_module}-final
            COMMAND ${DOXYGEN_EXECUTABLE} ${CMAKE_BINARY_DIR}/doxygen/Doxyfile.${ssh_user_module}.final
            COMMAND ${QORE_DOCS_ENV} ${QORE_QDX_COMMAND} --post ${CMAKE_BINARY_DIR}/docs/${ssh_user_module}/html
                ${CMAKE_BINARY_DIR}/docs/${ssh_user_module}/html/search
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
            COMMENT "Generating API documentation with Doxygen (final pass with cross-references) for: ${ssh_user_module}"
            VERBATIM
        )
        add_dependencies(docs-${ssh_user_module}-final
            docs-SftpServerDataProvider
            docs-SshServerAuthProvider
            docs-SshServerConnections
            docs-SshServerCommandProvider
            docs-QorusSshIntegration
        )
    endforeach()

    add_dependencies(docs-module-final
        docs-SftpServerDataProvider-final
        docs-SshServerAuthProvider-final
        docs-SshServerConnections-final
        docs-SshServerCommandProvider-final
        docs-QorusSshIntegration-final
    )
    add_dependencies(docs docs-module-final)
endif()
