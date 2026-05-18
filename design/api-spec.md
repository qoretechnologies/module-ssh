# module-ssh API Specification

## Scope

The `ssh` module is a new Qore binary module based on `libssh`. It is intended
to complement the client-focused `ssh2` module with server-side SSH and SFTP
support focused on controlled command handling, file-based integration, and
auditable operation.

GitHub is the master repository. GitLab exists only as a mirror for CI.

Complex runtime objects support `LoggerInterface`-compatible loggers for
operational messages, warnings, errors, and detailed tracing. Accepted child
objects inherit the logger from their parent by default. The higher-level qlib
helpers now type these logger surfaces directly as `LoggerInterface`; the
binary-module reflection surface still exposes `object`, but the object must
implement the `LoggerInterface` contract.

The focused backend-virtualization design note is in
`design/sftp-backend-virtualization.md`.

## Naming Convention

All public class and namespace names use CamelCase consistently.

Binary module namespace:

- `Qore::Ssh`

Planned public classes:

- `SshServer`
- `SshSession`
- `SshCommandSession`
- `SshAuthContext`
- `SshAuditContext`
- `SshAuditEvent`
- `SftpServer`
- `SftpSession`

Planned user modules:

- `SshServerConnections`
- `SftpServerDataProvider`

## Design Goals

- server-side SSH and SFTP support using `libssh`
- controlled command processing instead of unrestricted shell exposure
- local configuration with support for multiple listeners and concurrent sessions
- pluggable application authentication
- pluggable sandboxing and instrumentation after authentication
- secure and auditable actions for both command and file operations
- generic integration support through command and file APIs

## Architecture Overview

### Binary Module

The binary module owns transport, session, channel, authentication, cancellation,
and audit plumbing.

The module must:

- expose QPP-backed public classes
- register typed hashes for all public metadata
- integrate sandbox checks for network and filesystem operations
- integrate cooperative cancellation for all blocking operations
- remain exception-safe in all teardown paths

### User Modules

The user modules provide Qore-level integration and configuration helpers.

- `SshServerConnections`
  - local configuration schema
  - listener and service lifecycle management
  - connection-provider style abstractions where appropriate
- `SftpServerDataProvider`
  - generic file-oriented APIs for atomic submission and retrieval
  - `VirtualSftpFilesystem` helper for in-memory virtual SFTP namespaces
  - `VirtualSftpExchange` helper for inbound/outbound/archive/claim workflows
  - `VirtualSftpExchangeRecordStore` helper for record-oriented queue APIs
  - generic DataProvider-facing integration actions

### SFTP Backend Model

Server-side SFTP must support both real filesystem access and fully virtualized
filesystems where no direct OS-backed path exists behind the SFTP namespace.

The design therefore treats filesystem access as a backend contract rather than
as intrinsic module behavior.

Required backend modes:

- `LocalFilesystem`
  - backed by real OS paths
  - supports sandbox-checked path access
- `VirtualFilesystem`
  - all path, metadata, listing, read, and write behavior is delegated to Qore
    backend callbacks or objects
  - no local filesystem access is required
- `AtomicExchange`
  - optimized for controlled file submission and retrieval workflows rather
    than generic filesystem semantics
  - intended for controlled interface-style exchanges

The current direct filesystem helpers in `SftpSession` are transitional. The
stable public direction is backend-driven, with local-filesystem behavior moved
behind the same contract as virtual backends.

The backend contract is now strongly typed in both directions:

- helper-facing convenience APIs use typed `SftpServerDataProvider::*`
  hashdecls
- live backend verbs use typed `Qore::Ssh::*` hashdecls
- `hash<auto>` backend signatures remain available only for intentionally
  dynamic backends

Implemented high-level helper:

- `SftpServerDataProvider::VirtualSftpFilesystem`
  - easy-to-use in-memory backend implementing the current SFTP backend
    contract
  - supports `addDirectory()`, `addFile()`, `addTextFile()`, `getFileData()`,
    and `getFileText()` for simple virtual filesystem population
  - exposes typed constructor options through `VirtualSftpFilesystemOptions`
  - exposes typed helper requests through `VirtualSftpPathRequest`,
    `VirtualSftpSubmissionRequest`, and `VirtualSftpCompletionRequest`
  - exposes typed helper results for inspection through
    `VirtualSftpFileSnapshot`, `VirtualSftpSnapshot`, and
    `VirtualSftpEntryInfo`
  - projects built-in helper-managed state through
    `VirtualSftpBuiltinState` on snapshot/stat/listing results so callers do
    not need to inspect loose metadata for stable flags like archived/claimed
    and exchange-role markers
  - supports atomic exchange methods through the same backend object:
    `submit()`, `listAvailable()`, `retrieve()`, and `completeRetrieve()`
  - can be attached directly to `Qore::Ssh::SftpSession::setBackend()`

