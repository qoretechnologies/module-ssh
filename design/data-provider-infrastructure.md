# module-ssh Data Provider Infrastructure Design

## Scope

This design note defines the generic infrastructure that belongs in
`module-ssh` for `ConnectionProvider` and `DataProvider` integration.

The stable public contract that builds on this infrastructure is documented in
`design/api-spec.md`.

The boundary is explicit:

- generic provider infrastructure belongs in this repo
- generic typed request and response models belong in this repo
- generic connection schemes for managed SSH and SFTP servers belong in this
  repo
- application-specific actions, workflows, domain objects, and adapters do not
  belong
  in this repo

This note follows the rules and patterns documented in:

- `/home/david/src/qore/git/qore/design/data-provider-development-guide.md`
- `/home/david/src/qore/git/qore/design/data-provider-checklist.md`

## Goals

This layer provides reusable Qore-level integration infrastructure on top of
the binary `ssh` module.

Required outcomes:

- `SshServerConnections` becomes a real `ConnectionProvider` module
- command-oriented server flows support generic virtualization helpers
- `SftpServerDataProvider` grows a real `DataProvider` module structure
- server-side file-exchange flows are exposed through generic provider actions
- server lifecycle and backend wiring can be configured through typed
  connection/provider metadata instead of ad hoc scripts

## Module Split

The generic user-module split should be:

- `SshServerConnections`
  - `ConnectionProvider` scheme registration
  - typed local server connection/configuration objects
  - listener and service lifecycle helpers
  - logger and status integration
- `SshServerCommandProvider`
  - generic virtual command-service helpers
  - typed command request/result handling
  - reusable command virtualization for managed SSH command servers
  - intentionally no `DataProvider` layer
- `SftpServerDataProvider`
  - `DataProvider` app and action registration
  - typed request and response data types
  - provider classes that operate on `SftpSession`/backend abstractions
  - generic file-exchange actions for submit, retrieve, claim, archive, and
    delete

No application-specific adapter module should be implemented here.

## ConnectionProvider Design

`SshServerConnections` now follows the same high-level pattern as
`module-ssh2`'s `Ssh2Connections`, but adapted for local managed server
instances rather than outbound client connections.

Current public classes:

- `SshServerConnections::AbstractSshServerConnection`
- `SshServerConnections::SftpServerConnection`
- `SshServerConnections::SshCommandServerConnection`

Current scheme usage:

- `sftpsrv` / `sftpserver` for local SFTP-oriented server definitions
- `sshsrv` / `sshserver` for local command-oriented server definitions

The implemented `ConnectionSchemeInfo` hashes provide:

- user-friendly `display_name`, `short_desc`, and markdown `desc`
- typed option descriptions via `ConnectionOptionInfo`
- explicit `required_options` where needed
- logger support
- lifecycle-related options such as listener address, port, host keys, auth
  behavior, callback wiring, and logging policy

The connection classes do not embed application-specific assumptions. They expose generic
local server configuration, return managed `Qore::Ssh::SshServer` objects, and
project typed `Qore::Ssh::SshServerConfig` /
`Qore::Ssh::SshListenerConfig` hashes through `getServerConfig()` and
`getListenerConfig()`.

`SshCommandServerConnection` now also supports a generic `command_backend`
option. When `command_callback` is not configured explicitly, the connection
synthesizes a typed callback that delegates to
`command_backend.handle(hash<SshCommandRequest>)`.

## Command Virtualization Helper Design

`SshServerCommandProvider` is the first generic helper layer for command-side
virtualization.

Current helper elements:

- `SshServerCommandProvider::VirtualSshCommandService`
  - registers static typed command results by command name
  - registers typed closure-backed handlers by command name
  - returns a deterministic default-deny result for unknown commands unless a
    default result is configured
  - records handled typed command requests for inspection in tests and higher
    layers

This helper is intentionally generic. It does not model application workflows or
process orchestration; it only virtualizes the SSH command namespace.

The command contract itself is intentionally compact and typed:

- request: `hash<SshCommandRequest>`
  - stable identity and routing fields
  - protocol-specific distinctions are limited to `metadata.request_type` and
    `metadata.subsystem`
- result: `hash<SshCommandResult>`
  - stable acceptance, exit, stdout, and stderr fields
  - higher-level integration payloads remain in `result_data`

No command-oriented `DataProvider` layer is implemented here. Command execution is
not a natural data-exchange abstraction, so the command side stops at:

- `SshCommandServerConnection`
- `VirtualSshCommandService`
- typed `SshCommandRequest` / `SshCommandResult` contracts

The intended usage pattern is:

- define a `VirtualSshCommandService`
- attach it as `command_backend` on `SshCommandServerConnection`
- let the connection synthesize the typed command callback for the server

Observable and action-oriented provider behavior is reserved for the SFTP side,
where submit/retrieve/exchange workflows are the real public abstraction.

## DataProvider Design

The `DataProvider` infrastructure in this repo is intentionally SFTP-only.
There is no command-side `DataProvider` layer in this repo.

`SftpServerDataProvider` now has an initial real `DataProvider` implementation
and already uses the repository-standard directory-module layout. The longer-term
target layout remains:

```text
qlib/
  SftpServerDataProvider/
    SftpServerDataProvider.qm
    SftpServerDataProviderTypes.qc
    SftpServerDataProviderProviderTypes.qc
    SftpServerDataProviderProviders.qc
    VirtualSftpFilesystem.qc
    VirtualSftpExchange.qc
    VirtualSftpExchangeRecordStore.qc
```

