/*
    ssh-hashdecl.cpp

    Qore Programming Language

    Copyright (C) 2026 Qore Technologies, s.r.o.
*/

#include "ssh-module.h"

TypedHashDecl* init_hashdecl_SshListenerConfig(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshListenerConfig", "::Qore::Ssh::SshListenerConfig");
    hd->addMember("name", stringTypeInfo, QoreValue());
    hd->addMember("bind_address", stringTypeInfo, QoreValue());
    hd->addMember("port", bigIntTypeInfo, QoreValue());
    hd->addMember("host_keys", qore_get_complex_list_type(stringTypeInfo), QoreValue());
    hd->addMember("max_sessions", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("banner", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("enabled_auth_methods", qore_get_complex_list_or_nothing_type(stringTypeInfo), QoreValue());
    hd->addMember("allow_command_service", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("allow_sftp_service", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("server_options", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("keepalive_interval_seconds", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("idle_timeout_seconds", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("allowed_ciphers", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("allowed_kex", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("allowed_macs", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("allowed_hostkey_algorithms", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("allowed_addresses", qore_get_complex_list_or_nothing_type(stringTypeInfo), QoreValue());
    hd->addMember("denied_addresses", qore_get_complex_list_or_nothing_type(stringTypeInfo), QoreValue());
    hd->addMember("auth_banner", stringOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SshServerConfig(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshServerConfig", "::Qore::Ssh::SshServerConfig");
    hd->addMember("name", stringTypeInfo, QoreValue());
    hd->addMember("listeners", qore_get_complex_list_type(hashdeclSshListenerConfig->getTypeInfo(false)), QoreValue());
    hd->addMember("logger", objectOrNothingTypeInfo, QoreValue());
    hd->addMember("auth_provider", objectOrNothingTypeInfo, QoreValue());
    hd->addMember("auth_callback", codeOrNothingTypeInfo, QoreValue());
    hd->addMember("command_callback", codeOrNothingTypeInfo, QoreValue());
    hd->addMember("audit_callback", codeOrNothingTypeInfo, QoreValue());
    hd->addMember("sftp_factory_callback", codeOrNothingTypeInfo, QoreValue());
    hd->addMember("auth_config", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("command_config", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("audit_config", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("sftp_config", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("default_command_timeout_ms", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("log_authenticated_sessions", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("log_file_transfers", boolOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SshListenerStatus(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshListenerStatus", "::Qore::Ssh::SshListenerStatus");
    hd->addMember("name", stringTypeInfo, QoreValue());
    hd->addMember("bind_address", stringTypeInfo, QoreValue());
    hd->addMember("port", bigIntTypeInfo, QoreValue());
    hd->addMember("bound_port", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("running", boolTypeInfo, QoreValue());
    hd->addMember("active_session_count", bigIntTypeInfo, QoreValue());
    hd->addMember("last_error", hashdeclExceptionInfo->getTypeInfo(true), QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SshServerStatus(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshServerStatus", "::Qore::Ssh::SshServerStatus");
    hd->addMember("name", stringTypeInfo, QoreValue());
    hd->addMember("running", boolTypeInfo, QoreValue());
    hd->addMember("listener_count", bigIntTypeInfo, QoreValue());
    hd->addMember("active_session_count", bigIntTypeInfo, QoreValue());
    hd->addMember("started", dateOrNothingTypeInfo, QoreValue());
    hd->addMember("listeners", qore_get_complex_list_type(hashdeclSshListenerStatus->getTypeInfo(false)), QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SshSessionInfo(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshSessionInfo", "::Qore::Ssh::SshSessionInfo");
    hd->addMember("session_id", stringTypeInfo, QoreValue());
    hd->addMember("server_name", stringTypeInfo, QoreValue());
    hd->addMember("listener_name", stringTypeInfo, QoreValue());
    hd->addMember("remote_address", stringTypeInfo, QoreValue());
    hd->addMember("remote_port", bigIntTypeInfo, QoreValue());
    hd->addMember("local_address", stringTypeInfo, QoreValue());
    hd->addMember("local_port", bigIntTypeInfo, QoreValue());
    hd->addMember("username", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("authenticated", boolTypeInfo, QoreValue());
    hd->addMember("auth_method", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("principal", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("session_data", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("command_policy", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("sftp_policy", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("started", dateTypeInfo, QoreValue());
    hd->addMember("last_activity", dateTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SshAuthContextInfo(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshAuthContextInfo", "::Qore::Ssh::SshAuthContextInfo");
    hd->addMember("session_id", stringTypeInfo, QoreValue());
    hd->addMember("server_name", stringTypeInfo, QoreValue());
    hd->addMember("listener_name", stringTypeInfo, QoreValue());
    hd->addMember("remote_address", stringTypeInfo, QoreValue());
    hd->addMember("remote_port", bigIntTypeInfo, QoreValue());
    hd->addMember("username", stringTypeInfo, QoreValue());
    hd->addMember("auth_method", stringTypeInfo, QoreValue());
    hd->addMember("password", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("public_key", binaryOrNothingTypeInfo, QoreValue());
    hd->addMember("public_key_type", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("service", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SshAuthDecision(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshAuthDecision", "::Qore::Ssh::SshAuthDecision");
    hd->addMember("accepted", boolTypeInfo, QoreValue());
    hd->addMember("partial", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("principal", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("message", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("allowed_auth_methods", qore_get_complex_list_or_nothing_type(stringTypeInfo), QoreValue());
    hd->addMember("command_policy", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("sftp_policy", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("session_data", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("audit_data", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SshCommandRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshCommandRequest", "::Qore::Ssh::SshCommandRequest");
    hd->addMember("session_id", stringTypeInfo, QoreValue());
    hd->addMember("server_name", stringTypeInfo, QoreValue());
    hd->addMember("listener_name", stringTypeInfo, QoreValue());
    hd->addMember("username", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("principal", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("command", stringTypeInfo, QoreValue());
    hd->addMember("arguments", qore_get_complex_list_or_nothing_type(stringTypeInfo), QoreValue());
    hd->addMember("environment", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SshCommandResult(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshCommandResult", "::Qore::Ssh::SshCommandResult");
    hd->addMember("accepted", boolTypeInfo, QoreValue());
    hd->addMember("exit_status", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("message", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("stdout", binaryOrNothingTypeInfo, QoreValue());
    hd->addMember("stderr", binaryOrNothingTypeInfo, QoreValue());
    hd->addMember("result_data", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpSessionInfo(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpSessionInfo", "::Qore::Ssh::SftpSessionInfo");
    hd->addMember("session_info", hashdeclSshSessionInfo->getTypeInfo(false), QoreValue());
    hd->addMember("principal", stringTypeInfo, QoreValue());
    hd->addMember("root_dir", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("read_only", boolTypeInfo, QoreValue());
    hd->addMember("session_data", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpProtocolMessage(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpProtocolMessage", "::Qore::Ssh::SftpProtocolMessage");
    hd->addMember("type", bigIntTypeInfo, QoreValue());
    hd->addMember("name", stringTypeInfo, QoreValue());
    hd->addMember("request_id", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("version", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("payload", binaryOrNothingTypeInfo, QoreValue());
    hd->addMember("payload_size", bigIntTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpTransferRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpTransferRequest", "::Qore::Ssh::SftpTransferRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(false), QoreValue());
    hd->addMember("operation", stringTypeInfo, QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("target_path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("temporary_path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("size", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpTransferInfo(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpTransferInfo", "::Qore::Ssh::SftpTransferInfo");
    hd->addMember("operation", stringTypeInfo, QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("temporary_path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("final_path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("size", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("checksum", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("atomic_publish", boolTypeInfo, QoreValue());
    hd->addMember("completed", boolTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpTransferDecision(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpTransferDecision", "::Qore::Ssh::SftpTransferDecision");
    hd->addMember("allowed", boolTypeInfo, QoreValue());
    hd->addMember("message", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("transfer_info", hashdeclSftpTransferInfo->getTypeInfo(false), QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpPathRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpPathRequest", "::Qore::Ssh::SftpPathRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("follow_symlinks", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("operation", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpPathInfo(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpPathInfo", "::Qore::Ssh::SftpPathInfo");
    hd->addMember("path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("exists", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("directory", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("symlink", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("target_path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("size", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("permissions", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpListResult(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpListResult", "::Qore::Ssh::SftpListResult");
    hd->addMember("path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("entries", qore_get_complex_list_or_nothing_type(autoHashTypeInfo), QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpOpenRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpOpenRequest", "::Qore::Ssh::SftpOpenRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("operation", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("pflags", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("offset", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("length", bigIntOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpOpenResult(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpOpenResult", "::Qore::Ssh::SftpOpenResult");
    hd->addMember("path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("exists", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("data", binaryOrNothingTypeInfo, QoreValue());
    hd->addMember("backend_handle", autoTypeInfo, QoreValue());
    hd->addMember("size", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("permissions", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("transfer_info", hashdeclSftpTransferInfo->getTypeInfo(true), QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpOperationResult(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpOperationResult", "::Qore::Ssh::SftpOperationResult");
    hd->addMember("path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("exists", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("completed", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("message", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("transfer_info", hashdeclSftpTransferInfo->getTypeInfo(true), QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpRenameRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpRenameRequest", "::Qore::Ssh::SftpRenameRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("target_path", stringTypeInfo, QoreValue());
    hd->addMember("operation", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpSubmissionRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpSubmissionRequest", "::Qore::Ssh::SftpSubmissionRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("source_path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("data", binaryOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    hd->addMember("checksum", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("move", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("create_parents", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("operation", stringOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpOperationRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpOperationRequest", "::Qore::Ssh::SftpOperationRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("target_path", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("operation", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("completion_mode", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpReadRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpReadRequest", "::Qore::Ssh::SftpReadRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("operation", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("backend_handle", autoTypeInfo, QoreValue());
    hd->addMember("open_result", hashdeclSftpOpenResult->getTypeInfo(true), QoreValue());
    hd->addMember("offset", bigIntTypeInfo, QoreValue());
    hd->addMember("length", bigIntTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpReadResult(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpReadResult", "::Qore::Ssh::SftpReadResult");
    hd->addMember("data", binaryOrNothingTypeInfo, QoreValue());
    hd->addMember("eof", boolOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpWriteRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpWriteRequest", "::Qore::Ssh::SftpWriteRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("operation", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("backend_handle", autoTypeInfo, QoreValue());
    hd->addMember("open_result", hashdeclSftpOpenResult->getTypeInfo(true), QoreValue());
    hd->addMember("offset", bigIntTypeInfo, QoreValue());
    hd->addMember("data", binaryTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpCloseRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpCloseRequest", "::Qore::Ssh::SftpCloseRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("operation", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("backend_handle", autoTypeInfo, QoreValue());
    hd->addMember("open_result", hashdeclSftpOpenResult->getTypeInfo(true), QoreValue());
    hd->addMember("data", binaryOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SshActiveSessionInfo(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SshActiveSessionInfo", "::Qore::Ssh::SshActiveSessionInfo");
    hd->addMember("session_id", stringTypeInfo, QoreValue());
    hd->addMember("remote_address", stringTypeInfo, QoreValue());
    hd->addMember("remote_port", bigIntTypeInfo, QoreValue());
    hd->addMember("username", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("principal", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("auth_method", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("started", dateTypeInfo, QoreValue());
    hd->addMember("last_activity", dateTypeInfo, QoreValue());
    hd->addMember("bytes_read", bigIntTypeInfo, QoreValue());
    hd->addMember("bytes_written", bigIntTypeInfo, QoreValue());
    hd->addMember("sftp_operations", bigIntTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpSymlinkRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpSymlinkRequest", "::Qore::Ssh::SftpSymlinkRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("link_path", stringTypeInfo, QoreValue());
    hd->addMember("target_path", stringTypeInfo, QoreValue());
    hd->addMember("operation", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpSetstatRequest(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpSetstatRequest", "::Qore::Ssh::SftpSetstatRequest");
    hd->addMember("session_info", hashdeclSftpSessionInfo->getTypeInfo(true), QoreValue());
    hd->addMember("path", stringTypeInfo, QoreValue());
    hd->addMember("handle", stringOrNothingTypeInfo, QoreValue());
    hd->addMember("operation", stringTypeInfo, QoreValue());
    hd->addMember("size", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("uid", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("gid", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("permissions", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("atime", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("mtime", bigIntOrNothingTypeInfo, QoreValue());
    hd->addMember("attr_flags", bigIntTypeInfo, QoreValue());
    hd->addMember("metadata", autoHashOrNothingTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}

TypedHashDecl* init_hashdecl_SftpStatvfsResult(QoreNamespace& ns) {
    TypedHashDecl* hd = new TypedHashDecl("SftpStatvfsResult", "::Qore::Ssh::SftpStatvfsResult");
    hd->addMember("f_bsize", bigIntTypeInfo, QoreValue());
    hd->addMember("f_frsize", bigIntTypeInfo, QoreValue());
    hd->addMember("f_blocks", bigIntTypeInfo, QoreValue());
    hd->addMember("f_bfree", bigIntTypeInfo, QoreValue());
    hd->addMember("f_bavail", bigIntTypeInfo, QoreValue());
    hd->addMember("f_files", bigIntTypeInfo, QoreValue());
    hd->addMember("f_ffree", bigIntTypeInfo, QoreValue());
    hd->addMember("f_favail", bigIntTypeInfo, QoreValue());
    hd->addMember("f_fsid", bigIntTypeInfo, QoreValue());
    hd->addMember("f_flag", bigIntTypeInfo, QoreValue());
    hd->addMember("f_namemax", bigIntTypeInfo, QoreValue());
    ns.addSystemHashDecl(hd);
    return hd;
}