- `SftpServerDataProvider::VirtualSftpExchange`
  - higher-level exchange wrapper built on `VirtualSftpFilesystem`
  - manages explicit `inbound`, `outbound`, `archive`, and `claim`
    directories
  - exposes typed constructor options through `VirtualSftpExchangeOptions`
  - supports a typed `VirtualSftpInboundPolicy` through
    `VirtualSftpExchangeOptions.inbound_policy` for filename, size, and
    content-aware acceptance controls on inbound uploads, including
    duplicate-basename, duplicate-size, duplicate-content, file-count, and
    total-byte rejection
  - supports optional custom content validation through
    `VirtualSftpInboundPolicy.validation_callback`
  - also supports principal-aware acceptance and routing through
    `allow_principals`, `deny_principals`, `principal_policies`, and
    `principal_routes`
  - supports typed retention policies through
    `inbound_retention_policy`, `archive_retention_policy`, and
    `claim_retention_policy`
  - stamps `retention_queue`, `retained_at`, and `expires_at` metadata when
    those policies are configured, and exposes deterministic cleanup through
    `cleanupExpired()`
  - supports the same typed helper request hashes as `VirtualSftpFilesystem`
  - provides direct convenience methods such as `addOutboundData()`,
    `addInboundData()`, `listOutbound()`, `claimOutbound()`,
    `archiveOutbound()`, and `deleteOutbound()`
  - returns typed `VirtualSftpEntryInfo` listings and typed
    `VirtualSftpRecordInfo` completion results for claim/archive/delete
  - for delete-style completion results, `VirtualSftpRecordInfo.path` may be
    `NOTHING`
  - still implements the backend contract directly so it can be attached to
    `Qore::Ssh::SftpSession::setBackend()`
  - recommended UX is to use typed helper requests such as
    `VirtualSftpPathRequest` and `VirtualSftpCompletionRequest` instead of
    loose request maps
  - inbound acceptance policy is enforced consistently for helper submissions,
    `DataProvider` `submit-inbound` requests, and real SFTP uploads against
    the exchange backend
  - also exposes strongly typed backend verb overloads using
    `Qore::Ssh::SftpPathRequest`, `Qore::Ssh::SftpOpenRequest`,
    `Qore::Ssh::SftpRenameRequest`, `Qore::Ssh::SftpReadRequest`,
    `Qore::Ssh::SftpWriteRequest`, and `Qore::Ssh::SftpCloseRequest`

- `SftpServerDataProvider::VirtualSftpExchangeRecordStore`
  - record-oriented wrapper built on `VirtualSftpExchange`
  - exposes queue-style methods such as `submitInboundRecord()`,
    `addOutboundRecord()`, `listOutboundRecords()`, `retrieveOutboundRecord()`,
    `claimOutboundRecord()`, `archiveOutboundRecord()`, and
    `deleteOutboundRecord()`
  - supports typed record request hashes:
    `VirtualSftpRecordRequest`,
    `VirtualSftpRecordSubmissionRequest`, and
    `VirtualSftpRecordCompletionRequest`
  - returns typed `VirtualSftpRecordInfo` hashes instead of loose record maps
  - suitable for generic integration code that should work with typed records
    instead of raw virtual filenames
  - recommended UX is to use the typed record request hashes for submission,
    retrieval, claim, archive, and delete flows

### Typed Backend Contract

The preferred backend contract now uses explicit typed hashes for both normal
filesystem verbs and streamed handle operations.

Typed metadata and path verbs:

- `hash<SftpPathInfo> stat(hash<SftpPathRequest> req)`
- `hash<SftpListResult> list(hash<SftpPathRequest> req)`
- `hash<SftpOpenResult> openRead(hash<SftpOpenRequest> req)`
- `hash<SftpOpenResult> openWrite(hash<SftpOpenRequest> req)`
- `hash<SftpOperationResult> removePath(hash<SftpPathRequest> req)`
- `hash<SftpOperationResult> rename(hash<SftpRenameRequest> req)`
- `hash<SftpOperationResult> mkdir(hash<SftpPathRequest> req)`
- `hash<SftpOperationResult> rmdir(hash<SftpPathRequest> req)`

Typed streamed-handle verbs:

- `hash<SftpReadResult> read(hash<SftpReadRequest> req)`
- `hash<SftpOperationResult> write(hash<SftpWriteRequest> req)`
- `hash<SftpOperationResult> closeRead(hash<SftpCloseRequest> req)`
- `hash<SftpOperationResult> closeWrite(hash<SftpCloseRequest> req)`

Typed atomic-exchange verbs:

- `hash<SftpOperationResult> submit(hash<SftpSubmissionRequest> req)`
- `hash<SftpListResult> listAvailable(hash<SftpPathRequest> req)`
- `hash<SftpOpenResult> retrieve(hash<SftpOpenRequest> req)`
- `hash<SftpOperationResult> completeRetrieve(hash<SftpOperationRequest> req)`

`SftpSession` now dispatches these typed backend request hashes directly.
Typed-only backends are therefore supported end to end. Lower-level dynamic
backend maps remain available for intentionally dynamic backends.

The `SftpSession` convenience layer is also being kept aligned with the typed
contract. In addition to the primitive convenience signatures, typed overloads
are now supported for common helper flows such as:

- `submitData(hash<SftpSubmissionRequest>)`
- `submitLocalFile(hash<SftpSubmissionRequest>)`
- `retrieveData(hash<SftpOpenRequest>)`
- `completeRetrieveDelete(hash<SftpOperationRequest>)`

On the provider side, `SftpServerDataProvider` surfaces the same generic
inbound acceptance policy through constructor/action metadata for the
`submit-inbound` flow and the config-driven `inbound-file-accepted` event
provider. That gives one typed configuration surface for local managed SFTP
servers, provider actions, and live uploads. The inbound policy is applied to
direct payload submissions, `source_path` submissions, and live SFTP uploads.
Inbound events now omit the binary payload by default; payload fanout is an
explicit opt-in via `inbound_event_payload_mode=inline`.
Typed inbound events also carry stable live-session context fields when
available: `session_id`, `server_name`, `listener_name`, and `principal`.
- `completeRetrieveClaim(hash<SftpOperationRequest>)`
- `completeRetrieveArchive(hash<SftpOperationRequest>)`
- `retrieveToLocalFile(hash<SftpOpenRequest>, string, *string, bool)`