Current implemented provider elements:

- registered factory: `sftpserver`
- registered app: `SftpServerExchange`
- root provider: `SftpServerDataProvider`
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
    observable entry point for accepted/rejected inbound events
  - `outbound-file-claimed`
  - `outbound-file-archived`
  - `outbound-file-deleted`
- typed request/response data types for those actions
- typed retention cleanup request/response data types
- principal-scoped retention cleanup for inbound/archive/claim queues
- typed inbound submission event payloads with optional binary data fanout and
  persisted checksum metadata for later stat/list/retrieve flows
- typed outbound completion event payloads for claim/archive/delete flows,
  including checksum metadata when the completed record carries it
- typed accepted/rejected inbound event ids and rejection reason codes
- typed inbound acceptance policy options
- principal-aware inbound acceptance and routing policy
- principal-aware retention metadata for deterministic cleanup in shared roots
- live-session event context fields:
  - `session_id`
  - `server_name`
  - `listener_name`
  - `principal`
- constructor-time backend injection via `VirtualSftpExchangeRecordStore` or
  `VirtualSftpExchange`

The main remaining cleanup is internal naming and file-boundary polish, not
the directory-module conversion itself.

### App Model

The generic provider app should describe a managed SFTP server endpoint rather
than a specific business workflow.

Current app shape:

- app name based on managed SFTP server exchange
- `AppGroup::FileTransfer`
- scheme-bound through `sftpserver`
- generic file-transfer branding and descriptions
- served by `SshServerConnections::SftpServerConnection`
- may share a single `VirtualSftpExchangeRecordStore` /
  `VirtualSftpExchange` backend object between the live server and the generic
  data-provider bridge

### Action Model

The first provider actions should map cleanly onto the already-implemented
generic exchange semantics.

Initial action families:

- list available exchange entries
- retrieve an exchange entry
- submit an inbound file
- claim an outbound file
- archive an outbound file
- delete an outbound file
- raise an event when a new inbound file is submitted

These actions should be described through typed request/response data types,
not raw `hash<auto>` payloads.

Inbound submissions should also support generic acceptance policy controls at
the backend boundary, exposed through typed constructor/action options. The
current policy surface is:

- `accept_filename_glob`
- `reject_filename_glob`
- `accept_filename_regex`
- `reject_filename_regex`
- `min_size`
- `max_size`
- `max_file_count`
- `max_total_bytes`
- `max_concurrent_uploads`
- `allow_overwrite`
- `reject_duplicate_name`
- `reject_duplicate_size`
- `reject_duplicate_hash`
- `accept_content_prefix`
- `reject_content_prefix`
- `accept_content_type_hints`
- `reject_content_type_hints`
- `validation_callback`
- `allow_hidden_files`
- `allow_principals`
- `deny_principals`
- `principal_policies`
- `principal_routes`
- `directory_policies`

Typed backend constructor options should also expose retention metadata and
cleanup hooks through:

- `inbound_retention_policy`
- `archive_retention_policy`
- `claim_retention_policy`

Each retention policy currently supports `max_age_seconds`, and the backend
should stamp deterministic `retention_queue`, `retained_at`, and `expires_at`
metadata so helper-side cleanup can be explicit rather than watch-based.

The inbound event action should also be config-driven and observable, so one
provider configuration can:

- bind to a local `sftpserver` connection
- share the same `VirtualSftpExchange` backend with accepted SFTP sessions
- emit typed inbound submission events when clients upload files
- control event payload fanout explicitly with `inbound_event_payload_mode`

### Provider Base Class

`SftpServerDataProviderBase` should own the generic integration state:

- resolved managed server connection
- logger
- typed session/backend access helpers
- common validation and path normalization helpers
- exception-to-provider-error translation

This base class should operate only on generic `module-ssh` abstractions such
as `SftpSession`, `VirtualSftpExchange`, and typed exchange requests.

## Typed Data Types

The provider layer should introduce explicit data types for the stable generic
exchange workflows.

Planned request types:

- exchange path request
- exchange submission request
- exchange retrieval request
- exchange completion request

Planned response types:

- exchange listing entry
- exchange retrieval response
- exchange completion response
- exchange transfer/state response

The request/response shape should align with the existing typed helper hashes in
`SftpServerDataProvider/` so the helper layer and provider layer do not drift
apart.

## Logging and Audit Expectations

Provider infrastructure in this repo should preserve the current logger model:

- loggers are optional and best-effort
- child objects inherit parent loggers by default
- provider-layer actions should emit stable operational messages
- errors from provider wiring or action execution should be visible through
  logger output and typed exceptions

The provider layer should rely on stable `SshServer` / `SftpSession` logs where
possible instead of inventing redundant ad hoc audit channels.

## Testing Requirements

Per the Qore data-provider guide and checklist, provider work is not complete
without dedicated tests.

Required coverage:

- module-load tests for `SshServerConnections`
- provider module-load and action-registration tests
- typed request/response tests
- negative tests for invalid options and invalid provider requests
- live integration tests against the existing local OpenSSH-driven server path
  where practical

## Deliberate Non-Goals

The following are explicitly out of scope for this repo:

- application-specific admin adapters
- application-specific user/session models
- application-specific workflow logic
- application-specific naming, actions, or provider specializations

Those should build on the generic provider infrastructure defined here rather
than living in this repo.
