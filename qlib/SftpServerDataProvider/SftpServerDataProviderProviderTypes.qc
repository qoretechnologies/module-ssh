# -*- mode: qore; indent-tabs-mode: nil -*-
#! SftpServerDataProvider DataProvider-specific types

/*  SftpServerDataProviderProviderTypes.qc Copyright 2026 Qore Technologies, s.r.o.

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
    #! allowed values for the typed completion mode (DP1)
    public const SftpServerCompletionModeAllowedValues = (
        <AllowedValueInfo>{"value": "claim", "display_name": "Claim"},
        <AllowedValueInfo>{"value": "archive", "display_name": "Archive"},
        <AllowedValueInfo>{"value": "delete", "display_name": "Delete"},
    );

    #! allowed values for the retention queue selector (DP1)
    public const SftpServerRetentionQueueAllowedValues = (
        <AllowedValueInfo>{"value": RetentionQueueInbound, "display_name": "Inbound"},
        <AllowedValueInfo>{"value": RetentionQueueArchive, "display_name": "Archive"},
        <AllowedValueInfo>{"value": RetentionQueueClaim, "display_name": "Claim"},
    );

    #! typed schema for the optional transfer_info carried by inbound/outbound events (DP5)
    /** Mirrors @ref Qore::Ssh::SftpTransferInfo.  Provided as a concrete typed schema so the
        structure is documented and reusable; the event fields reference it as
        @c *hash because @c transfer_info is optional and is omitted (NOTHING) for the common
        case, which a strict nested typed-hash field would reject. */
    public class SftpServerTransferInfoDataType inherits HashDataType {
        public {
            const Fields = {
                "operation": {
                    "display_name": "Operation",
                    "short_desc": "The transfer operation name",
                    "type": StringType,
                    "desc": "The transfer operation name.",
                },
                "path": {
                    "display_name": "Path",
                    "short_desc": "The virtual source path",
                    "type": StringType,
                    "desc": "The virtual source path.",
                },
                "temporary_path": {
                    "display_name": "Temporary Path",
                    "short_desc": "Optional temporary path",
                    "type": StringOrNothingType,
                    "desc": "Optional temporary path.",
                },
                "final_path": {
                    "display_name": "Final Path",
                    "short_desc": "Optional final published path",
                    "type": StringOrNothingType,
                    "desc": "Optional final published path.",
                },
                "size": {
                    "display_name": "Size",
                    "short_desc": "Optional transfer size in bytes",
                    "type": IntOrNothingType,
                    "desc": "Optional transfer size in bytes.",
                },
                "checksum": {
                    "display_name": "Checksum",
                    "short_desc": "Optional checksum string",
                    "type": StringOrNothingType,
                    "desc": "Optional checksum string.",
                },
                "atomic_publish": {
                    "display_name": "Atomic Publish",
                    "short_desc": "Whether atomic-publish behavior is active",
                    "type": BoolType,
                    "desc": "`True` when atomic-publish behavior is active.",
                },
                "completed": {
                    "display_name": "Completed",
                    "short_desc": "Whether the transfer workflow is completed",
                    "type": BoolType,
                    "desc": "`True` when the transfer workflow is completed.",
                },
            };
        }

        constructor() : HashDataType("SftpServerTransferInfo") {
            addQoreFields(Fields);
        }
    }

    public const SftpServerTransferInfoDataType = new SftpServerTransferInfoDataType();

    public class SftpServerSubmitInboundRequestDataType inherits HashDataType {
        public {
            const Fields = {
                "name": {
                    "display_name": "Entry Name",
                    "short_desc": "The inbound exchange entry name",
                    "type": StringType,
                    "desc": "The inbound exchange entry name.",
                    "example_value": "order-12345.csv",
                },
                "data": {
                    "display_name": "Payload",
                    "short_desc": "The binary payload to submit",
                    "type": BinaryType,
                    "desc": "The binary payload to submit.",
                },
                "metadata": {
                    "display_name": "Metadata",
                    "short_desc": "Optional free-form metadata for the entry",
                    "type": AutoHashOrNothingType,
                    "desc": "Optional free-form metadata to associate with the entry.",
                },
            };
        }

        constructor() : HashDataType("SftpServerSubmitInboundRequest") {
            addQoreFields(Fields);
        }
    }

    public class SftpServerRecordRequestDataType inherits HashDataType {
        public {
            const Fields = {
                "name": {
                    "display_name": "Entry Name",
                    "short_desc": "The exchange entry name",
                    "type": StringType,
                    "desc": "The exchange entry name.",
                    "example_value": "order-12345.csv",
                },
                "metadata": {
                    "display_name": "Metadata",
                    "short_desc": "Optional free-form metadata for the operation",
                    "type": AutoHashOrNothingType,
                    "desc": "Optional free-form metadata for the operation.",
                },
            };
        }

        constructor() : HashDataType("SftpServerRecordRequest") {
            addQoreFields(Fields);
        }
    }

    public class SftpServerRecordCompletionRequestDataType inherits HashDataType {
        public {
            const Fields = SftpServerRecordRequestDataType::Fields + {
                "final_name": {
                    "display_name": "Final Name",
                    "short_desc": "Optional final entry name for claim or archive",
                    "type": StringOrNothingType,
                    "desc": "Optional final entry name for `claim` or `archive` operations.",
                },
                "completion_mode": {
                    "display_name": "Completion Mode",
                    "short_desc": "How the retrieval is finalized",
                    "type": StringOrNothingType,
                    "desc": "Optional typed completion mode.\n\n"
                        "- `claim` -- move the entry to the claim queue\n"
                        "- `archive` -- move the entry to the archive queue\n"
                        "- `delete` -- delete the entry",
                    "allowed_values": SftpServerCompletionModeAllowedValues,
                },
            };
        }

        constructor() : HashDataType("SftpServerRecordCompletionRequest") {
            addQoreFields(Fields);
        }
    }

    public class SftpServerRetentionCleanupRequestDataType inherits HashDataType {
        public {
            const Fields = {
                "queue": {
                    "display_name": "Retention Queue",
                    "short_desc": "The retention queue to clean",
                    "type": StringType,
                    "desc": "The retention queue to clean.\n\n"
                        "- `inbound` -- the inbound submission queue\n"
                        "- `archive` -- the archived-entry queue\n"
                        "- `claim` -- the claimed-entry queue",
                    "allowed_values": SftpServerRetentionQueueAllowedValues,
                },
                "now_s": {
                    "display_name": "Evaluation Time",
                    "short_desc": "Optional deterministic evaluation time",
                    "type": DateOrNothingType,
                    "desc": "Optional deterministic evaluation time used to compute retention "
                        "expiration; defaults to the current time when not set.",
                },
                "principal": {
                    "display_name": "Principal",
                    "short_desc": "Optional principal to scope retention cleanup",
                    "type": StringOrNothingType,
                    "desc": "Optional authenticated principal to scope retention cleanup.",
                },
                "remove_empty_directories": {
                    "display_name": "Remove Empty Directories",
                    "short_desc": "Remove empty directories after deleting expired files",
                    "type": BoolOrNothingType,
                    "desc": "Whether empty directories should be removed after expired files are "
                        "deleted.",
                },
            };
        }

        constructor() : HashDataType("SftpServerRetentionCleanupRequest") {
            addQoreFields(Fields);
        }
    }

    public class SftpServerRecordInfoDataType inherits HashDataType {
        public {
            const Fields = {
                "queue": {
                    "display_name": "Queue",
                    "short_desc": "The logical exchange queue name",
                    "type": StringType,
                    "desc": "The logical exchange queue name.",
                },
                "name": {
                    "display_name": "Entry Name",
                    "short_desc": "The original exchange entry name",
                    "type": StringType,
                    "desc": "The original exchange entry name.",
                },
                "path": {
                    "display_name": "Path",
                    "short_desc": "The virtual exchange path for the entry",
                    "type": StringOrNothingType,
                    "desc": "The virtual exchange path for the entry, if any.",
                },
                "size": {
                    "display_name": "Size",
                    "short_desc": "The payload size in bytes",
                    "type": IntType,
                    "desc": "The payload size in bytes.",
                    "default_value": 0,
                },
                "checksum": {
                    "display_name": "Checksum",
                    "short_desc": "Optional checksum for the record payload",
                    "type": StringOrNothingType,
                    "desc": "Optional checksum for the record payload.",
                },
                "checksum_algorithm": {
                    "display_name": "Checksum Algorithm",
                    "short_desc": "Optional checksum algorithm for the payload",
                    "type": StringOrNothingType,
                    "desc": "Optional checksum algorithm for the record payload.",
                },
                "metadata": {
                    "display_name": "Metadata",
                    "short_desc": "Free-form entry metadata",
                    "type": AutoHashType,
                    "desc": "Free-form entry metadata.",
                    "default_value": {},
                },
                "data": {
                    "display_name": "Payload",
                    "short_desc": "The payload for retrieve operations",
                    "type": BinaryOrNothingType,
                    "desc": "The payload for retrieve operations.",
                },
                "final_name": {
                    "display_name": "Final Name",
                    "short_desc": "The final entry name after completion",
                    "type": StringOrNothingType,
                    "desc": "The final entry name after `claim` or `archive` completion.",
                },
                "operation": {
                    "display_name": "Operation",
                    "short_desc": "The completed operation name, if any",
                    "type": StringOrNothingType,
                    "desc": "The completed operation name, if any.",
                },
                "completed": {
                    "display_name": "Completed",
                    "short_desc": "Whether the operation completed a state transition",
                    "type": BoolType,
                    "desc": "Whether the operation completed a state transition.",
                    "default_value": False,
                },
            };
        }

        constructor() : HashDataType("SftpServerRecordInfo") {
            addQoreFields(Fields);
        }
    }

    public class SftpServerInboundEventInfoDataType inherits HashDataType {
        public {
            const Fields = {
                "event_type": {
                    "display_name": "Event Type",
                    "short_desc": "The emitted inbound event type",
                    "type": StringType,
                    "desc": "The emitted inbound event type.",
                    "default_value": EventInboundFileAccepted,
                },
                "queue": {
                    "display_name": "Queue",
                    "short_desc": "The logical exchange queue name",
                    "type": StringType,
                    "desc": "The logical exchange queue name.",
                    "default_value": "inbound",
                },
                "name": {
                    "display_name": "Entry Name",
                    "short_desc": "The submitted inbound entry name",
                    "type": StringType,
                    "desc": "The submitted inbound entry name.",
                },
                "path": {
                    "display_name": "Path",
                    "short_desc": "The virtual inbound path for the entry",
                    "type": StringType,
                    "desc": "The virtual inbound path for the submitted entry.",
                },
                "size": {
                    "display_name": "Size",
                    "short_desc": "The submitted payload size in bytes",
                    "type": IntType,
                    "desc": "The submitted payload size in bytes.",
                },
                "metadata": {
                    "display_name": "Metadata",
                    "short_desc": "Free-form metadata for the submitted entry",
                    "type": AutoHashType,
                    "desc": "Free-form metadata associated with the submitted entry.",
                    "default_value": {},
                },
                "data": {
                    "display_name": "Payload",
                    "short_desc": "The submitted payload when available",
                    "type": BinaryOrNothingType,
                    "desc": "The submitted payload when available.",
                },
                "submitted_at": {
                    "display_name": "Submitted At",
                    "short_desc": "When the submission event was emitted",
                    "type": DateType,
                    "desc": "When the submission event was emitted.",
                },
                "source": {
                    "display_name": "Source",
                    "short_desc": "The source of the submission event",
                    "type": StringOrNothingType,
                    "desc": "The source of the submission event, for example `helper` or `sftp`.",
                },
                "session_id": {
                    "display_name": "Session ID",
                    "short_desc": "Optional SSH session id for the submission",
                    "type": StringOrNothingType,
                    "desc": "Optional SSH session id associated with the inbound submission.",
                },
                "server_name": {
                    "display_name": "Server Name",
                    "short_desc": "Optional server name for the submission",
                    "type": StringOrNothingType,
                    "desc": "Optional server name associated with the inbound submission.",
                },
                "listener_name": {
                    "display_name": "Listener Name",
                    "short_desc": "Optional listener name for the submission",
                    "type": StringOrNothingType,
                    "desc": "Optional listener name associated with the inbound submission.",
                },
                "principal": {
                    "display_name": "Principal",
                    "short_desc": "Optional principal for the submission",
                    "type": StringOrNothingType,
                    "desc": "Optional authenticated principal associated with the inbound submission.",
                },
                "accepted": {
                    "display_name": "Accepted",
                    "short_desc": "Whether the inbound submission was accepted",
                    "type": BoolType,
                    "desc": "`True` when the inbound submission was accepted.",
                    "default_value": True,
                },
                "reason_code": {
                    "display_name": "Reason Code",
                    "short_desc": "Optional typed rejection reason code",
                    "type": StringOrNothingType,
                    "desc": "Optional typed rejection reason code for denied inbound submissions.",
                },
                "reason_desc": {
                    "display_name": "Reason Detail",
                    "short_desc": "Optional human-readable rejection detail",
                    "type": StringOrNothingType,
                    "desc": "Optional human-readable rejection detail for denied inbound submissions.",
                },
                "checksum": {
                    "display_name": "Checksum",
                    "short_desc": "Optional checksum for accepted submissions",
                    "type": StringOrNothingType,
                    "desc": "Optional checksum for accepted inbound submissions.",
                },
                "checksum_algorithm": {
                    "display_name": "Checksum Algorithm",
                    "short_desc": "Optional checksum algorithm for submissions",
                    "type": StringOrNothingType,
                    "desc": "Optional checksum algorithm for accepted inbound submissions.",
                },
                "transfer_info": {
                    "display_name": "Transfer Info",
                    "short_desc": "Optional transfer info for the submission",
                    "type": AutoHashOrNothingType,
                    "desc": "Optional transfer info associated with the submission.  When present "
                        "it has the structure of `SftpServerTransferInfoDataType` (mirroring "
                        "`Qore::Ssh::SftpTransferInfo`): `operation`, `path`, `temporary_path`, "
                        "`final_path`, `size`, `checksum`, `atomic_publish`, `completed`.",
                },
            };
        }

        constructor() : HashDataType("SftpServerInboundEventInfo") {
            addQoreFields(Fields);
        }
    }

    public class SftpServerOutboundEventInfoDataType inherits HashDataType {
        public {
            const Fields = {
                "event_type": {
                    "display_name": "Event Type",
                    "short_desc": "The emitted outbound completion event type",
                    "type": StringType,
                    "desc": "The emitted outbound completion event type.",
                },
                "queue": {
                    "display_name": "Queue",
                    "short_desc": "The logical exchange queue name",
                    "type": StringType,
                    "desc": "The logical exchange queue name.",
                    "default_value": "outbound",
                },
                "name": {
                    "display_name": "Entry Name",
                    "short_desc": "The original outbound entry name",
                    "type": StringType,
                    "desc": "The original outbound entry name.",
                },
                "path": {
                    "display_name": "Path",
                    "short_desc": "The relevant outbound completion path",
                    "type": StringType,
                    "desc": "The relevant outbound completion path.",
                },
                "size": {
                    "display_name": "Size",
                    "short_desc": "The outbound payload size before completion",
                    "type": IntType,
                    "desc": "The outbound payload size in bytes before completion.",
                    "default_value": 0,
                },
                "metadata": {
                    "display_name": "Metadata",
                    "short_desc": "Free-form metadata for the outbound entry",
                    "type": AutoHashType,
                    "desc": "Free-form metadata associated with the outbound entry.",
                    "default_value": {},
                },
                "completed_at": {
                    "display_name": "Completed At",
                    "short_desc": "When the completion event was emitted",
                    "type": DateType,
                    "desc": "When the completion event was emitted.",
                },
                "source": {
                    "display_name": "Source",
                    "short_desc": "The source of the completion event",
                    "type": StringOrNothingType,
                    "desc": "The source of the completion event, for example `helper` or `sftp`.",
                },
                "session_id": {
                    "display_name": "Session ID",
                    "short_desc": "Optional SSH session id for the completion",
                    "type": StringOrNothingType,
                    "desc": "Optional SSH session id associated with the completion event.",
                },
                "server_name": {
                    "display_name": "Server Name",
                    "short_desc": "Optional server name for the completion",
                    "type": StringOrNothingType,
                    "desc": "Optional server name associated with the completion event.",
                },
                "listener_name": {
                    "display_name": "Listener Name",
                    "short_desc": "Optional listener name for the completion",
                    "type": StringOrNothingType,
                    "desc": "Optional listener name associated with the completion event.",
                },
                "principal": {
                    "display_name": "Principal",
                    "short_desc": "Optional principal for the completion",
                    "type": StringOrNothingType,
                    "desc": "Optional authenticated principal associated with the completion event.",
                },
                "final_name": {
                    "display_name": "Final Name",
                    "short_desc": "Optional final entry name after completion",
                    "type": StringOrNothingType,
                    "desc": "Optional final outbound entry name after `archive` or `claim` completion.",
                },
                "operation": {
                    "display_name": "Operation",
                    "short_desc": "The completed outbound operation",
                    "type": StringOrNothingType,
                    "desc": "The completed outbound operation, for example `claim`, `archive`, or "
                        "`delete`.",
                },
                "reason_code": {
                    "display_name": "Reason Code",
                    "short_desc": "Reserved typed reason code",
                    "type": StringOrNothingType,
                    "desc": "Reserved typed reason code field for future outbound rejection/denial "
                        "reporting.",
                },
                "reason_desc": {
                    "display_name": "Reason Detail",
                    "short_desc": "Reserved human-readable reason detail",
                    "type": StringOrNothingType,
                    "desc": "Reserved human-readable reason detail for future outbound "
                        "rejection/denial reporting.",
                },
                "checksum": {
                    "display_name": "Checksum",
                    "short_desc": "Optional checksum for the completed payload",
                    "type": StringOrNothingType,
                    "desc": "Optional checksum for the completed outbound payload.",
                },
                "checksum_algorithm": {
                    "display_name": "Checksum Algorithm",
                    "short_desc": "Optional checksum algorithm for the payload",
                    "type": StringOrNothingType,
                    "desc": "Optional checksum algorithm for the completed outbound payload.",
                },
                "transfer_info": {
                    "display_name": "Transfer Info",
                    "short_desc": "Optional transfer info for the completion",
                    "type": AutoHashOrNothingType,
                    "desc": "Optional transfer info associated with the outbound completion.  When "
                        "present it has the structure of `SftpServerTransferInfoDataType` "
                        "(mirroring `Qore::Ssh::SftpTransferInfo`): `operation`, `path`, "
                        "`temporary_path`, `final_path`, `size`, `checksum`, `atomic_publish`, "
                        "`completed`.",
                },
            };
        }

        constructor() : HashDataType("SftpServerOutboundEventInfo") {
            addQoreFields(Fields);
        }
    }

    public class SftpServerRetentionCleanupResultDataType inherits HashDataType {
        public {
            const Fields = {
                "queue": {
                    "display_name": "Queue",
                    "short_desc": "The cleaned retention queue",
                    "type": StringType,
                    "desc": "The cleaned retention queue.",
                },
                "evaluated_at": {
                    "display_name": "Evaluated At",
                    "short_desc": "The time used to evaluate retention expiration",
                    "type": DateType,
                    "desc": "The time used when evaluating retention expiration.",
                },
                "principal": {
                    "display_name": "Principal",
                    "short_desc": "Optional principal used to scope cleanup",
                    "type": StringOrNothingType,
                    "desc": "Optional authenticated principal used to scope retention cleanup.",
                },
                "removed_count": {
                    "display_name": "Removed Count",
                    "short_desc": "The number of expired files removed",
                    "type": IntType,
                    "desc": "The number of expired files removed.",
                },
                "removed_paths": {
                    "display_name": "Removed Paths",
                    "short_desc": "The removed expired file paths",
                    "type": new SoftListDataType("SftpServerRetentionRemovedPathList", StringType),
                    "desc": "The removed expired file paths.",
                },
                "removed_directories": {
                    "display_name": "Removed Directories",
                    "short_desc": "The removed empty directory paths",
                    "type": new SoftListDataType("SftpServerRetentionRemovedDirectoryList", StringType),
                    "desc": "The removed empty directory paths.",
                },
            };
        }

        constructor() : HashDataType("SftpServerRetentionCleanupResult") {
            addQoreFields(Fields);
        }
    }

    public class SftpServerListResponseDataType inherits HashDataType {
        public {
            const Fields = {
                "records": {
                    "display_name": "Records",
                    "short_desc": "The currently available outbound records",
                    "type": new SoftListDataType("SftpServerRecordInfoList", new SftpServerRecordInfoDataType()),
                    "desc": "The currently available outbound records.",
                },
            };
        }

        constructor() : HashDataType("SftpServerListResponse") {
            addQoreFields(Fields);
        }
    }

    public const SftpServerRecordResponseDataType = new SftpServerRecordInfoDataType();
    public const SftpServerListResponseDataType = new SftpServerListResponseDataType();
    public const SftpServerSubmitResponseDataType = SftpServerRecordResponseDataType;
    public const SftpServerInboundEventInfoDataType = new SftpServerInboundEventInfoDataType();
    public const SftpServerOutboundEventInfoDataType = new SftpServerOutboundEventInfoDataType();
    public const SftpServerRetentionCleanupResponseDataType = new SftpServerRetentionCleanupResultDataType();
}