For retrieval-completion requests, `SftpOperationRequest` carries the explicit
typed field `completion_mode`.

## Public API Direction

### SshServer

Responsibilities:

- own one or more configured listeners
- load host keys and listener settings
- start, stop, and report status
- dispatch accepted sessions into authentication and service handlers

Initial method direction:

- `constructor(hash<SshServerConfig> config)`
- `nothing start()`
- `nothing stop()`
- `*SshSession acceptSession(int timeout_ms = 0)`
- `*hash<SshSessionInfo> acceptSessionInfo(int timeout_ms = 0)`
- `*hash<SshAuthDecision> authenticateSession(SshSession session, int timeout_ms = 0)`
- `*hash<SshCommandResult> dispatchCommandSession(SshSession session, int timeout_ms = 0)`
- `*SftpSession dispatchSftpSession(SshSession session, int timeout_ms = 0)`
- `nothing setLogger(object logger)`
- `object getLogger()`
- `bool running()`
- `hash<SshServerStatus> getStatus()`

### SshSession

Responsibilities:

- represent an accepted SSH connection
- expose peer info, negotiated auth method, and session capabilities
- own per-session lifecycle and cancellation state
- remain separate from transient accept-only metadata returned by `SshServer::acceptSessionInfo()`
- surface server-side authentication requests in a controlled, typed form

Initial method direction:

- `hash<SshSessionInfo> getInfo()`
- `*hash<SshAuthContextInfo> getAuthContextInfo()`
- `*SshAuthContext waitAuthContext(int timeout_ms = 0)`
- `*SshCommandSession waitCommandSession(int timeout_ms = 0)`
- `*SftpSession waitSftpSession(int timeout_ms = 0)`
- `nothing applyAuthDecision(hash<SshAuthContextInfo>, hash<SshAuthDecision>)`
- `nothing setLogger(object logger)`
- `object getLogger()`
- `nothing disconnect()`

Live accepted sessions inherit the logger from `SshServer`.

### SshAuthContext

Responsibilities:

- represent a pending server-side authentication request
- expose typed request metadata for auth callbacks and policy decisions
- provide logger-aware accept and reject paths

Initial method direction:

- `hash<SshAuthContextInfo> getInfo()`
- `nothing accept(hash<SshAuthDecision> decision)`
- `nothing reject(hash<SshAuthDecision> decision)`
- `nothing setLogger(object logger)`
- `object getLogger()`

Pending auth contexts inherit the logger from `SshSession`.

### SshCommandSession

Responsibilities:

- represent a controlled exec request
- provide structured stdin/stdout/stderr access
- capture exit status and audit metadata

Initial method direction:

- `string getCommand()`
- `*binary read(int size, timeout timeout = -1)`
- `nothing write(binary data, timeout timeout = -1)`
- `nothing writeError(binary data, timeout timeout = -1)`
- `nothing closeInput()`
- `nothing setExitStatus(int status)`
- `nothing setLogger(object logger)`
- `object getLogger()`
- `nothing applyResult(hash<SshCommandResult>)`

Command sessions inherit the logger from `SshSession`.

### SftpServer and SftpSession

Responsibilities:

- expose server-side SFTP handling with backend-driven file operations
- support staged writes and atomic publish patterns
- support fully virtualized filesystem behavior with no real backing paths
- enforce path restrictions and audit all operations

Initial method direction:

- `SftpServer::constructor(hash<SftpServerConfig> config)`
- `hash<SftpSessionInfo> getInfo()`
- `*hash<SftpProtocolMessage> waitProtocolMessage(int timeout_ms = 0)`
- `*hash<SftpProtocolMessage> processNextRequest(int timeout_ms = 0)`
- `*hash<SftpTransferInfo> getTransferInfo()`
- `nothing applyTransferInfo(hash<SftpTransferInfo> transfer_info)`
- `nothing clearTransferInfo()`
- `nothing sendVersion(int version = 3)`
- `nothing sendStatus(int request_id, int status_code, string message = "", string language = "")`
- `nothing setBackend(object backend)`
- `object getBackend()`
- `hash<SftpOperationResult> submit(hash<SftpSubmissionRequest> req)`
- `hash<SftpOperationResult> submitData(string path, binary data, *hash<auto> metadata = NOTHING, *string checksum = NOTHING)`
- `hash<SftpOperationResult> submitLocalFile(string path, string source_path, bool move = False, bool create_parents = True, *hash<auto> metadata = NOTHING, *string checksum = NOTHING)`
- `hash<SftpListResult> listAvailable(hash<SftpPathRequest> req)`
- `hash<SftpOpenResult> retrieve(hash<SftpOpenRequest> req)`
- `binary retrieveData(string path, *hash<auto> metadata = NOTHING, int offset = 0, int length = -1)`
- `hash<SftpOperationResult> completeRetrieve(hash<SftpOperationRequest> req)`
- `hash<SftpOperationResult> completeRetrieveMode(string path, string completion_mode, *string target_path = NOTHING, *hash<auto> metadata = NOTHING)`
- `hash<SftpOperationResult> completeRetrieveDelete(string path, *string target_path = NOTHING, *hash<auto> metadata = NOTHING)`
- `hash<SftpOperationResult> completeRetrieveClaim(string path, *string target_path = NOTHING, *hash<auto> metadata = NOTHING)`
- `hash<SftpOperationResult> completeRetrieveArchive(string path, *string target_path = NOTHING, *hash<auto> metadata = NOTHING)`
- `hash<SftpOperationResult> retrieveToLocalFile(string path, string target_path, *string completion_mode = NOTHING, *hash<auto> metadata = NOTHING, bool create_parents = True)`
- `hash<SftpTransferInfo> publishLocalFile(string source_path, bool move = False, bool create_parents = True)`
- `hash<SftpTransferInfo> retrieveLocalFile(string target_path, bool move = False, bool create_parents = True)`
- `nothing setLogger(object logger)`
- `object getLogger()`
- `bool connected()`
- `nothing close()`

