# module-ssh Callback and Provider Contracts

/*  callback-contracts.md Copyright 2026 Qore Technologies, s.r.o.

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

This document fixes the initial callback and provider contracts for the `ssh` module so that
the binary implementation and user-module integration layers can be developed
independently without drift.

## Principles

- normal authorization denials should be data-driven return values, not exceptions
- exceptions are reserved for internal failures and invalid runtime state
- providers and callbacks must be safe to invoke repeatedly across concurrent sessions
- provider and callback results must be auditable and suitable for integration

## Authentication

Primary provider signature:

```qore
hash<SshAuthDecision> authenticate(hash<SshAuthContextInfo> ctx)
```

Contract:

- listener-level `enabled_auth_methods` filtering happens before the provider is
  invoked
- disabled auth methods are rejected automatically and are not surfaced as
  `SshAuthContext` objects
- the provider receives one authentication attempt
- password auth attempts include `password`
- public-key auth attempts include:
  - `public_key`
  - `public_key_type`
  - `metadata.public_key_state`
- the provider should return `accepted: False` for expected failures
- the provider may enrich the session with `principal`, `session_data`, and policy
- returned `command_policy` and `sftp_policy` become the post-login policy basis

Low-level fallback signature:

```qore
hash<SshAuthDecision> authCallback(hash<SshAuthContext> ctx)
```

`auth_callback` remains available on the raw binary-module config surface, but
provider objects are the primary public auth abstraction.

## Command Dispatch

Signature:

```qore
hash<SshCommandResult> commandCallback(hash<SshCommandRequest> req)
```

Contract:

- this callback is the only path for command execution in this module
- unrestricted shell execution is not part of the default contract
- listener-level service gates are enforced first:
  - `allow_command_service` blocks exec and non-SFTP subsystem requests
  - `allow_sftp_service` blocks the `sftp` subsystem request
- exec requests are denied unless `command_policy.mode` allows command execution
- subsystem requests are denied unless `command_policy.mode` allows subsystem
  execution and the requested subsystem is explicitly allowed
- callbacks may implement:
  - direct request/response execution
  - streaming through `SshCommandSession`
  - subsystem dispatch if explicitly allowed

Initial command policy direction:

- `mode: "command-only"` allows exec only
- `mode: "subsystem-only"` allows subsystem requests only
- `mode: "command-and-subsystem"` allows both exec and subsystem requests
- subsystem requests additionally require either:
  - `allow_all_subsystems: True`, or
  - `allowed_subsystems` containing the requested subsystem name

## SFTP Backend and Path Policy

Session-factory signature:

```qore
hash<auto> sftpFactoryCallback(hash<SftpSessionInfo> info)
```

Contract:

- the callback is invoked after the live `sftp` subsystem request has been
  accepted and surfaced as a `SftpSession`
- returning `NOTHING` leaves the accepted session metadata unchanged
- returning a hash may override:
  - `root_dir`
  - `read_only`
  - `session_data`
  - `transfer_info`
  - `backend`
- the callback does not replace Qore sandboxing checks; it complements them
- transfer-level path policy remains a later layer on top of this session
  factory hook

Backend-binding direction:

```qore
object sftpBackendFactory(hash<SftpSessionInfo> info)
```

Backend contract:

- the module must support attaching a backend object to a live `SftpSession`
- the backend may represent:
  - a local filesystem adapter
  - a fully virtual filesystem with no real backing paths
  - an atomic exchange adapter for submit/retrieve workflows
- backend failures should be surfaced as typed SFTP failures, not as protocol
  corruption
- the binary module remains responsible for:
  - protocol decoding and encoding
  - request lifecycle
  - audit emission
  - cancellation
  - sandboxing for any real local filesystem access performed by built-in
    adapters

Initial backend operation direction:

```qore
hash<SftpPathInfo> stat(hash<SftpPathRequest> req)
hash<SftpListResult> list(hash<SftpPathRequest> req)
hash<SftpOpenResult> openRead(hash<SftpOpenRequest> req)
hash<SftpOpenResult> openWrite(hash<SftpOpenRequest> req)
hash<SftpOperationResult> removePath(hash<SftpPathRequest> req)
hash<SftpOperationResult> rename(hash<SftpRenameRequest> req)
hash<SftpOperationResult> mkdir(hash<SftpPathRequest> req)
hash<SftpOperationResult> rmdir(hash<SftpPathRequest> req)
```

Typed streamed backend direction:

```qore
hash<SftpReadResult> read(hash<SftpReadRequest> req)
hash<SftpOperationResult> write(hash<SftpWriteRequest> req)
hash<SftpOperationResult> closeRead(hash<SftpCloseRequest> req)
hash<SftpOperationResult> closeWrite(hash<SftpCloseRequest> req)
```

These backend methods are the stable public direction for full filesystem
virtualization. Users should not have to implement raw packet processing to
virtualize the SFTP namespace.

Compatibility note:

- the module still tolerates looser `hash<auto>` backend implementations for
  compatibility
- however, the typed `hash<...>` signatures above are now the intended public
  API and the default UX
- `SftpSession` now dispatches typed request hashes for both the low-level
  filesystem verbs and the high-level atomic-exchange verbs, so typed-only
  backends work end to end

Easy backend option:

- `SftpServerDataProvider::VirtualSftpFilesystem` now provides an in-memory
  implementation of this contract so users can expose a virtual SFTP namespace
  without writing the backend methods themselves
- the helper is intended for direct `SftpSession::setBackend()` use and for
  return values from `sftp_factory_callback`
- `SftpServerDataProvider::VirtualSftpExchange` now provides a higher-level
  inbound/outbound exchange backend on top of the same contract for
  queue-style file submission and retrieval scenarios
- `SftpServerDataProvider::VirtualSftpExchangeRecordStore` now provides a
  record-oriented facade on top of `VirtualSftpExchange` for Qorus-style
  submit/list/retrieve/claim/archive workflows

Current implementation step:

- when a backend object is attached to `SftpSession`, `processNextRequest()`
  routes `SSH_FXP_REALPATH` and `SSH_FXP_STAT` / `SSH_FXP_LSTAT` through the
  backend `stat()` method
- when a backend object is attached to `SftpSession`, `processNextRequest()`
  routes `SSH_FXP_OPENDIR` through the backend `list()` method and manages
  `SSH_FXP_READDIR` / `SSH_FXP_CLOSE` protocol handles internally
- when a backend object is attached to `SftpSession`, `processNextRequest()`
  routes `SSH_FXP_OPEN` through the backend `openRead()` method and manages
  `SSH_FXP_FSTAT` / `SSH_FXP_READ` / `SSH_FXP_CLOSE` protocol file handles
  internally
- the current easy virtual-retrieval contract allows `openRead()` to return
  metadata plus a full in-memory `data` payload, which the binary module serves
  in chunked `SSH_FXP_READ` replies
- streamed virtual retrieval is also supported: `openRead()` may return an
  opaque `backend_handle` instead of `data`, and then the binary module routes
  `SSH_FXP_READ` through backend `read(hash<SftpReadRequest>)` and final
  `SSH_FXP_CLOSE` through backend `closeRead(hash<SftpCloseRequest>)`
- backend objects implementing `read()` must also implement `closeRead()`, and
  vice versa
- when a backend object is attached to `SftpSession`, `processNextRequest()`
  routes write-oriented `SSH_FXP_OPEN` requests through backend `openWrite()`,
  buffers `SSH_FXP_WRITE` payloads in memory, and finalizes the submission with
  backend `closeWrite(hash<SftpCloseRequest>)` on `SSH_FXP_CLOSE`
- streamed virtual submission is also supported: `openWrite()` may return an
  opaque `backend_handle`, and then the binary module routes `SSH_FXP_WRITE`
  chunks through backend `write(hash<SftpWriteRequest>)` while still invoking
  backend `closeWrite(hash<SftpCloseRequest>)` for finalization on
  `SSH_FXP_CLOSE`
- backend objects implementing `openWrite()` must also implement
  `closeWrite()`, and vice versa
- backend objects implementing `write()` must also implement `openWrite()` and
  `closeWrite()`
- when a backend object is attached to `SftpSession`, `processNextRequest()`
  routes `SSH_FXP_REMOVE`, `SSH_FXP_RENAME`, `SSH_FXP_MKDIR`, and
  `SSH_FXP_RMDIR` through backend `removePath()`, `rename()`, `mkdir()`, and
  `rmdir()` methods
- the Qore-facing backend contract uses `removePath()` rather than `remove()`
  because `remove` is not a practical plain method name in Qore class
  definitions
- local rooted-filesystem behavior remains the fallback when no backend is
  attached

Transfer-policy signature:

```qore
hash<SftpTransferDecision> pathPolicyCallback(hash<SftpTransferRequest> req)
```

Transfer-policy contract:

- the callback is invoked by `SshServer::evaluateSftpTransferRequest()`
- the built-in default decision first normalizes request paths, denies traversal
  outside the virtual session root, denies write operations for read-only
  sessions, and derives rooted final/temporary paths including atomic-publish
  defaults when configured
- returning `NOTHING` keeps the default transfer decision
- returning a typed decision may:
  - allow the transfer and override `transfer_info`
  - deny the transfer with `allowed: False` and an explanatory `message`
- when the final decision is allowed, the resulting `transfer_info` is applied
  to the live `SftpSession`
- when the final decision is denied, the live `SftpSession` transfer state is
  cleared

## Atomic Exchange Helpers

High-level exchange handlers should sit above the raw backend contract so users
can implement common integration scenarios with minimal code.

Submission-handler direction:

```qore
hash<SftpOperationResult> submit(hash<SftpSubmissionRequest> req)
```

Retrieval-handler direction:

```qore
hash<SftpListResult> listAvailable(hash<SftpPathRequest> req)
hash<SftpOpenResult> retrieve(hash<SftpOpenRequest> req)
hash<SftpOperationResult> completeRetrieve(hash<SftpOperationRequest> req)
```

Contract:

- submission flows should support staging, validation, and atomic commit
- retrieval flows should support claim/archive/delete-on-success behavior
- retrieval completion should use the explicit `completion_mode` field on
  `SftpOperationRequest` rather than encoding the mode in loose metadata
- these helpers may be implemented on top of a virtual backend with no real
  filesystem paths
- this is the preferred integration API for Qorus-style atomic file exchanges
- the current implementation exposes these helpers directly on `SftpSession`
- `submit()` may be called with either inline binary `data` or a local
  `source_path`; when `source_path` is used, the module reads the file and
  passes the payload to backend `submit()`
- `SftpSession` also exposes convenience wrappers for common flows:
  `submitData()`, `submitLocalFile()`, `retrieveData()`, and
  `retrieveToLocalFile()`
- retrieval finalization also has explicit helpers:
  `completeRetrieveMode()`, `completeRetrieveDelete()`,
  `completeRetrieveClaim()`, and `completeRetrieveArchive()`
- when atomic-exchange helper results include `transfer_info`, that transfer
  state is applied to the live `SftpSession`

## Auditing

Signature:

```qore
nothing auditCallback(hash<SshAuditEvent> event)
```

Contract:

- events should be fire-and-forget from the server point of view
- the callback should be written to avoid indefinite blocking
- a callback failure should not corrupt session state
