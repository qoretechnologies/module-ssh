Atomic SFTP file exchange audit
===============================

Copyright 2026 Qore Technologies, s.r.o.

The plan commit added one Markdown file outside the implemented-design directory.
Its documentation and scope checks passed against develop at 8f57f57. The
repository was clean when the feature branch was created. All runtime checks
below were inapplicable to that commit.

The native and compatibility commit 2097180 covered the two QPP files, upload
reservation cleanup and three existing executable test suites. Its applicable
checks were handle ownership, typed close/abort dispatch, sandboxing,
cancellation, local rename semantics, tests and native memory safety.

Implementation review
---------------------

.. list-table::
   :header-rows: 1
   :widths: 27 9 64

   * - Check
     - Result
     - Evidence
   * - Core module catalog and core release notes
     - N/A
     - The feature extends an existing external module.
   * - External release notes and API documentation
     - Pass
     - The SFTP Backend Guide documents close, abort, collision policy, cursor semantics and recovery. The release notes link to the working producer/consumer example.
   * - CMake registration, module structure and namespace
     - Pass
     - The existing SftpServerDataProvider build includes StagedSftpExchange.qc in its compiled module and metadata. The new class uses the module namespace. The existing main .qm owns parse directives. No new binary class or module requires registration.
   * - Test structure and dependencies
     - Pass
     - Changed suites use %modern, executable permissions and repository-first module lookup. The strict suite uses %try-module for the external sqlite3 driver. Package qualification installs the driver as a test dependency.
   * - Sandboxing
     - Pass
     - The native session uses its filesystem and network domains. Strict local publication checks the source, destination and staging permissions with the sandbox manager. SQLite opens an operator-configured local file through the DBI driver. SFTP filenames enter SQL as bound values.
   * - Cooperative cancellation
     - Pass
     - Local copying checks cancellation between reads and writes. The wire test cancels a dispatcher after an acknowledged write and reuses its staging name on a new session. Cleanup releases all detached handles. Large database copies run in bounded batches.
   * - Action registration and request handler
     - Pass
     - The list-publications API action has an option for the required principal and optional page controls, a typed response and a request-capable provider. Connection tests exercise its normal child-provider path.
   * - Data types and allowed values
     - Pass
     - Request fields are public and response fields are private on the new HashDataType classes. Each field declares its type and meaning. Validation checks the open-ended principal, cursor and numeric page size. The endpoint exposes a fixed no-replace policy.
   * - App registration, descriptions and scheme
     - Pass
     - The existing app supplies the FileTransfer group and its external logo. The action uses a scheme path, a plain short description and Markdown help. Source and packaged catalog checks cover all standard locales.
   * - New factory map entries, record searches and JNI assets
     - N/A
     - The action uses the existing connection and factory. The change introduces no factory, find action or Java dependency.
   * - Workarounds and incomplete implementations
     - Pass
     - A failed write invalidates its handle. A database uniqueness constraint resolves final-name collisions at commit. The independent ConnectionProvider callable-validation defect is tracked in Qore issue 6712.
   * - Exception safety
     - Pass
     - Native holders release references and descriptors. Cleanup addresses the original backend and handle. Failed publication rolls back both the receipt and inserted chunks. The injected storage failure leaves the stage available for retry.
   * - Thread safety
     - Pass
     - Session handle maps use the session mutex and the channel has one request dispatcher. The backend serializes transactions on its datasource. Two synchronized OpenSSH clients compete for one final name.
   * - Type safety and QPP flags
     - Pass
     - Native close and abort use the existing typed request. Public Qore hashdecls describe receipts, capabilities and observer events. No new QPP method requires a flag assignment.
   * - Performance
     - Pass
     - Local copies and publication reads use bounded chunks. Directory pagination retains its listing by reference. Receipt enumeration selects metadata by version and enforces a page limit.
   * - Error handling
     - Pass
     - Tests cover stale handles, nonconsecutive writes, invalid staging, existing targets, cross-device moves, cancellation, observer exceptions and rollback after an injected database error.
   * - Security and isolation
     - Pass
     - Wire operations derive the principal from the authenticated session. A second principal cannot rename another owner's stage or read its receipt or bytes. Loopback fixtures use the repository's public test identities.
   * - Correctness and compatibility
     - Pass
     - Tests establish visibility before and after rename, one winning immutable identity, empty and multi-chunk payloads, successful legacy direct submission and recovery after an unread reply and producer process exit.
   * - Native memory and runtime checks
     - Pass
     - The affected debug-enabled sessions run under Memcheck with qore -b, AST execution and QORE_PCRE2_NO_JIT=1. This exercises native server code with the instrumentable regex engine.

Qualification
-------------

The compiled-package runner exercised all 18 test suites, seven examples and
the compiler smoke test. The staging suite checked rollback after the second
database write failed, cross-session cancellation, concurrent OpenSSH clients,
an unread rename response and receipt recovery across a process boundary.
Memcheck reported zero errors and zero definitely lost bytes for SftpSession,
VirtualSftpServer and StagedSftpExchange. The docs target built the backend
guide, and the packaged provider catalogs validated 8,892 translations.