Potential future backend methods:

- `nothing setBackend(object backend)`
- `object getBackend()`
- `hash<SftpBackendResult> processRequest(hash<SftpProtocolMessage> msg)`

The intended shape is that low-level protocol decoding remains in the binary
module, while path operations, listing, stat, read, write, and atomic-exchange
semantics are delegated through a stable backend contract.

### Planned Virtualization API

The module should expose an easy-to-use backend API so users do not have to
implement raw SFTP protocol details.

Planned backend object:

- `SftpBackend`
  - `hash<SftpPathInfo> stat(hash<SftpPathRequest> req)`
  - `hash<SftpListResult> list(hash<SftpPathRequest> req)`
  - `hash<SftpOpenResult> openRead(hash<SftpOpenRequest> req)`
  - `hash<SftpOpenResult> openWrite(hash<SftpOpenRequest> req)`
  - `hash<SftpOperationResult> removePath(hash<SftpPathRequest> req)`
  - `hash<SftpOperationResult> rename(hash<SftpRenameRequest> req)`
  - `hash<SftpOperationResult> mkdir(hash<SftpPathRequest> req)`
  - `hash<SftpOperationResult> rmdir(hash<SftpPathRequest> req)`

These methods must be implementable by either:

- a local-filesystem adapter provided by the module
- a fully virtual Qore object with no direct filesystem access
- a higher-level exchange adapter that presents files/messages as SFTP objects

### Planned Atomic Exchange API

For integration scenarios, a simpler API is required than a generic
filesystem-like backend.

Planned high-level helpers:

- `SftpSubmissionHandler`
  - stage upload content
  - validate metadata and content
  - commit atomically
  - return auditable submission metadata
- `SftpRetrievalHandler`
  - enumerate retrievable objects
  - stream a selected object
  - support claim/archive/delete-on-success semantics
  - return auditable retrieval metadata

This layer is the preferred API for interface-style scenarios where users want
to submit or retrieve files atomically without implementing a full filesystem
abstraction.

## Typed Hashes

The module should define typed hashes early and keep them stable.

Planned declarations:

- `SshServerConfig`
- `SshListenerConfig`
- `SshServerStatus`
- `SshSessionInfo`
- `SshAuthInfo`
- `SshAuthDecision`
- `SshCommandRequest`
- `SshCommandResult`
- `SshAuditEvent`
- `SftpServerConfig`
- `SftpSessionInfo`
- `SftpProtocolMessage`
- `SftpTransferRequest`
- `SftpTransferInfo`
- `SftpTransferDecision`
- `SftpPathRequest`
- `SftpPathInfo`
- `SftpListResult`
- `SftpOpenRequest`
- `SftpOpenResult`
- `SftpOperationResult`
- `SftpRenameRequest`
- `SftpSubmissionRequest`
- `SftpOperationRequest`
- `SftpBackendResult`

#### SftpProtocolMessage

- `type`: `int`
- `name`: `string`
- `request_id`: `*int`
- `version`: `*int`
- `payload`: `*binary`
- `payload_size`: `int`

Current protocol support includes:

- decoding the initial client `SSH_FXP_INIT` packet into `SftpProtocolMessage`
- decoding subsequent request packet type and request id fields
- sending `SSH_FXP_VERSION` replies from `SftpSession::sendVersion()`
- sending `SSH_FXP_STATUS` replies from `SftpSession::sendStatus()`
- handling `SSH_FXP_REALPATH` in `SftpSession::processNextRequest()` using the
  same virtual path normalization rules as transfer planning
- handling rooted `SSH_FXP_STAT` / `SSH_FXP_LSTAT` lookups in
  `SftpSession::processNextRequest()` with `SSH_FXP_ATTRS` replies
- storing validated backend objects directly on `SftpSession` with
  `setBackend()` / `getBackend()`
- allowing `sftp_factory_callback` to attach a backend object to a live
  accepted `SftpSession`
- routing `SSH_FXP_REALPATH` and `SSH_FXP_STAT` / `SSH_FXP_LSTAT` through the
  attached backend when present, with the current rooted local-filesystem logic
  retained as the fallback
- routing backend-driven `SSH_FXP_OPENDIR`, `SSH_FXP_READDIR`, and
  `SSH_FXP_CLOSE` through binary-module-managed directory handles when a backend
  is attached
- routing backend-driven `SSH_FXP_OPEN`, `SSH_FXP_FSTAT`, `SSH_FXP_READ`, and
  `SSH_FXP_CLOSE` through binary-module-managed file handles when a backend
  implements `openRead()`
