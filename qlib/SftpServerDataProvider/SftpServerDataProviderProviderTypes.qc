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
    public class SftpServerSubmitInboundRequestDataType inherits HashDataType {
        public {
            const Fields = {
                "name": {
                    "type": StringType,
                    "desc": "The inbound exchange entry name",
                },
                "data": {
                    "type": BinaryType,
                    "desc": "The binary payload to submit",
                },
                "metadata": {
                    "type": AutoHashOrNothingType,
                    "desc": "Optional free-form metadata to associate with the entry",
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
                    "type": StringType,
                    "desc": "The exchange entry name",
                },
                "metadata": {
                    "type": AutoHashOrNothingType,
                    "desc": "Optional free-form metadata for the operation",
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
                    "type": StringOrNothingType,
                    "desc": "Optional final entry name for claim or archive operations",
                },
                "completion_mode": {
                    "type": StringOrNothingType,
                    "desc": "Optional typed completion mode; one of `claim`, `archive`, or `delete`",
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
                    "type": StringType,
                    "desc": "The retention queue to clean; one of `inbound`, `archive`, or `claim`",
                },
                "now_s": {
                    "type": IntOrNothingType,
                    "desc": "Optional deterministic evaluation time as a Unix timestamp",
                },
                "principal": {
                    "type": StringOrNothingType,
                    "desc": "Optional authenticated principal to scope retention cleanup",
                },
                "remove_empty_directories": {
                    "type": BoolOrNothingType,
                    "desc": "Whether empty directories should be removed after expired files are deleted",
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
                    "type": StringType,
                    "desc": "The logical exchange queue name",
                },
                "name": {
                    "type": StringType,
                    "desc": "The original exchange entry name",
                },
                "path": {
                    "type": StringOrNothingType,
                    "desc": "The virtual exchange path for the entry, if any",
                },
                "size": {
                    "type": IntType,
                    "desc": "The payload size in bytes",
                    "default_value": 0,
                },
                "checksum": {
                    "type": StringOrNothingType,
                    "desc": "Optional checksum for the record payload",
                },
                "checksum_algorithm": {
                    "type": StringOrNothingType,
                    "desc": "Optional checksum algorithm for the record payload",
                },
                "metadata": {
                    "type": AutoHashType,
                    "desc": "Free-form entry metadata",
                    "default_value": {},
                },
                "data": {
                    "type": BinaryOrNothingType,
                    "desc": "The payload for retrieve operations",
                },
                "final_name": {
                    "type": StringOrNothingType,
                    "desc": "The final entry name after claim or archive completion",
                },
                "operation": {
                    "type": StringOrNothingType,
                    "desc": "The completed operation name, if any",
                },
                "completed": {
                    "type": BoolType,
                    "desc": "Whether the operation completed a state transition",
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
                    "type": StringType,
                    "desc": "The emitted inbound event type",
                    "default_value": EventInboundFileAccepted,
                },
                "queue": {
                    "type": StringType,
                    "desc": "The logical exchange queue name",
                    "default_value": "inbound",
                },
                "name": {
                    "type": StringType,
                    "desc": "The submitted inbound entry name",
                },
                "path": {
                    "type": StringType,
                    "desc": "The virtual inbound path for the submitted entry",
                },
                "size": {
                    "type": IntType,
                    "desc": "The submitted payload size in bytes",
                },
                "metadata": {
                    "type": AutoHashType,
                    "desc": "Free-form metadata associated with the submitted entry",
                    "default_value": {},
                },
                "data": {
                    "type": BinaryOrNothingType,
                    "desc": "The submitted payload when available",
                },
                "submitted_at": {
                    "type": IntType,
                    "desc": "Unix timestamp when the submission event was emitted",
                },
                "source": {
                    "type": StringOrNothingType,
                    "desc": "The source of the submission event, for example `helper` or `sftp`",
                },
                "session_id": {
                    "type": StringOrNothingType,
                    "desc": "Optional SSH session id associated with the inbound submission",
                },
                "server_name": {
                    "type": StringOrNothingType,
                    "desc": "Optional server name associated with the inbound submission",
                },
                "listener_name": {
                    "type": StringOrNothingType,
                    "desc": "Optional listener name associated with the inbound submission",
                },
                "principal": {
                    "type": StringOrNothingType,
                    "desc": "Optional authenticated principal associated with the inbound submission",
                },
                "accepted": {
                    "type": BoolType,
                    "desc": "True when the inbound submission was accepted",
                    "default_value": True,
                },
                "reason_code": {
                    "type": StringOrNothingType,
                    "desc": "Optional typed rejection reason code for denied inbound submissions",
                },
                "reason_desc": {
                    "type": StringOrNothingType,
                    "desc": "Optional human-readable rejection detail for denied inbound submissions",
                },
                "checksum": {
                    "type": StringOrNothingType,
                    "desc": "Optional checksum for accepted inbound submissions",
                },
                "checksum_algorithm": {
                    "type": StringOrNothingType,
                    "desc": "Optional checksum algorithm for accepted inbound submissions",
                },
                "transfer_info": {
                    "type": AutoHashOrNothingType,
                    "desc": "Optional transfer info associated with the submission",
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
                    "type": StringType,
                    "desc": "The emitted outbound completion event type",
                },
                "queue": {
                    "type": StringType,
                    "desc": "The logical exchange queue name",
                    "default_value": "outbound",
                },
                "name": {
                    "type": StringType,
                    "desc": "The original outbound entry name",
                },
                "path": {
                    "type": StringType,
                    "desc": "The relevant outbound completion path",
                },
                "size": {
                    "type": IntType,
                    "desc": "The outbound payload size in bytes before completion",
                    "default_value": 0,
                },
                "metadata": {
                    "type": AutoHashType,
                    "desc": "Free-form metadata associated with the outbound entry",
                    "default_value": {},
                },
                "completed_at": {
                    "type": IntType,
                    "desc": "Unix timestamp when the completion event was emitted",
                },
                "source": {
                    "type": StringOrNothingType,
                    "desc": "The source of the completion event, for example `helper` or `sftp`",
                },
                "session_id": {
                    "type": StringOrNothingType,
                    "desc": "Optional SSH session id associated with the completion event",
                },
                "server_name": {
                    "type": StringOrNothingType,
                    "desc": "Optional server name associated with the completion event",
                },
                "listener_name": {
                    "type": StringOrNothingType,
                    "desc": "Optional listener name associated with the completion event",
                },
                "principal": {
                    "type": StringOrNothingType,
                    "desc": "Optional authenticated principal associated with the completion event",
                },
                "final_name": {
                    "type": StringOrNothingType,
                    "desc": "Optional final outbound entry name after archive or claim completion",
                },
                "operation": {
                    "type": StringOrNothingType,
                    "desc": "The completed outbound operation, for example `claim`, `archive`, or `delete`",
                },
                "reason_code": {
                    "type": StringOrNothingType,
                    "desc": "Reserved typed reason code field for future outbound rejection/denial reporting",
                },
                "reason_desc": {
                    "type": StringOrNothingType,
                    "desc": "Reserved human-readable reason detail for future outbound rejection/denial reporting",
                },
                "checksum": {
                    "type": StringOrNothingType,
                    "desc": "Optional checksum for the completed outbound payload",
                },
                "checksum_algorithm": {
                    "type": StringOrNothingType,
                    "desc": "Optional checksum algorithm for the completed outbound payload",
                },
                "transfer_info": {
                    "type": AutoHashOrNothingType,
                    "desc": "Optional transfer info associated with the outbound completion",
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
                    "type": StringType,
                    "desc": "The cleaned retention queue",
                },
                "evaluated_at": {
                    "type": IntType,
                    "desc": "Unix timestamp used when evaluating retention expiration",
                },
                "principal": {
                    "type": StringOrNothingType,
                    "desc": "Optional authenticated principal used to scope retention cleanup",
                },
                "removed_count": {
                    "type": IntType,
                    "desc": "The number of expired files removed",
                },
                "removed_paths": {
                    "type": new SoftListDataType("SftpServerRetentionRemovedPathList", StringType),
                    "desc": "The removed expired file paths",
                },
                "removed_directories": {
                    "type": new SoftListDataType("SftpServerRetentionRemovedDirectoryList", StringType),
                    "desc": "The removed empty directory paths",
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
                    "type": new SoftListDataType("SftpServerRecordInfoList", new SftpServerRecordInfoDataType()),
                    "desc": "The currently available outbound records",
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
