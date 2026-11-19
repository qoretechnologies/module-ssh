# Atomic SFTP file exchange

Copyright 2026 Qore Technologies, s.r.o.

The implementation starts at develop commit `8f57f57`. A partner uploads one complete member to a principal-private staging area, closes it, then renames it into the agreed inbound directory. The rename commits both immutable content and its publication receipt. A lost rename reply is reconciled by principal and final name.

1. Strengthen the real-client regression in `test/VirtualSftpServer.qtest`. Exercise a rejected write followed by close and prove that a later, independent upload succeeds. Split native handle cleanup from explicit close. Give resource-owning backends an idempotent abort hook, including the virtual exchange's upload reservation. Preserve successful buffered and streamed operations.
2. Correct `SftpSession::publishLocalFile()`. A strict move can rename directly to the destination on the same filesystem. A strict copy requires exclusive private staging and an atomic rename. Fail before exposing bytes if staging or rename is unsuitable. Test cancellation/error cleanup, collisions, empty data, and compatibility with ordinary publication.
3. Add an opt-in exchange backend with private staging and atomic no-replace publication. Bind open handles to authenticated owners, reject premature rename, and prevent stale handles from changing completed members. Use a transactional store to bind the receipt and content, enforce uniqueness, and support restart reconciliation. Keep existing direct-submit and outbound operations available through their existing backend. Document where an operator can rely on restart recovery.
4. Expose metadata-only publication facts to connection/provider consumers and document the producer and consumer calls. Qualify the public surface using independent client sessions, explicit protocol barriers, lost replies, competing commits, principal isolation, and restart. Business acknowledgments, workflow dispatch, and batch correlation remain Qorus responsibilities.

Run focused debug-enabled tests at each implementation boundary and the module suites before completion. Run affected native paths with Valgrind and `qore -b --enable-debug`. Audit the staged changes before every commit. Keep the module-ssh2 agreement explicit about the staging and final paths, ordinary SFTP rename, collision semantics, and reconciliation identity.