- supporting a first easy-to-use virtual retrieval contract where
  `openRead()` returns metadata plus an in-memory `data` payload and the module
  handles chunked SFTP reads internally
- supporting streamed virtual retrieval where `openRead()` returns an opaque
  `backend_handle` and the module routes `SSH_FXP_READ` through backend
  `read()` plus final `SSH_FXP_CLOSE` through backend `closeRead()`
- routing backend-driven `SSH_FXP_OPEN`, `SSH_FXP_WRITE`, and `SSH_FXP_CLOSE`
  through binary-module-managed file handles when a backend implements
  `openWrite()` and `closeWrite()`
- supporting a first easy-to-use virtual submission contract where the module
  buffers uploaded `WRITE` payloads in memory and delivers the complete
  submission to backend `closeWrite()` as binary data
- supporting streamed virtual submission where `openWrite()` returns an opaque
  `backend_handle`, the module routes `SSH_FXP_WRITE` chunks through backend
  `write()`, and still invokes backend `closeWrite()` for finalization
- routing backend-driven `SSH_FXP_REMOVE`, `SSH_FXP_RENAME`, `SSH_FXP_MKDIR`,
  and `SSH_FXP_RMDIR` through backend mutation methods when a backend is
  attached
- using `removePath()` rather than `remove()` in the public Qore backend
  contract because `remove` is not a practical plain method name for Qore class
  implementations
- adding direct atomic-exchange helper methods on `SftpSession`:
  - `submit(hash<SftpSubmissionRequest>)`
  - `submitData(string, binary, *hash<auto>, *string)`
  - `submitLocalFile(string, string, bool, bool, *hash<auto>, *string)`
  - `listAvailable(hash<SftpPathRequest>)`
  - `retrieve(hash<SftpOpenRequest>)`
  - `retrieveData(string, *hash<auto>, int, int)`
  - `completeRetrieve(hash<SftpOperationRequest>)`
  - `completeRetrieveMode(string, string, *string, *hash<auto>)`
  - `completeRetrieveDelete(string, *string, *hash<auto>)`
  - `completeRetrieveClaim(string, *string, *hash<auto>)`
  - `completeRetrieveArchive(string, *string, *hash<auto>)`
  - `retrieveToLocalFile(string, string, *string, *hash<auto>, bool)`
- allowing `submit()` to take either inline binary data or a local
  `source_path`, so staged local files can be handed to a virtual backend
  without exposing a real filesystem through SFTP
- adding convenience wrappers so callers can implement common submit/retrieve
  exchange flows without manually building typed request hashes
- exposing typed backend verb overloads on the virtual filesystem and exchange
  helpers using the `Qore::Ssh` SFTP request/result hashes
- keeping the remaining `hash<auto>` helper path only for dynamic backend
  integration behind those overloads and behind `SftpSession`
- making the typed request overloads return typed helper result hashes for the
  normal public UX
- adding explicit retrieval-finalization helpers for common completion modes
  rather than forcing callers to set backend metadata keys directly

The long-term direction for SFTP request handling is:

- the binary module decodes protocol requests and encodes replies
- backend contracts provide the virtualized path/file semantics
- atomic file exchange flows are exposed through a higher-level API layered on
  top of the backend contract

Current `SshAuthContextInfo` population includes:

- `password` for password authentication attempts
- `public_key` as the decoded SSH public-key blob for public-key auth attempts
- `public_key_type` such as `ssh-ed25519`
- `metadata.public_key_state` for probe vs signed public-key attempts
- live `sftp` subsystem requests can now be surfaced as `SftpSession` objects
  through `SshSession::waitSftpSession()`
- `SftpTransferRequest`
- `SftpTransferInfo`
- `SftpAtomicPublishPolicy`

### Typed Hash Direction

The following keys should be treated as the initial target schema for the
first public version. Optional keys are marked explicitly with `*`.

#### SshServerConfig

- `name`: `string`
- `listeners`: `list<hash<SshListenerConfig>>`
- `auth_provider`: `*object`
- `auth_callback`: `code<hash<SshAuthDecision>(hash<SshAuthContext>)>`
- `command_callback`: `code<hash<SshCommandResult>(hash<SshCommandRequest>)>`
- `logger`: `*object` (must implement `LoggerInterface`)
- `audit_callback`: `*code<nothing(hash<SshAuditEvent>)>`
- `sftp_factory_callback`: `*code<hash<auto>(hash<SftpSessionInfo>)>`
- `default_command_timeout`: `*timeout`
- `log_authenticated_sessions`: `*bool`
- `log_file_transfers`: `*bool`

#### SshListenerConfig

- `name`: `string`
- `bind_address`: `string`
- `port`: `int`
- `host_keys`: `list<string>`
- `limits`: `*hash<SshServerConnectionLimits>`
- `services`: `*hash<SshServerConnectionServices>`
- `banner`: `*string`
- `server_options`: `*hash<auto>`

Listener capability keys are coarse pre-dispatch gates:

- `limits.max_sessions` caps concurrently accepted sessions per listener when set

- `services.enabled_auth_methods` controls which SSH authentication methods are
  exposed to clients on that listener
- `services.allow_command_service` controls whether exec requests and non-SFTP
  subsystem requests are admitted at all on that listener
- `services.allow_sftp_service` controls whether the `sftp` subsystem is
  admitted at all on that listener
  to clients on that listener; disabled methods are rejected before auth
  callbacks are surfaced

These listener-level gates are enforced before per-session `command_policy`.

#### SshServerStatus

