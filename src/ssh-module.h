/*
    src/ssh-module.h

    Qore Programming Language

    Copyright (C) 2026 Qore Technologies, s.r.o.
*/

#ifndef _QORE_MODULE_SSH_H
#define _QORE_MODULE_SSH_H

#include <atomic>
#include <libssh/libssh.h>
#include <memory>
#include <qore/Qore.h>

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
DLLLOCAL extern qore_classid_t CID_SSHAUTHCONTEXT;
DLLLOCAL extern QoreClass* QC_SSHAUTHCONTEXT;
DLLLOCAL extern qore_classid_t CID_SSHSESSION;
DLLLOCAL extern QoreClass* QC_SSHSESSION;
DLLLOCAL extern qore_classid_t CID_SSHCOMMANDSESSION;
DLLLOCAL extern QoreClass* QC_SSHCOMMANDSESSION;
DLLLOCAL extern qore_classid_t CID_SFTPSESSION;
DLLLOCAL extern QoreClass* QC_SFTPSESSION;

DLLLOCAL QoreObject* ssh_new_session_object(QoreProgram* pgm, QoreHashNode* info, QoreHashNode* auth_info,
    QoreObject* logger, ssh_session session, std::shared_ptr<std::atomic<int64>> active_session_counter,
    int enabled_auth_methods_mask, int64 keepalive_interval_seconds, int64 idle_timeout_seconds,
    ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_new_command_session_object(QoreProgram* pgm, QoreHashNode* request, QoreObject* logger,
    ssh_channel channel, ssh_message request_msg, ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_new_sftp_session_object(QoreProgram* pgm, QoreHashNode* info, QoreHashNode* transfer_info,
    QoreObject* logger, QoreObject* backend, ssh_channel channel, ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_session_get_info(const QoreObject* session_obj, ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_session_wait_auth_context(const QoreObject* session_obj, QoreProgram* pgm, int timeout_ms,
    ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_session_wait_command_session(const QoreObject* session_obj, QoreProgram* pgm, int timeout_ms,
    ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_session_wait_sftp_session(const QoreObject* session_obj, QoreProgram* pgm, int timeout_ms,
    ExceptionSink* xsink);
DLLLOCAL int ssh_session_set_logger(const QoreObject* session_obj, QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_session_apply_auth_decision(const QoreObject* session_obj, const QoreHashNode* auth_context_info,
    const QoreHashNode* decision, ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_auth_context_get_info(const QoreObject* auth_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_auth_context_set_logger(const QoreObject* auth_obj, QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_auth_context_reply_public_key_ok(const QoreObject* auth_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_auth_context_apply_decision(const QoreObject* auth_obj, const QoreHashNode* decision,
    ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_command_session_get_request(const QoreObject* command_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_command_session_set_logger(const QoreObject* command_obj, QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_command_session_apply_result(const QoreObject* command_obj, const QoreHashNode* result,
    ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_sftp_session_get_info(const QoreObject* sftp_obj, ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_sftp_session_get_transfer_info(const QoreObject* sftp_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_set_logger(const QoreObject* sftp_obj, QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_set_backend(const QoreObject* sftp_obj, QoreObject* backend, ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_apply_factory_result(const QoreObject* sftp_obj, const QoreHashNode* result,
    ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_apply_transfer_info(const QoreObject* sftp_obj, const QoreHashNode* transfer_info,
    ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_clear_transfer_info(const QoreObject* sftp_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_session_send_banner(const QoreObject* session_obj, const std::string& banner, ExceptionSink* xsink);

#endif
