/*
    src/ssh-module.h

    Qore Programming Language

    Copyright (C) 2026 Qore Technologies, s.r.o.
*/

#ifndef _QORE_MODULE_SSH_H
#define _QORE_MODULE_SSH_H

#include <atomic>
#include <cstring>
#include <libssh/libssh.h>
#include <libssh/libssh_version.h>
#include <map>
#include <memory>
#include <mutex>
#include <qore/Qore.h>
#include <string>

#include "config.h"

//! libssh >= 0.11.0 adds ssh_file_format_e and *_format() export functions
/** HAVE_SSH_FILE_FORMAT is probed at configure time via check_symbol_exists()
    and propagated through config.h.  If the configure-time probe is unavailable
    (e.g. the header is compiled outside the CMake build), fall back to a libssh
    version test so the header remains self-contained.  The flag is presence-
    based: defined when the API is available, otherwise left undefined. */
#ifndef HAVE_SSH_FILE_FORMAT
#if LIBSSH_VERSION_INT >= SSH_VERSION_INT(0, 11, 0)
#define HAVE_SSH_FILE_FORMAT 1
#endif
#endif

//! Thread-safe registry of live accepted SSH sessions.
/** Owned by @ref SshServerPriv through a @c std::shared_ptr and referenced by each live
    @c SshSession through a @c std::weak_ptr.  This decouples the registry entry lifetime from
    both the server and the session: a session that outlives its server unregisters safely
    (the weak_ptr has expired and the erase is a no-op), and the registry frees any remaining
    entries when the last owner (the server) is destroyed.  Entries are removed deterministically
    when the owning session disconnects, so the map cannot grow without bound. */
struct SshActiveSessionRegistry {
    std::mutex mutex;
    //! session_id -> private SshSessionInfo snapshot
    std::map<std::string, QoreHashNode*> sessions;

    DLLLOCAL ~SshActiveSessionRegistry() {
        for (auto& pair : sessions) {
            if (pair.second) {
                pair.second->deref(nullptr);
            }
        }
    }
};

DLLLOCAL extern const TypedHashDecl* hashdeclSshListenerConfig;
DLLLOCAL extern const TypedHashDecl* hashdeclSshServerConfig;
DLLLOCAL extern const TypedHashDecl* hashdeclSshListenerStatus;
DLLLOCAL extern const TypedHashDecl* hashdeclSshServerStatus;
DLLLOCAL extern const TypedHashDecl* hashdeclSshSessionInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSshAuthContextInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSshAuthDecision;
DLLLOCAL extern const TypedHashDecl* hashdeclSshCommandRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSshCommandResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpSessionInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpProtocolMessage;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpTransferRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpTransferInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpTransferDecision;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpPathRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpPathInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpListResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpOpenRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpOpenResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpOperationResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpRenameRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpSubmissionRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpOperationRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpReadRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpReadResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpWriteRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpCloseRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSshActiveSessionInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpSymlinkRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpSetstatRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpStatvfsResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSshKeyInfo;
DLLLOCAL extern qore_classid_t CID_SSHKEY;
DLLLOCAL extern QoreClass* QC_SSHKEY;
DLLLOCAL extern qore_classid_t CID_SSHAUTHCONTEXT;
DLLLOCAL extern QoreClass* QC_SSHAUTHCONTEXT;
DLLLOCAL extern qore_classid_t CID_SSHSESSION;
DLLLOCAL extern QoreClass* QC_SSHSESSION;
DLLLOCAL extern qore_classid_t CID_SSHCOMMANDSESSION;
DLLLOCAL extern QoreClass* QC_SSHCOMMANDSESSION;
DLLLOCAL extern qore_classid_t CID_SFTPSESSION;
DLLLOCAL extern QoreClass* QC_SFTPSESSION;
DLLLOCAL QoreObject* ssh_new_session_object(QoreProgram* pgm, QoreHashNode* info, QoreHashNode* auth_info,
    const QoreObject* logger, ssh_session session, std::shared_ptr<std::atomic<int64>> active_session_counter,
    int enabled_auth_methods_mask, int64 keepalive_interval_seconds, int64 idle_timeout_seconds,
    ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_new_command_session_object(QoreProgram* pgm, QoreHashNode* request, const QoreObject* logger,
    ssh_channel channel, ssh_message request_msg, ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_new_sftp_session_object(QoreProgram* pgm, QoreHashNode* info, QoreHashNode* transfer_info,
    const QoreObject* logger, QoreObject* backend, ssh_channel channel, ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_session_get_info(const QoreObject* session_obj, ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_session_wait_auth_context(const QoreObject* session_obj, QoreProgram* pgm, int timeout_ms,
    ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_session_wait_command_session(const QoreObject* session_obj, QoreProgram* pgm, int timeout_ms,
    ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_session_wait_sftp_session(const QoreObject* session_obj, QoreProgram* pgm, int timeout_ms,
    ExceptionSink* xsink);
DLLLOCAL int ssh_session_set_logger(const QoreObject* session_obj, const QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_session_apply_auth_decision(const QoreObject* session_obj, const QoreHashNode* auth_context_info,
    const QoreHashNode* decision, ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_auth_context_get_info(const QoreObject* auth_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_auth_context_set_logger(const QoreObject* auth_obj, const QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_auth_context_reply_public_key_ok(const QoreObject* auth_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_auth_context_apply_decision(const QoreObject* auth_obj, const QoreHashNode* decision,
    ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_command_session_get_request(const QoreObject* command_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_command_session_set_logger(const QoreObject* command_obj, const QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_command_session_apply_result(const QoreObject* command_obj, const QoreHashNode* result,
    ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_sftp_session_get_info(const QoreObject* sftp_obj, ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_sftp_session_get_transfer_info(const QoreObject* sftp_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_set_logger(const QoreObject* sftp_obj, const QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_set_backend(const QoreObject* sftp_obj, QoreObject* backend, ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_apply_factory_result(const QoreObject* sftp_obj, const QoreHashNode* result,
    ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_apply_transfer_info(const QoreObject* sftp_obj, const QoreHashNode* transfer_info,
    ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_clear_transfer_info(const QoreObject* sftp_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_session_send_banner(const QoreObject* session_obj, const std::string& banner, ExceptionSink* xsink);
//! Binds a live SshSession to the server's active-session registry so it deterministically
//! unregisters itself on disconnect (see SshActiveSessionRegistry).
DLLLOCAL void ssh_session_set_registry(const QoreObject* session_obj,
    std::weak_ptr<SshActiveSessionRegistry> registry, const std::string& session_id);

//! securely erases a buffer that may contain sensitive key material
/** Uses explicit_bzero() when the C library provides it (glibc/BSD); otherwise
    falls back to a portable volatile-pointer write loop, which the compiler is
    not permitted to optimize away. Use this instead of explicit_bzero()
    directly so the code builds on platforms without it (e.g. macOS). */
static inline void ssh_secure_bzero(void* p, size_t n) {
#ifdef HAVE_EXPLICIT_BZERO
    explicit_bzero(p, n);
#else
    volatile unsigned char* vp = static_cast<volatile unsigned char*>(p);
    while (n--) {
        *vp++ = 0;
    }
#endif
}

#endif
