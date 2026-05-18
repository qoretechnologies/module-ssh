# module-ssh Error Taxonomy

## Purpose

This document fixes the initial exception naming scheme for `module-ssh`.

## Rules

- use one family per subsystem
- prefer stable names over highly specific one-off names
- use data returns for expected denials where practical
- reserve exceptions for invalid state, runtime failures, and framework-level errors

## Families

### Server Startup and Configuration

- `SSH-MODULE-INIT-ERROR`
- `SSHSERVER-CONFIG-ERROR`
- `SSHLISTENER-CONFIG-ERROR`
- `SFTPSERVER-CONFIG-ERROR`

### Listener and Session Lifecycle

- `SSHSERVER-ERROR`
- `SSHLISTENER-ERROR`
- `SSHSESSION-ERROR`
- `SSHSESSION-NOT-AUTHENTICATED`
- `SSHSESSION-DISCONNECTED`

### Authentication and Authorization

- `SSH-AUTH-ERROR`
- `SSH-AUTH-DENIED`
- `SSH-AUTH-CALLBACK-ERROR`
- `SSH-COMMAND-DENIED`
- `SSH-COMMAND-CALLBACK-ERROR`

### Command Processing

- `SSHCOMMAND-ERROR`
- `SSHCOMMAND-INPUT-CLOSED`
- `SSHCOMMAND-TIMEOUT`

### SFTP and File Workflows

- `SFTPSERVER-ERROR`
- `SFTPSESSION-ERROR`
- `SFTP-PATH-DENIED`
- `SFTP-TRANSFER-ERROR`
- `SFTP-ATOMIC-PUBLISH-ERROR`

### Shared Framework Errors

Use existing Qore error families directly where applicable:

- `FILESYSTEM-ACCESS-DENIED`
- `NETWORK-ACCESS-DENIED`
- `PROGRAM-INTERRUPTED`
- `THREAD-CANCELLED`

## Notes

- callback implementations should prefer returning `accepted: False` for normal
  denials and use exceptions only for internal failures
- the binary module should wrap library failures in the nearest stable family
