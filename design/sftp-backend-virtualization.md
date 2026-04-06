# module-ssh SFTP Backend Virtualization

/*  sftp-backend-virtualization.md Copyright 2026 Qore Technologies, s.r.o.

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

This document defines the intended backend-driven SFTP model for `module-ssh`.
The key requirement is that a server must be able to expose a fully virtualized
filesystem through SFTP without requiring a real local filesystem behind the
visible path namespace.

## Design Requirements

- protocol handling stays in the binary module
- path and file semantics are delegated through a backend contract
- a backend may be fully virtual and not use local filesystem paths at all
- atomic file submission and retrieval must be easy to implement
- local filesystem access remains available as one built-in backend mode
- auditing, cancellation, and sandboxing remain enforced by the module where
  applicable

## Backend Types

### Local Filesystem Backend

Use case:

- standard rooted SFTP server on local storage

Behavior:

- maps virtual paths to real local paths
- applies filesystem sandbox checks
- provides built-in stat, list, read, write, mkdir, remove, rename behavior

### Virtual Filesystem Backend

Use case:

- exposing files or directories that exist only logically in Qore
- object stores, generated content, interface queues, database-backed entries

Behavior:

- no direct local filesystem mapping required
- all path metadata, listing, reads, and writes come from backend methods
- backend controls visible paths, metadata, and content lifecycle

### Atomic Exchange Backend

Use case:

- inbound file submissions
- outbound retrieval queues
- Qorus-style interface exchanges

Behavior:

- optimized around staged submit/retrieve flows
- may present a filesystem-like facade while internally using queues or
  transactional objects
- supports claim, archive, delete-on-success, and atomic commit semantics

## Backend Contract Direction

The preferred backend contract is object-based and easy to implement from Qore.

### Path and Metadata

```qore
hash<SftpPathInfo> stat(hash<SftpPathRequest> req)
hash<SftpListResult> list(hash<SftpPathRequest> req)
```

### Read and Write Opening

```qore
hash<SftpOpenResult> openRead(hash<SftpOpenRequest> req)
hash<SftpOpenResult> openWrite(hash<SftpOpenRequest> req)
```

### Streamed Read and Write

```qore
hash<SftpReadResult> read(hash<SftpReadRequest> req)
hash<SftpOperationResult> write(hash<SftpWriteRequest> req)
hash<SftpOperationResult> closeRead(hash<SftpCloseRequest> req)
hash<SftpOperationResult> closeWrite(hash<SftpCloseRequest> req)
```

### Mutations

```qore
hash<SftpOperationResult> removePath(hash<SftpPathRequest> req)
hash<SftpOperationResult> rename(hash<SftpRenameRequest> req)
hash<SftpOperationResult> mkdir(hash<SftpPathRequest> req)
hash<SftpOperationResult> rmdir(hash<SftpPathRequest> req)
```

## Streaming Model Direction

The low-level SFTP protocol uses handles and chunked reads/writes. That should
remain internal to the binary module.

The user-facing backend contract should instead return opaque backend handles or
stream descriptors in `SftpOpenResult`. The module will maintain the mapping
between SFTP protocol handles and backend state.

Current implemented step:

- `openRead()` may still return inline `data` for the simple buffered case
- `openRead()` may also return an opaque `backend_handle` for streamed virtual
  retrieval
- when `backend_handle` is present, the module routes chunk reads through
  backend `read(hash<SftpReadRequest>)` and final read-handle cleanup through
  backend `closeRead(hash<SftpCloseRequest>)`
- `openWrite()` may still use the simple buffered submission contract where the
  module accumulates uploaded data and passes it to `closeWrite()`
- `openWrite()` may also return an opaque `backend_handle` for streamed virtual
  submission
- when the streamed write contract is used, the module routes each write chunk
  through backend `write(hash<SftpWriteRequest>)` and still invokes
  `closeWrite(hash<SftpCloseRequest>)` for finalization
- live mutation requests are now backend-driven as well:
  - `SSH_FXP_REMOVE` -> `removePath()`
  - `SSH_FXP_RENAME` -> `rename()`
  - `SSH_FXP_MKDIR` -> `mkdir()`
  - `SSH_FXP_RMDIR` -> `rmdir()`
- the public Qore backend contract uses `removePath()` instead of `remove()`
  because `remove` is not a practical plain method name for Qore class
  backends

This keeps the API simple:

- users implement object methods
- the module handles SFTP packet state and protocol handle bookkeeping

The preferred user-facing backend contract is now strongly typed. The older
`hash<auto>` forms remain available only for intentionally dynamic backends,
but `SftpSession` now dispatches typed request hashes for both metadata/path
verbs and streamed-handle verbs, so typed-only backends work cleanly at the
live protocol boundary.

Implemented convenience layer:

- `SftpServerDataProvider::VirtualSftpFilesystem` is now the first easy-to-use
  backend helper on top of this contract
- it provides in-memory directory and file management with high-level methods
  such as `addDirectory()`, `addFile()`, `addTextFile()`, `getFileData()`,
  and `getFileText()`
- it also implements the atomic exchange helpers directly so uploads and
  retrieval workflows can be exercised without a real filesystem backend
- `SftpServerDataProvider::VirtualSftpExchange` builds on it with explicit
  inbound/outbound/archive/claim directories and direct exchange methods such
  as `addOutboundData()`, `listOutbound()`, `claimOutbound()`, and
  `archiveOutbound()`
- `SftpServerDataProvider::VirtualSftpExchangeRecordStore` builds on the
  exchange helper with record-oriented methods so higher-level integration
  code can work with queue entries and payload hashes instead of managing
  virtual filenames directly

## Atomic Exchange API Direction

Many integration scenarios do not need a generic filesystem API. For these
cases, the module should provide higher-level helpers layered on top of the
backend contract.

### Submission

```qore
hash<SftpOperationResult> submit(hash<SftpSubmissionRequest> req)
```

Expected behavior:

- stage uploaded content
- validate name, metadata, and optional checksum
- commit atomically
- return final object metadata
- current implementation exposes this directly through
  `SftpSession::submit(hash<SftpSubmissionRequest>)`
- `submit()` accepts either inline binary `data` or a local `source_path`
  whose contents are read by the module before backend dispatch
- convenience wrappers also exist through
  `SftpSession::submitData()` and `SftpSession::submitLocalFile()`

### Retrieval

```qore
hash<SftpListResult> listAvailable(hash<SftpPathRequest> req)
hash<SftpOpenResult> retrieve(hash<SftpOpenRequest> req)
hash<SftpOperationResult> completeRetrieve(hash<SftpOperationRequest> req)
```

Expected behavior:

- list retrievable objects
- stream the selected object
- finalize retrieval with claim/archive/delete semantics
- use the explicit typed `completion_mode` field on `SftpOperationRequest`
  for completion semantics
- current implementation exposes these directly through
  `SftpSession::listAvailable()`, `SftpSession::retrieve()`, and
  `SftpSession::completeRetrieve()`
- convenience wrappers also exist through `SftpSession::retrieveData()` and
  `SftpSession::retrieveToLocalFile()`
- retrieval completion convenience wrappers also exist through
  `SftpSession::completeRetrieveMode()`, `completeRetrieveDelete()`,
  `completeRetrieveClaim()`, and `completeRetrieveArchive()`

## Responsibilities Split

### Binary Module

- decode and encode SFTP protocol packets
- manage channel lifecycle and protocol handles
- enforce cancellation
- emit audit events
- apply sandboxing to built-in local-filesystem adapters
- map backend outcomes to SFTP status and reply packets

### Backend Implementation

- define visible path namespace
- provide metadata and listing
- provide read/write object semantics
- enforce business-level access rules
- implement virtualized or exchange-specific object lifecycle

## Immediate Implementation Consequence

Current direct filesystem helpers such as `publishLocalFile()` and
`retrieveLocalFile()` should remain available as transitional local-filesystem
helpers, but future SFTP protocol handling should target the backend contract
first rather than expanding direct OS-path logic.