- `name`: `string`
- `running`: `bool`
- `listener_count`: `int`
- `active_session_count`: `int`
- `started`: `*date`
- `listeners`: `list<hash<SshListenerStatus>>`

#### SshListenerStatus

- `name`: `string`
- `bind_address`: `string`
- `port`: `int`
- `bound_port`: `*int`
- `running`: `bool`
- `active_session_count`: `int`
- `last_error`: `*hash<ExceptionInfo>`

#### SshSessionInfo

- `session_id`: `string`
- `server_name`: `string`
- `listener_name`: `string`
- `remote_address`: `string`
- `remote_port`: `int`
- `local_address`: `string`
- `local_port`: `int`
- `username`: `*string`
- `authenticated`: `bool`
- `auth_method`: `*string`
- `principal`: `*string`
- `session_data`: `*hash<auto>`
- `command_policy`: `*hash<auto>`
- `sftp_policy`: `*hash<auto>`
- `started`: `date`
- `last_activity`: `date`

Current Phase 2 status:

- `SshServer::acceptSessionInfo()` is implemented and returns typed metadata
  after `ssh_bind_accept()` and `ssh_handle_key_exchange()`
- `SshServer::acceptSession()` is implemented and returns a live `SshSession`
  wrapper owning the accepted libssh session
- `SshSession::waitAuthContext()` is implemented for the first server-side
  auth handshake, auto-handling the `ssh-userauth` service request and
  returning typed auth-request metadata
- `SshServer::acceptSessionInfo()` disconnects and frees the accepted transport
  after the metadata snapshot is created
- authenticated session state, service negotiation, and server-managed session
  tracking are still later Phase 2/3 tasks

Current Phase 3 status:

- `SshServerConfig.auth_provider` is implemented as the primary pluggable auth hook
- `SshServerConfig.auth_callback` remains available as a low-level auth hook
- `SshServer::authenticateSession()` is implemented and applies typed auth decisions
- `SshServerConfig.command_callback` is implemented as a pluggable command hook
- `SshServerConfig.sftp_factory_callback` is implemented as a pluggable SFTP session hook
- `SshServer::dispatchCommandSession()` is implemented with deny-by-default exec authorization
- `SshServer::dispatchSftpSession()` is implemented to create live `SftpSession`
  objects and apply optional factory metadata overrides
- `SshServer::evaluateSftpTransferRequest()` is implemented to evaluate typed
  transfer requests against an optional path-policy callback and update the
  live `SftpSession` transfer state
- logger support is implemented for `SshServer`, `SshSession`,
  `SshAuthContext`, and `SshCommandSession`
- `SshAuthContext::applyDecision()` is implemented for data-driven auth handling
- `SshSession::applyAuthDecision()` records session auth state and policy metadata
- `SshSession::waitCommandSession()` is implemented for live command-request capture
- `SshCommandSession::applyResult()` is implemented for live command reply/output handling

Authentication is exposed in two public forms:

- low-level binary-module server configs may attach `auth_provider` objects
  implementing `authenticate(hash<SshAuthContextInfo>)`
- grouped connection-helper `auth` options synthesize a built-in
  `SshServerAuthProvider::VirtualSshAuthProvider`

The built-in provider supports config-driven and validator-driven handling for:

- `none`
- `password`
- `publickey`
- `interactive`
- `hostbased`
- `gssapi-mic`

#### SshAuthContext

- `session_id`: `string`
- `server_name`: `string`
- `listener_name`: `string`
- `remote_address`: `string`
- `remote_port`: `int`
- `username`: `string`
- `auth_method`: `string`
- `password`: `*string`
- `public_key`: `*binary`
- `public_key_type`: `*string`
- `service`: `*string`
- `metadata`: `*hash<auto>`

#### SshAuthDecision

- `accepted`: `bool`
- `partial`: `*bool`
- `principal`: `*string`
- `message`: `*string`
- `allowed_auth_methods`: `*list<string>`
- `command_policy`: `*hash<auto>`
  Supported initial keys:
  `mode` = `"command-only" | "subsystem-only" | "command-and-subsystem"`
  `allowed_subsystems` = `*list<string>`
  `allow_all_subsystems` = `*bool`
- `sftp_policy`: `*hash<auto>`
- `session_data`: `*hash<auto>`
- `audit_data`: `*hash<auto>`

### Logger Requirements

When a logger object is provided, it must be compatible with
`LoggerInterface` and support the methods used by the module:

- `detail(string message, ...)`
- `info(string message, ...)`
- `warn(string message, ...)`
- `error(string message, ...)`
- `debug(string message, ...)`

Logger failures must not break SSH processing. Logging is best-effort only.
Current level usage in the helper layers is:

- `detail` for auth attempts and low-level virtual filesystem churn
- `info` for accepted auth and command outcomes plus higher-level exchange events
- `warn` for rejected auth and command outcomes
- `error` for event-listener callback failures
- `debug` for configuration-oriented command-service traces

#### SshCommandRequest

- `session_id`: `string`
- `server_name`: `string`
- `listener_name`: `string`
- `username`: `*string`
- `principal`: `*string`
- `command`: `string`
- `arguments`: `*list<string>`
- `environment`: `*hash<auto>`
- `metadata`: `*hash<auto>`
  Supported initial keys:
  `request_type` = `"exec" | "subsystem"`
  `subsystem` = `*string`

#### SshCommandResult

