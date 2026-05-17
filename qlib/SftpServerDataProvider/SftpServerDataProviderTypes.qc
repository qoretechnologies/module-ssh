# -*- mode: qore; indent-tabs-mode: nil -*-
#! SftpServerDataProvider typed helper and provider data definitions

/*  SftpServerDataProviderTypes.qc Copyright 2026 Qore Technologies, s.r.o.

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

public namespace SftpServerDataProvider {
    public const AppName = "SftpServerExchange";
    public const FactoryName = "sftpserver";
    public const EventInboundFileAccepted = "inbound-file-accepted";
    public const EventInboundFileRejected = "inbound-file-rejected";
    public const EventOutboundFileClaimed = "outbound-file-claimed";
    public const EventOutboundFileArchived = "outbound-file-archived";
    public const EventOutboundFileDeleted = "outbound-file-deleted";
    public const EventSourceHelper = "helper";
    public const EventSourceSftp = "sftp";
    public const RetentionQueueInbound = "inbound";
    public const RetentionQueueArchive = "archive";
    public const RetentionQueueClaim = "claim";
    public const InboundEventPayloadNone = "none";
    public const InboundEventPayloadInline = "inline";
    public const ChecksumAlgorithmSha256 = "sha256";
    public const InboundRejectHiddenFile = "hidden-file-not-allowed";
    public const InboundRejectFilenameGlob = "filename-glob-rejected";
    public const InboundRejectFilenameRegex = "filename-regex-rejected";
    public const InboundRejectMinSize = "size-below-minimum";
    public const InboundRejectMaxSize = "size-above-maximum";
    public const InboundRejectOverwrite = "overwrite-not-allowed";
    public const InboundRejectDuplicateName = "duplicate-name-rejected";
    public const InboundRejectDuplicateSize = "duplicate-size-rejected";
    public const InboundRejectDuplicateHash = "duplicate-hash-rejected";
    public const InboundRejectContentPrefix = "content-prefix-rejected";
    public const InboundRejectContentTypeHint = "content-type-hint-rejected";
    public const InboundRejectCustomValidation = "custom-validation-rejected";
    public const InboundRejectMaxFileCount = "file-count-above-maximum";
    public const InboundRejectMaxTotalBytes = "total-bytes-above-maximum";
    public const InboundRejectMaxConcurrentUploads = "concurrent-uploads-above-maximum";
    public const InboundRejectPrincipalDenied = "principal-denied";
    public const InboundRejectPrincipalNotAllowed = "principal-not-allowed";

    #! virtual filesystem persistence configuration options
    public hashdecl VirtualSftpPersistenceOptions {
        #! local directory for snapshot files
        *string persistence_dir;
        #! persistence mode: "snapshot" or "write-through"
        *string persistence_mode;
        #! interval in seconds between periodic snapshots (snapshot mode only)
        *int snapshot_interval_seconds;
        #! restore state from persistence dir on construction
        *bool restore_on_construct;
        #! Low/Info: maximum accepted on-disk snapshot size in bytes when restoring
        /** A tampered or runaway snapshot file is otherwise loaded wholesale into memory.
            Defaults to 256 MiB when not set. */
        *int max_snapshot_bytes;
    }

    #! virtual filesystem configuration options
    public hashdecl VirtualSftpFilesystemOptions {
        *int default_file_permissions;
        *int default_directory_permissions;
        *string archive_dir;
        *hash<VirtualSftpPersistenceOptions> persistence;
        *LoggerInterface logger;
        #! allow-listed real-filesystem roots a submit() @c source_path may be read from
        /** Reading a server-local file via a submission @c source_path is a server-side helper
            convenience (e.g. submitLocalFile()); it is not reachable from a remote SFTP client.
            It is disabled by default (fail-closed): a @c source_path is only read when this list
            is configured and the canonicalized file resolves inside one of the canonicalized
            roots, preventing an integration that forwards untrusted input as @c source_path from
            reading arbitrary server files (M-1). */
        *softlist<string> allowed_source_path_roots;
        #! global cap on the total in-memory bytes held by the virtual filesystem (M-8)
        /** Enforced for every data-ingest path independently of any inbound policy; bounds
            server memory (and, with write-through persistence, the per-write snapshot cost). */
        *int max_total_bytes;
        #! global cap on the number of files held by the virtual filesystem (M-8)
        *int max_file_count;
        #! global cap on the size of a single virtual file (M-8)
        *int max_file_size;
    }

    #! SFTP file exchange configuration with inbound/outbound directories and policies
    public hashdecl VirtualSftpExchangeOptions inherits VirtualSftpFilesystemOptions {
        *string inbound_dir;
        *string outbound_dir;
        *string claim_dir;
        *hash<VirtualSftpInboundPolicy> inbound_policy;
        *hash<VirtualSftpRetentionPolicy> inbound_retention_policy;
        *hash<VirtualSftpRetentionPolicy> archive_retention_policy;
        *hash<VirtualSftpRetentionPolicy> claim_retention_policy;
        *string inbound_event_payload_mode;
        *bool generate_inbound_checksum;
    }

    #! file retention policy with age-based expiration
    public hashdecl VirtualSftpRetentionPolicy {
        *int max_age_seconds;
    }

    #! request data passed to inbound file validation callbacks
    public hashdecl VirtualSftpInboundValidationRequest {
        string name;
        string path;
        *int size;
        hash<auto> metadata;
        *binary data;
        *string source_path;
        string source;
        string operation;
        *hash<Qore::Ssh::SftpSessionInfo> session_info;
        *string principal;
        *string content_type_hint;
        hash<auto> policy;
        string scope_root;
        *string scope_principal;
    }

    #! result of inbound file validation indicating acceptance or rejection
    public hashdecl VirtualSftpInboundValidationResult {
        bool accepted = True;
        *string reason_code;
        *string reason_desc;
    }

    #! inbound file acceptance policy configuration
    public hashdecl VirtualSftpInboundPolicy {
        *string accept_filename_glob;
        *string reject_filename_glob;
        *string accept_filename_regex;
        *string reject_filename_regex;
        *int min_size;
        *int max_size;
        *int max_file_count;
        *int max_total_bytes;
        *int max_concurrent_uploads;
        *bool allow_overwrite;
        *bool reject_duplicate_name;
        *bool reject_duplicate_size;
        *bool reject_duplicate_hash;
        *binary accept_content_prefix;
        *binary reject_content_prefix;
        *list<string> accept_content_type_hints;
        *list<string> reject_content_type_hints;
        *code<hash<VirtualSftpInboundValidationResult>(hash<VirtualSftpInboundValidationRequest>)>
            validation_callback;
        *bool allow_hidden_files;
        *list<string> allow_principals;
        *list<string> deny_principals;
        *list<hash<VirtualSftpPrincipalPolicy>> principal_policies;
        *list<hash<VirtualSftpPrincipalRoute>> principal_routes;
        *list<hash<VirtualSftpInboundDirectoryPolicy>> directory_policies;
    }

    #! reusable inbound policy rule for directory or principal-level overrides
    public hashdecl VirtualSftpInboundPolicyRule {
        *string accept_filename_glob;
        *string reject_filename_glob;
        *string accept_filename_regex;
        *string reject_filename_regex;
        *int min_size;
        *int max_size;
        *int max_file_count;
        *int max_total_bytes;
        *int max_concurrent_uploads;
        *bool allow_overwrite;
        *bool reject_duplicate_name;
        *bool reject_duplicate_size;
        *bool reject_duplicate_hash;
        *binary accept_content_prefix;
        *binary reject_content_prefix;
        *list<string> accept_content_type_hints;
        *list<string> reject_content_type_hints;
        *code<hash<VirtualSftpInboundValidationResult>(hash<VirtualSftpInboundValidationRequest>)>
            validation_callback;
        *bool allow_hidden_files;
    }

    #! per-subdirectory inbound policy override
    public hashdecl VirtualSftpInboundDirectoryPolicy {
        string subdir;
        hash<VirtualSftpInboundPolicyRule> policy;
    }

    #! mapping from a principal to an inbound subdirectory
    public hashdecl VirtualSftpPrincipalRoute {
        string principal;
        string inbound_subdir;
    }

    #! per-principal inbound policy override
    public hashdecl VirtualSftpPrincipalPolicy {
        string principal;
        hash<VirtualSftpInboundPolicyRule> policy;
    }

    #! base request type with path and session info
    public hashdecl VirtualSftpPathRequest {
        string path;
        *hash<Qore::Ssh::SftpSessionInfo> session_info;
        *hash<auto> metadata;
    }

    #! file submission request with optional data payload
    public hashdecl VirtualSftpSubmissionRequest inherits VirtualSftpPathRequest {
        *binary data;
        *string source_path;
    }

    #! file completion request with optional target path and completion mode
    public hashdecl VirtualSftpCompletionRequest inherits VirtualSftpPathRequest {
        *string target_path;
        *string completion_mode;
    }

    #! request to run retention cleanup on a specific queue
    public hashdecl VirtualSftpRetentionCleanupRequest {
        string queue;
        *int now_s;
        *string principal;
        *bool remove_empty_directories;
    }

    #! base result type for virtual filesystem operations
    public hashdecl VirtualSftpOperationResult {
        *string path;
        bool available;
        bool completed = False;
        *string checksum;
        *string checksum_algorithm;
        *hash<Qore::Ssh::SftpTransferInfo> transfer_info;
    }

    #! built-in file state tracking for archive and claim lifecycle
    public hashdecl VirtualSftpBuiltinState {
        bool archived = False;
        bool claimed = False;
        *int archived_at;
        *int claimed_at;
        *string exchange_role;
    }

    #! directory listing result with entry details
    public hashdecl VirtualSftpListResult inherits VirtualSftpOperationResult {
        list<hash<VirtualSftpEntryInfo>> entries = ();
    }

    #! file retrieval result with data payload, size, and permissions
    public hashdecl VirtualSftpRetrieveResult inherits VirtualSftpOperationResult {
        *binary data;
        *int size;
        *int permissions;
    }

    #! file or directory stat result with metadata and state
    public hashdecl VirtualSftpStatResult inherits VirtualSftpOperationResult {
        bool directory = False;
        *int size;
        *int permissions;
        *int mtime;
        *int atime;
        *hash<VirtualSftpBuiltinState> state;
        *hash<auto> metadata;
    }

    #! result of opening a file for reading, including stat info and data
    public hashdecl VirtualSftpOpenReadResult inherits VirtualSftpStatResult {
        *binary data;
    }

    #! result of opening a file for writing
    public hashdecl VirtualSftpOpenWriteResult inherits VirtualSftpOperationResult {
        *int permissions;
    }

    #! serializable snapshot of a single file's data, metadata, and state
    public hashdecl VirtualSftpFileSnapshot {
        int size;
        binary data;
        *string checksum;
        *string checksum_algorithm;
        *hash<VirtualSftpBuiltinState> state;
        hash<auto> metadata;
        int permissions;
        int mtime;
        int atime;
    }

    #! complete filesystem snapshot for persistence and restore
    public hashdecl VirtualSftpSnapshot {
        string root_path;
        list<string> file_paths;
        list<string> directory_paths;
        hash<auto> files;
    }

    #! directory entry information for a file or subdirectory
    public hashdecl VirtualSftpEntryInfo {
        string filename;
        string long_name;
        bool directory;
        *bool symlink;
        *string target_path;
        int size;
        *string checksum;
        *string checksum_algorithm;
        int permissions;
        int mtime;
        int atime;
        *hash<VirtualSftpBuiltinState> state;
        hash<auto> metadata;
    }

    #! record-oriented file information for queue operations
    public hashdecl VirtualSftpRecordInfo {
        string queue;
        string name;
        *string path;
        int size;
        *string checksum;
        *string checksum_algorithm;
        hash<auto> metadata;
        *binary data;
        *string final_name;
        *string operation;
        bool completed = False;
    }

    #! base record request with name and optional metadata
    public hashdecl VirtualSftpRecordRequest {
        string name;
        *hash<auto> metadata;
    }

    #! record submission request with binary data payload
    public hashdecl VirtualSftpRecordSubmissionRequest inherits VirtualSftpRecordRequest {
        binary data;
    }

    #! record completion request with optional final name and completion mode
    public hashdecl VirtualSftpRecordCompletionRequest inherits VirtualSftpRecordRequest {
        *string final_name;
        *string completion_mode;
    }

    #! inbound file event payload with acceptance status and transfer details
    public hashdecl VirtualSftpInboundEventInfo {
        string event_type = EventInboundFileAccepted;
        string queue = "inbound";
        string name;
        string path;
        int size;
        hash<auto> metadata;
        *binary data;
        int submitted_at;
        *string source;
        *string session_id;
        *string server_name;
        *string listener_name;
        *string principal;
        bool accepted = True;
        *string reason_code;
        *string reason_desc;
        *string checksum;
        *string checksum_algorithm;
        *hash<Qore::Ssh::SftpTransferInfo> transfer_info;
    }

    #! outbound file event payload with claim/archive/delete details
    public hashdecl VirtualSftpOutboundEventInfo {
        string event_type;
        string queue = "outbound";
        string name;
        string path;
        int size = 0;
        hash<auto> metadata;
        int completed_at;
        *string source;
        *string session_id;
        *string server_name;
        *string listener_name;
        *string principal;
        *string final_name;
        *string operation;
        *string reason_code;
        *string reason_desc;
        *string checksum;
        *string checksum_algorithm;
        *hash<Qore::Ssh::SftpTransferInfo> transfer_info;
    }

    #! result of a retention cleanup operation with removed file and directory lists
    public hashdecl VirtualSftpRetentionCleanupResult {
        string queue;
        int evaluated_at;
        *string principal;
        int removed_count;
        list<string> removed_paths;
        list<string> removed_directories;
    }
}
