# module-ssh Error Taxonomy

/*  error-taxonomy.md Copyright 2026 Qore Technologies, s.r.o.

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
*/

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