- `accepted`: `bool`
- `exit_status`: `*int`
- `message`: `*string`
- `stdout`: `*binary`
- `stderr`: `*binary`
- `result_data`: `*hash<auto>`

#### SshAuditEvent

- `timestamp`: `date`
- `event_type`: `string`
- `server_name`: `string`
- `listener_name`: `*string`
- `session_id`: `*string`
- `principal`: `*string`
- `success`: `bool`
- `message`: `*string`
- `data`: `*hash<auto>`

#### SftpServerConfig

- `root_dir`: `*string`
- `read_only`: `*bool`
- `allow_overwrite`: `*bool`
- `allow_symlinks`: `*bool`
- `atomic_publish_policy`: `*hash<SftpAtomicPublishPolicy>`
- `path_policy_callback`: `*code<hash<auto>(hash<SftpTransferRequest>)>`
- `audit_data`: `*hash<auto>`

#### SftpSessionInfo

- `session_info`: `hash<SshSessionInfo>`
- `principal`: `string`
- `root_dir`: `*string`
- `read_only`: `bool`
- `session_data`: `*hash<auto>`

Supported initial `sftp_factory_callback` override keys:

- `root_dir`: `*string`
- `read_only`: `*bool`
- `session_data`: `*hash<auto>`
- `transfer_info`: `*hash<SftpTransferInfo>`

#### SftpTransferRequest

- `session_info`: `hash<SftpSessionInfo>`
- `operation`: `string`
- `path`: `string`
- `target_path`: `*string`
- `temporary_path`: `*string`
- `size`: `*int`
- `metadata`: `*hash<auto>`

#### SftpTransferInfo

- `operation`: `string`
- `path`: `string`
- `temporary_path`: `*string`
- `final_path`: `*string`
- `size`: `*int`
- `checksum`: `*string`
- `atomic_publish`: `bool`
- `completed`: `bool`

#### SftpTransferDecision

- `allowed`: `bool`
- `message`: `*string`
- `transfer_info`: `hash<SftpTransferInfo>`

Default decision behavior:

- request paths are normalized before callback evaluation
- traversal outside the virtual session root is denied
- write-style operations are denied for read-only sessions
- when `sftp_config.atomic_publish_policy.enabled` is true, upload/write-style
  requests default to atomic publish planning with a derived temporary path
  when one is not provided explicitly

#### SftpAtomicPublishPolicy

- `enabled`: `bool`
- `temporary_suffix`: `*string`
- `publish_by_rename`: `*bool`
- `overwrite`: `*bool`
- `fsync_before_publish`: `*bool`
- `preserve_partial_on_error`: `*bool`

## Callback Contracts

The first implementation should treat the following callback shapes as
authoritative unless explicitly revised.

### Authentication Callback

```qore
hash<SshAuthDecision> authCallback(hash<SshAuthContext> ctx)
```

Requirements:

- return `accepted: True` to authenticate the session
- return `accepted: False` to deny authentication without throwing
- throw only for internal errors and not for normal authentication failures

### Command Callback

```qore
hash<SshCommandResult> commandCallback(hash<SshCommandRequest> req)
```

Requirements:

- return `accepted: False` for denied commands
- return `accepted: True` with `exit_status` and output fields for handled commands
- support both simple request/response handling and streaming via `SshCommandSession`

### Audit Callback

```qore
nothing auditCallback(hash<SshAuditEvent> event)
```

Requirements:

- must never block indefinitely
- should not throw in normal operation
- should be invoked for both success and failure paths

### SFTP Path Policy Callback

```qore
hash<auto> pathPolicyCallback(hash<SftpTransferRequest> req)
```

Expected result keys:

- `allowed`: `bool`
- `resolved_path`: `*string`
- `message`: `*string`
- `audit_data`: `*hash<auto>`

## Error Taxonomy

The module should use a small, predictable set of exception families.

### Initialization and Configuration

- `SSH-MODULE-INIT-ERROR`
- `SSHSERVER-CONFIG-ERROR`
- `SSHLISTENER-CONFIG-ERROR`
- `SFTPSERVER-CONFIG-ERROR`

### Runtime Server and Session Errors

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

### Command Execution

- `SSHCOMMAND-ERROR`
- `SSHCOMMAND-INPUT-CLOSED`
- `SSHCOMMAND-TIMEOUT`

### SFTP

- `SFTPSERVER-ERROR`
- `SFTPSESSION-ERROR`
- `SFTP-PATH-DENIED`
- `SFTP-ATOMIC-PUBLISH-ERROR`
- `SFTP-TRANSFER-ERROR`

### Sandboxing and Cancellation

- propagate Qore sandbox exceptions directly where possible
- use `PROGRAM-INTERRUPTED` and `THREAD-CANCELLED` through `qore_check_cancel()`

## Phase 1 Deliverables

Phase 1 is complete when the repo contains:

- this API and schema specification
- callback contract documentation
- error taxonomy documentation
- placeholder tests that lock the design artifacts in place

## Security Model

The module is deny-by-default.

Requirements:

- no unrestricted shell access by default
- all command execution goes through an application dispatcher
- all filesystem access must honor policy and Qore sandbox checks
- listener creation must honor network sandbox checks
- auth, authorization, command, and file activity must be auditable

The implementation must follow:

- `qore/design/module-sandboxing-audit-guide.md`
- `qore/design/cooperative-cancellation.md`

## Integration Boundary

Application-specific behavior stays outside the generic module surface.

The command API must support:

- generic dispatch of admin and user actions
- structured command arguments
- audit-friendly result handling

The file API must support:

- staged upload to temporary location
- validation and checksum steps
- atomic rename to a published location
- controlled retrieval and completion handling

## Tests

Testing must be comprehensive.

Required coverage:

- unit tests for config validation and callback behavior
- integration tests with a live SSH/SFTP server
- negative tests for invalid auth, denied commands, and path traversal
- corner-case tests for cancellation, concurrent sessions, and interrupted transfers
- valgrind coverage for affected C++ tests

## Phases

### Phase 0

- repository scaffolding
- hosted repo and CI setup
- design and API specification

### Phase 1

- namespace, class, hashdecl, and error taxonomy design
- config schema definition

### Phase 2

- binary module foundation
- listener lifecycle
- cancellation and sandbox integration

### Phase 3

- authentication and policy hooks

### Phase 4

- controlled command execution

### Phase 5

- SFTP server and atomic file workflows
- typed backend contract implemented end to end for filesystem, streamed
  handle, and atomic-exchange verbs
- strongly typed virtual helper layer for filesystem, exchange, and
  record-store workflows
- live audit and integration coverage for exchange success/failure paths,
  malformed backends, and inbound upload policy enforcement

### Phase 6

- generic user modules for ConnectionProvider and DataProvider support
- `SshServerConnections` is now the reusable `ConnectionProvider`
  module for managed local SSH/SFTP server definitions
  - current classes:
    - `AbstractSshServerConnection`
    - `SshCommandServerConnection`
    - `SftpServerConnection`
  - current schemes:
    - `sshsrv`
    - `sshserver`
    - `sftpsrv`
    - `sftpserver`
  - current behavior:
    - returns live `Qore::Ssh::SshServer` objects
    - projects typed `SshServerConfig` and `SshListenerConfig` hashes
      through `getServerConfig()` and `getListenerConfig()`
    - supports command-service virtualization through
      `command_backend.handle(hash<SshCommandRequest>)` when
      `command_callback` is not set explicitly
- `SshServerCommandProvider` is now the first generic command-virtualization
  helper layer
  - current helper:
    - `VirtualSshCommandService`
  - current behavior:
    - typed virtual command registry with static and closure-backed exec and
      subsystem handlers
    - typed grouped configuration through
      `VirtualSshCommandPolicy`, `VirtualSshCommandAuditOptions`, and
      `VirtualSshCommandLimits`
    - grouped runtime setters replace their full configuration domain
      deterministically, with typed getter snapshots and clear-to-default
      helpers
    - exact-name allow/deny policy for commands and subsystems
    - principal-aware policy overrides through `setPrincipalPolicy()`
      including principal-specific default results
    - optional audit-capture controls for environment, arguments, identity, and
      bounded string truncation
    - optional global and per-principal concurrency caps for active command
      dispatch
    - deterministic default-deny fallback for missing commands
    - bounded request capture for test and audit-oriented inspection
    - optional environment redaction in captured requests
    - `request_history_limit = 0` disables capture and clears retained history
    - concurrency-denied requests return `exit_status = 126` with stable
      `result_data.reason_code` values:
      `command-concurrency-above-maximum` and
      `principal-command-concurrency-above-maximum`
    - policy-denied requests return `exit_status = 126` with stable
      `result_data.reason_code` values:
      `command-policy-denied` and `subsystem-policy-denied`
  - current boundary:
    - no generic command `DataProvider`
    - command virtualization stays at the connection and virtual-service layer
    - advanced controls are exposed through typed service options and runtime
      setters, not child action metadata
- `SftpServerDataProvider` is now the first reusable generic `DataProvider`
  infrastructure layer for generic submit/retrieve/claim/archive/delete flows
  - current factory:
    - `sftpserver`
  - current app:
    - `SftpServerExchange`
  - current child API providers:
    - `submit-inbound`
    - `list-outbound`
    - `retrieve-outbound`
    - `claim-outbound`
    - `archive-outbound`
    - `delete-outbound`
    - `cleanup-expired`
  - current child event providers:
    - `inbound-file-accepted`
      observable entry point for:
      `inbound-file-accepted` and `inbound-file-rejected`
    - `outbound-file-claimed`
    - `outbound-file-archived`
    - `outbound-file-deleted`
  - current behavior:
    - backed by `VirtualSftpExchangeRecordStore` / `VirtualSftpExchange`
    - typed request/response data types
    - typed inbound submission event payloads with optional persisted SHA-256
      checksum metadata for later stat/list/retrieve flows
    - typed outbound completion event payloads, including checksum metadata
      when the completed record carries it
    - typed retention cleanup request/response payloads
      including optional principal-scoped cleanup
    - typed accepted/rejected inbound event ids and reason codes
    - direct factory usage and action-catalog registration
    - scheme-bound to `sftpserver` through
      `SshServerConnections::SftpServerConnection`
    - can reuse a single backend object for both accepted SFTP sessions and
      the generic `DataProvider` bridge
    - supports config-driven observable inbound submission flows for local
      SFTP servers
    - tracks principal-aware retention metadata so cleanup can be scoped
      deterministically even when principals share the same inbound root
- application-specific adapters stay out of this repo; only generic integration
  infrastructure belongs here
- all current `qlib/` user modules now use the standard directory-module layout
  and local tests/examples load them through directory `%requires` paths
- detailed design note: `design/data-provider-infrastructure.md`

### Current Follow-Up Work

- stabilization includes validation, CI hardening, and valgrind runs
