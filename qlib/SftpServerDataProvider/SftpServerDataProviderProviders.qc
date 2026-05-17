# -*- mode: qore; indent-tabs-mode: nil -*-
#! SftpServerDataProvider DataProvider-specific providers and actions

/*  SftpServerDataProviderProviders.qc Copyright 2026 Qore Technologies, s.r.o.

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
    # DP3: the underlying virtual SFTP exchange uses Unix epoch seconds for timestamps, but
    # the DataProvider schema surfaces date types so the UI renders date pickers.  These
    # helpers convert at the provider boundary; the int contract with the exchange backend is
    # unchanged.
    #! converts the named Unix-epoch-second int keys of a hash to @ref date "date" values
    public hash<auto> sub sftpServerEpochKeysToDate(hash<auto> h, softlist<string> field_names) {
        # cast to an untyped hash so a hashdecl int member can be replaced with a date value
        # (a plain copy preserves the source hashdecl's per-member int typing)
        hash<auto> rv = cast<hash>(h);
        foreach string fk in (field_names) {
            if (rv{fk}.typeCode() == NT_INT) {
                rv{fk} = 1970-01-01Z + seconds(rv{fk});
            }
        }
        return rv;
    }

    #! converts an optional @ref date "date" to Unix epoch seconds (NOTHING passes through)
    public *int sub sftpServerDateToEpoch(auto v) {
        return v.typeCode() == NT_DATE ? get_epoch_seconds(v) : v;
    }

    public class SftpServerDataProviderFactory inherits AbstractDataProviderFactory {
        private {
            static Class cls = new Class("SftpServerDataProvider");
            const FactoryInfo = <DataProviderFactoryInfo>{
                "name": FactoryName,
                "desc": "virtual SFTP server exchange data provider factory",
                "children_can_support_apis": True,
                "children_can_support_observers": True,
            };
        }

        private hash<DataProviderFactoryInfo> getInfoImpl() {
            return FactoryInfo;
        }

        private hash<DataProviderInfo> getProviderInfoImpl() {
            return SftpServerDataProvider::ProviderInfo;
        }

        private Class getClassImpl() {
            return cls;
        }
    }

    public const ConstructorOptions = {
        "backend": <DataProviderOptionInfo>{
            "display_name": "Virtual Exchange Backend",
            "short_desc": "Existing virtual exchange or record-store backend object",
            "type": AbstractDataProviderTypeMap."any",
            "desc": "Optional existing `VirtualSftpExchangeRecordStore` or `VirtualSftpExchange` object to use as "
                "the provider backend.",
        },
        "inbound_dir": <DataProviderOptionInfo>{
            "display_name": "Inbound Directory",
            "short_desc": "Virtual inbound exchange directory",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional virtual inbound exchange directory when creating a backend from constructor options.",
        },
        "outbound_dir": <DataProviderOptionInfo>{
            "display_name": "Outbound Directory",
            "short_desc": "Virtual outbound exchange directory",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional virtual outbound exchange directory when creating a backend from constructor options.",
        },
        "archive_dir": <DataProviderOptionInfo>{
            "display_name": "Archive Directory",
            "short_desc": "Virtual archive directory for completed outbound files",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional virtual archive directory when creating a backend from constructor options.",
        },
        "claim_dir": <DataProviderOptionInfo>{
            "display_name": "Claim Directory",
            "short_desc": "Virtual claim directory for claimed outbound files",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional virtual claim directory when creating a backend from constructor options.",
        },
        "inbound_policy": <DataProviderOptionInfo>{
            "display_name": "Inbound File Policy",
            "short_desc": "Typed policy for accepting inbound SFTP files",
            "type": AbstractDataProviderTypeMap."hash",
            "desc": "Optional typed inbound-file acceptance policy when creating a backend from constructor options. "
                "Supported keys include `accept_filename_glob`, `reject_filename_glob`, "
                "`accept_filename_regex`, `reject_filename_regex`, `min_size`, `max_size`, "
                "`max_file_count`, `max_total_bytes`, `max_concurrent_uploads`, "
                "`allow_overwrite`, `reject_duplicate_name`, `reject_duplicate_size`, "
                "`reject_duplicate_hash`, `accept_content_prefix`, `reject_content_prefix`, "
                "`accept_content_type_hints`, `reject_content_type_hints`, `validation_callback`, "
                "`allow_hidden_files`, "
                "`allow_principals`, `deny_principals`, `principal_policies`, "
                "`directory_policies`, "
                "and `principal_routes`.",
        },
        "inbound_retention_policy": <DataProviderOptionInfo>{
            "display_name": "Inbound Retention Policy",
            "short_desc": "Retention metadata and cleanup policy for inbound files",
            "type": AbstractDataProviderTypeMap."hash",
            "desc": "Optional typed retention policy for inbound files. Supported keys currently include "
                "`max_age_seconds`.",
        },
        "archive_retention_policy": <DataProviderOptionInfo>{
            "display_name": "Archive Retention Policy",
            "short_desc": "Retention metadata and cleanup policy for archived outbound files",
            "type": AbstractDataProviderTypeMap."hash",
            "desc": "Optional typed retention policy for archive files. Supported keys currently include "
                "`max_age_seconds`.",
        },
        "claim_retention_policy": <DataProviderOptionInfo>{
            "display_name": "Claim Retention Policy",
            "short_desc": "Retention metadata and cleanup policy for claimed outbound files",
            "type": AbstractDataProviderTypeMap."hash",
            "desc": "Optional typed retention policy for claim files. Supported keys currently include "
                "`max_age_seconds`.",
        },
        "inbound_event_payload_mode": <DataProviderOptionInfo>{
            "display_name": "Inbound Event Payload Mode",
            "short_desc": "Control whether inbound events include payload data",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional typed payload mode for inbound submission events.\n\n"
                "- `none` -- inbound events carry no payload data (the default)\n"
                "- `inline` -- inbound events include the submitted payload",
            "allowed_values": (
                <AllowedValueInfo>{"value": InboundEventPayloadNone, "display_name": "None"},
                <AllowedValueInfo>{"value": InboundEventPayloadInline, "display_name": "Inline"},
            ),
        },
        "generate_inbound_checksum": <DataProviderOptionInfo>{
            "display_name": "Generate Inbound Checksum",
            "short_desc": "Generate SHA-256 checksums for accepted inbound files",
            "type": AbstractDataProviderTypeMap."bool",
            "desc": "Optional flag controlling whether accepted inbound helper/provider/live uploads generate a "
                "typed SHA-256 checksum in results and events and persist that checksum in virtual file metadata "
                "for later stat/list/retrieve flows.",
        },
        "default_file_permissions": <DataProviderOptionInfo>{
            "display_name": "Default File Permissions",
            "short_desc": "Default permissions for created virtual files",
            "type": AbstractDataProviderTypeMap."int",
            "desc": "Optional default virtual file permissions for new backend instances.",
        },
        "default_directory_permissions": <DataProviderOptionInfo>{
            "display_name": "Default Directory Permissions",
            "short_desc": "Default permissions for created virtual directories",
            "type": AbstractDataProviderTypeMap."int",
            "desc": "Optional default virtual directory permissions for new backend instances.",
        },
        "logger": <DataProviderOptionInfo>{
            "display_name": "Logger",
            "short_desc": "Optional logger for helper and provider events",
            "type": AbstractDataProviderTypeMap."any",
            "desc": "Optional `LoggerInterface` object inherited by the virtual backend and child providers.",
        },
    };

    public const ConstructorActionOptions = {
        "backend": <ActionOptionInfo>{
            "display_name": "Virtual Exchange Backend",
            "short_desc": "Existing virtual exchange or record-store backend object",
            "type": AbstractDataProviderTypeMap."any",
            "desc": "Optional existing `VirtualSftpExchangeRecordStore` or `VirtualSftpExchange` object to use as "
                "the provider backend.",
            "loc": "constructor",
        },
        "inbound_dir": <ActionOptionInfo>{
            "display_name": "Inbound Directory",
            "short_desc": "Virtual inbound exchange directory",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional virtual inbound exchange directory when creating a backend from constructor options.",
            "loc": "constructor",
        },
        "outbound_dir": <ActionOptionInfo>{
            "display_name": "Outbound Directory",
            "short_desc": "Virtual outbound exchange directory",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional virtual outbound exchange directory when creating a backend from constructor options.",
            "loc": "constructor",
        },
        "archive_dir": <ActionOptionInfo>{
            "display_name": "Archive Directory",
            "short_desc": "Virtual archive directory for completed outbound files",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional virtual archive directory when creating a backend from constructor options.",
            "loc": "constructor",
        },
        "claim_dir": <ActionOptionInfo>{
            "display_name": "Claim Directory",
            "short_desc": "Virtual claim directory for claimed outbound files",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional virtual claim directory when creating a backend from constructor options.",
            "loc": "constructor",
        },
        "inbound_policy": <ActionOptionInfo>{
            "display_name": "Inbound File Policy",
            "short_desc": "Typed policy for accepting inbound SFTP files",
            "type": AbstractDataProviderTypeMap."hash",
            "desc": "Optional typed inbound-file acceptance policy when creating a backend from constructor options. "
                "Supported keys include `accept_filename_glob`, `reject_filename_glob`, "
                "`accept_filename_regex`, `reject_filename_regex`, `min_size`, `max_size`, "
                "`max_file_count`, `max_total_bytes`, `max_concurrent_uploads`, "
                "`allow_overwrite`, `reject_duplicate_name`, "
                "`reject_duplicate_size`, `reject_duplicate_hash`, "
                "`accept_content_prefix`, `reject_content_prefix`, "
                "`accept_content_type_hints`, `reject_content_type_hints`, `validation_callback`, "
                "`allow_hidden_files`, "
                "`allow_principals`, `deny_principals`, `principal_policies`, `directory_policies`, "
                "and `principal_routes`.",
            "loc": "constructor",
        },
        "inbound_retention_policy": <ActionOptionInfo>{
            "display_name": "Inbound Retention Policy",
            "short_desc": "Retention metadata and cleanup policy for inbound files",
            "type": AbstractDataProviderTypeMap."hash",
            "desc": "Optional typed retention policy for inbound files. Supported keys currently include "
                "`max_age_seconds`.",
            "loc": "constructor",
        },
        "archive_retention_policy": <ActionOptionInfo>{
            "display_name": "Archive Retention Policy",
            "short_desc": "Retention metadata and cleanup policy for archived outbound files",
            "type": AbstractDataProviderTypeMap."hash",
            "desc": "Optional typed retention policy for archive files. Supported keys currently include "
                "`max_age_seconds`.",
            "loc": "constructor",
        },
        "claim_retention_policy": <ActionOptionInfo>{
            "display_name": "Claim Retention Policy",
            "short_desc": "Retention metadata and cleanup policy for claimed outbound files",
            "type": AbstractDataProviderTypeMap."hash",
            "desc": "Optional typed retention policy for claim files. Supported keys currently include "
                "`max_age_seconds`.",
            "loc": "constructor",
        },
        "inbound_event_payload_mode": <ActionOptionInfo>{
            "display_name": "Inbound Event Payload Mode",
            "short_desc": "Control whether inbound events include payload data",
            "type": AbstractDataProviderTypeMap."string",
            "desc": "Optional typed payload mode for inbound submission events.\n\n"
                "- `none` -- inbound events carry no payload data (the default)\n"
                "- `inline` -- inbound events include the submitted payload",
            "allowed_values": (
                <AllowedValueInfo>{"value": InboundEventPayloadNone, "display_name": "None"},
                <AllowedValueInfo>{"value": InboundEventPayloadInline, "display_name": "Inline"},
            ),
            "loc": "constructor",
        },
        "generate_inbound_checksum": <ActionOptionInfo>{
            "display_name": "Generate Inbound Checksum",
            "short_desc": "Generate SHA-256 checksums for accepted inbound files",
            "type": AbstractDataProviderTypeMap."bool",
            "desc": "Optional flag controlling whether accepted inbound helper/provider/live uploads generate a "
                "typed SHA-256 checksum in results and events and persist that checksum in virtual file metadata "
                "for later stat/list/retrieve flows.",
            "loc": "constructor",
        },
        "default_file_permissions": <ActionOptionInfo>{
            "display_name": "Default File Permissions",
            "short_desc": "Default permissions for created virtual files",
            "type": AbstractDataProviderTypeMap."int",
            "desc": "Optional default virtual file permissions for new backend instances.",
            "loc": "constructor",
        },
        "default_directory_permissions": <ActionOptionInfo>{
            "display_name": "Default Directory Permissions",
            "short_desc": "Default permissions for created virtual directories",
            "type": AbstractDataProviderTypeMap."int",
            "desc": "Optional default virtual directory permissions for new backend instances.",
            "loc": "constructor",
        },
        "logger": <ActionOptionInfo>{
            "display_name": "Logger",
            "short_desc": "Optional logger for helper and provider events",
            "type": AbstractDataProviderTypeMap."any",
            "desc": "Optional `LoggerInterface` object inherited by the virtual backend and child providers.",
            "loc": "constructor",
        },
    };

    public const ProviderInfo = <DataProviderInfo>{
        "type": "SftpServerDataProvider",
        "constructor_options": ConstructorOptions,
        "supports_children": True,
        "children_can_support_apis": True,
        "children_can_support_observers": True,
    };

    public class SftpServerDataProviderBase inherits AbstractDataProvider {
        public {
            VirtualSftpExchangeRecordStore store;
        }

        constructor(*hash<auto> options) {
            checkOptions("CONSTRUCTOR-ERROR", ConstructorOptions, options);
            store = createRecordStore(options);
        }

        constructor(VirtualSftpExchangeRecordStore store) {
            self.store = store;
        }

        constructor(VirtualSftpExchange exchange) {
            store = new VirtualSftpExchangeRecordStore(exchange);
        }

        VirtualSftpExchangeRecordStore getRecordStore() {
            return store;
        }

        VirtualSftpExchange getExchange() {
            return store.getExchange();
        }

        private static VirtualSftpExchangeRecordStore createRecordStore(*hash<auto> options) {
            if (!options || !options.backend) {
                return new VirtualSftpExchangeRecordStore(makeExchangeOptions(options));
            }

            auto backend = options.backend;
            string backend_class = backend.className();
            if (backend_class == "SftpServerDataProvider::VirtualSftpExchangeRecordStore"
                    || backend_class == "VirtualSftpExchangeRecordStore") {
                return cast<VirtualSftpExchangeRecordStore>(backend);
            }
            if (backend_class == "SftpServerDataProvider::VirtualSftpExchange"
                    || backend_class == "VirtualSftpExchange") {
                return new VirtualSftpExchangeRecordStore(cast<VirtualSftpExchange>(backend));
            }

            throw "CONSTRUCTOR-ERROR",
                sprintf("unsupported virtual exchange backend class %y; expected %y or %y",
                    backend_class, "VirtualSftpExchangeRecordStore", "VirtualSftpExchange");
        }

        private static *hash<VirtualSftpExchangeOptions> makeExchangeOptions(*hash<auto> options) {
            if (!options) {
                return NOTHING;
            }
            hash<VirtualSftpExchangeOptions> rv = <VirtualSftpExchangeOptions>{};
            foreach string key in (("inbound_dir", "outbound_dir", "archive_dir", "claim_dir",
                    "default_file_permissions", "default_directory_permissions", "logger",
                    "inbound_retention_policy", "archive_retention_policy", "claim_retention_policy",
                    "inbound_event_payload_mode", "generate_inbound_checksum")) {
                if (options.hasKey(key)) {
                    rv{key} = options{key};
                }
            }
            if (options.hasKey("inbound_policy") && options.inbound_policy != NOTHING) {
                rv.inbound_policy = cast<hash<VirtualSftpInboundPolicy>>(options.inbound_policy);
            }
            if (options.hasKey("inbound_retention_policy") && options.inbound_retention_policy != NOTHING) {
                rv.inbound_retention_policy
                    = cast<hash<VirtualSftpRetentionPolicy>>(options.inbound_retention_policy);
            }
            if (options.hasKey("archive_retention_policy") && options.archive_retention_policy != NOTHING) {
                rv.archive_retention_policy
                    = cast<hash<VirtualSftpRetentionPolicy>>(options.archive_retention_policy);
            }
            if (options.hasKey("claim_retention_policy") && options.claim_retention_policy != NOTHING) {
                rv.claim_retention_policy
                    = cast<hash<VirtualSftpRetentionPolicy>>(options.claim_retention_policy);
            }
            return rv.empty() ? NOTHING : rv;
        }
    }

    public class SftpServerDataProvider inherits SftpServerDataProviderBase {
        public {
            const ProviderInfo = SftpServerDataProvider::ProviderInfo;
        }

        private {
            const ChildMap = {
                "submit-inbound": Class::forName("SftpServerDataProvider::SftpServerSubmitInboundDataProvider"),
                "list-outbound": Class::forName("SftpServerDataProvider::SftpServerListOutboundDataProvider"),
                "retrieve-outbound": Class::forName("SftpServerDataProvider::SftpServerRetrieveOutboundDataProvider"),
                "claim-outbound": Class::forName("SftpServerDataProvider::SftpServerClaimOutboundDataProvider"),
                "archive-outbound": Class::forName("SftpServerDataProvider::SftpServerArchiveOutboundDataProvider"),
                "delete-outbound": Class::forName("SftpServerDataProvider::SftpServerDeleteOutboundDataProvider"),
                "cleanup-expired": Class::forName("SftpServerDataProvider::SftpServerCleanupExpiredDataProvider"),
                EventInboundFileAccepted: Class::forName(
                    "SftpServerDataProvider::SftpServerInboundAcceptedEventDataProvider"),
                EventInboundFileRejected: Class::forName(
                    "SftpServerDataProvider::SftpServerInboundAcceptedEventDataProvider"),
                EventOutboundFileClaimed: Class::forName(
                    "SftpServerDataProvider::SftpServerOutboundClaimedEventDataProvider"),
                EventOutboundFileArchived: Class::forName(
                    "SftpServerDataProvider::SftpServerOutboundArchivedEventDataProvider"),
                EventOutboundFileDeleted: Class::forName(
                    "SftpServerDataProvider::SftpServerOutboundDeletedEventDataProvider"),
            };
        }

        constructor(*hash<auto> options) : SftpServerDataProviderBase(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerDataProviderBase(store) {
        }

        string getName() {
            return FactoryName;
        }

        *string getDesc() {
            return "Generic virtual SFTP exchange data provider";
        }

        private *list<string> getChildProviderNamesImpl() {
            return keys ChildMap;
        }

        private *AbstractDataProvider getChildProviderImpl(string name) {
            *Class cls = ChildMap{name};
            if (!cls) {
                return NOTHING;
            }
            return cls.newObject(store);
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerRecordStoreActionDataProvider inherits SftpServerDataProviderBase {
        constructor(*hash<auto> options) : SftpServerDataProviderBase(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerDataProviderBase(store) {
        }
    }

    public class SftpServerSubmitInboundDataProvider inherits SftpServerRecordStoreActionDataProvider {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": "submit-inbound",
                "desc": "Submit inbound file data to a virtual SFTP exchange",
                "type": "SftpServerSubmitInboundDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_request": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
            const RequestType = new SftpServerSubmitInboundRequestDataType();
            const ResponseType = SftpServerSubmitResponseDataType;
        }

        constructor(*hash<auto> options) : SftpServerRecordStoreActionDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerRecordStoreActionDataProvider(store) {
        }

        string getName() {
            return "submit-inbound";
        }

        private auto doRequestImpl(auto req, *hash<auto> request_options) {
            return store.submitInboundRecord(cast<hash<VirtualSftpRecordSubmissionRequest>>(req));
        }

        private *AbstractDataProviderType getRequestTypeImpl() {
            return RequestType;
        }

        private *AbstractDataProviderType getResponseTypeImpl() {
            return ResponseType;
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerListOutboundDataProvider inherits SftpServerRecordStoreActionDataProvider {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": "list-outbound",
                "desc": "List outbound exchange entries from a virtual SFTP exchange",
                "type": "SftpServerListOutboundDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_request": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
            const ResponseType = SftpServerListResponseDataType;
        }

        constructor(*hash<auto> options) : SftpServerRecordStoreActionDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerRecordStoreActionDataProvider(store) {
        }

        string getName() {
            return "list-outbound";
        }

        private auto doRequestImpl(auto req, *hash<auto> request_options) {
            return {
                "records": store.listOutboundRecords(),
            };
        }

        private *AbstractDataProviderType getRequestTypeImpl() {
            return NOTHING;
        }

        private *AbstractDataProviderType getResponseTypeImpl() {
            return ResponseType;
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerRetrieveOutboundDataProvider inherits SftpServerRecordStoreActionDataProvider {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": "retrieve-outbound",
                "desc": "Retrieve outbound exchange data from a virtual SFTP exchange",
                "type": "SftpServerRetrieveOutboundDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_request": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
            const RequestType = new SftpServerRecordRequestDataType();
            const ResponseType = SftpServerRecordResponseDataType;
        }

        constructor(*hash<auto> options) : SftpServerRecordStoreActionDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerRecordStoreActionDataProvider(store) {
        }

        string getName() {
            return "retrieve-outbound";
        }

        private auto doRequestImpl(auto req, *hash<auto> request_options) {
            return store.retrieveOutboundRecord(cast<hash<VirtualSftpRecordRequest>>(req));
        }

        private *AbstractDataProviderType getRequestTypeImpl() {
            return RequestType;
        }

        private *AbstractDataProviderType getResponseTypeImpl() {
            return ResponseType;
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerCompleteOutboundDataProvider inherits SftpServerRecordStoreActionDataProvider {
        constructor(*hash<auto> options) : SftpServerRecordStoreActionDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerRecordStoreActionDataProvider(store) {
        }

        private *AbstractDataProviderType getRequestTypeImpl() {
            return new SftpServerRecordCompletionRequestDataType();
        }

        private *AbstractDataProviderType getResponseTypeImpl() {
            return SftpServerRecordResponseDataType;
        }
    }

    public class SftpServerCleanupExpiredDataProvider inherits SftpServerDataProviderBase {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": "cleanup-expired",
                "desc": "Remove expired virtual exchange files according to typed retention policies, optionally scoped to a principal",
                "type": "SftpServerCleanupExpiredDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_request": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
            const RequestType = new SftpServerRetentionCleanupRequestDataType();
            const ResponseType = SftpServerRetentionCleanupResponseDataType;
        }

        constructor(*hash<auto> options) : SftpServerDataProviderBase(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerDataProviderBase(store) {
        }

        string getName() {
            return "cleanup-expired";
        }

        private auto doRequestImpl(auto req, *hash<auto> request_options) {
            # DP3: surface/accept the evaluation time as a date; the exchange uses epoch seconds
            hash<auto> sreq = req;
            if (sreq.now_s.typeCode() == NT_DATE) {
                sreq.now_s = sftpServerDateToEpoch(sreq.now_s);
            }
            hash<auto> result =
                getExchange().cleanupExpired(cast<hash<VirtualSftpRetentionCleanupRequest>>(sreq));
            return sftpServerEpochKeysToDate(result, "evaluated_at");
        }

        private *AbstractDataProviderType getRequestTypeImpl() {
            return RequestType;
        }

        private *AbstractDataProviderType getResponseTypeImpl() {
            return ResponseType;
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerInboundAcceptedEventDataProvider inherits SftpServerDataProviderBase,
            DataProvider::DelayedObservable {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": EventInboundFileAccepted,
                "desc": "Raise accepted and rejected inbound file events for a virtual SFTP exchange",
                "type": "SftpServerInboundAcceptedEventDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_observable": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
        }

        private {
            *int listener_id;
        }

        constructor(*hash<auto> options) : SftpServerDataProviderBase(options) {
            registerInboundListener();
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerDataProviderBase(store) {
            registerInboundListener();
        }

        destructor() {
            if (listener_id) {
                getExchange().deregisterInboundEventListener(listener_id);
            }
        }

        string getName() {
            return EventInboundFileAccepted;
        }

        observersReady() {
        }

        private hash<string, hash<DataProviderMessageInfo>> getEventTypesImpl() {
            return {
                EventInboundFileAccepted: <DataProviderMessageInfo>{
                    "desc": "Inbound file accepted event",
                    "type": SftpServerInboundEventInfoDataType,
                },
                EventInboundFileRejected: <DataProviderMessageInfo>{
                    "desc": "Inbound file rejected event",
                    "type": SftpServerInboundEventInfoDataType,
                },
            };
        }

        private auto getExampleEventDataImpl(string event_id) {
            bool rejected = event_id == EventInboundFileRejected;
            return {
                "event_type": event_id,
                "queue": "inbound",
                "name": "order-12345.csv",
                "path": "/inbound/order-12345.csv",
                "size": 1024,
                "metadata": {"kind": "order", "tenant": "acme"},
                "data": NOTHING,
                "submitted_at": now_us(),
                "source": "sftp",
                "session_id": "main:1715000000:42",
                "server_name": "sftp-exchange",
                "listener_name": "main",
                "principal": "principal:acme",
                "accepted": !rejected,
                "reason_code": rejected ? InboundRejectMaxFileCount : NOTHING,
                "reason_desc": rejected ? "inbound file-count quota exceeded" : NOTHING,
                "checksum": rejected ? NOTHING : "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                "checksum_algorithm": rejected ? NOTHING : "SHA-256",
                "transfer_info": NOTHING,
            };
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }

        private nothing registerInboundListener() {
            listener_id = getExchange().registerInboundEventListener(sub(hash<VirtualSftpInboundEventInfo> event) {
                # DP3: emit submitted_at as a date (the exchange records epoch seconds)
                hash<auto> ev = sftpServerEpochKeysToDate(event, "submitted_at");
                if (ev.accepted) {
                    notifyObservers(EventInboundFileAccepted, ev);
                    return;
                }
                notifyObservers(EventInboundFileRejected, ev);
            });
        }
    }

    public class SftpServerClaimOutboundDataProvider inherits SftpServerCompleteOutboundDataProvider {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": "claim-outbound",
                "desc": "Claim an outbound exchange entry in a virtual SFTP exchange",
                "type": "SftpServerClaimOutboundDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_request": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
        }

        constructor(*hash<auto> options) : SftpServerCompleteOutboundDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerCompleteOutboundDataProvider(store) {
        }

        string getName() {
            return "claim-outbound";
        }

        private auto doRequestImpl(auto req, *hash<auto> request_options) {
            return store.claimOutboundRecord(cast<hash<VirtualSftpRecordCompletionRequest>>(req));
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerOutboundCompletionEventDataProvider inherits SftpServerDataProviderBase,
            DataProvider::DelayedObservable {
        private {
            *int listener_id;
        }

        constructor(*hash<auto> options) : SftpServerDataProviderBase(options) {
            registerOutboundListener();
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerDataProviderBase(store) {
            registerOutboundListener();
        }

        destructor() {
            if (listener_id) {
                getExchange().deregisterOutboundEventListener(listener_id);
            }
        }

        observersReady() {
        }

        private hash<string, hash<DataProviderMessageInfo>> getEventTypesImpl() {
            return {
                getName(): <DataProviderMessageInfo>{
                    "desc": getDesc() ?? sprintf("Outbound completion event for %s", getName()),
                    "type": SftpServerOutboundEventInfoDataType,
                },
            };
        }

        private auto getExampleEventDataImpl(string event_id) {
            string operation = event_id == EventOutboundFileClaimed
                ? "claim"
                : (event_id == EventOutboundFileArchived ? "archive" : "delete");
            return {
                "event_type": event_id,
                "queue": "outbound",
                "name": "report-2026-05.csv",
                "path": "/outbound/report-2026-05.csv",
                "size": 4096,
                "metadata": {"kind": "report", "tenant": "acme"},
                "completed_at": now_us(),
                "source": "sftp",
                "session_id": "main:1715000000:43",
                "server_name": "sftp-exchange",
                "listener_name": "main",
                "principal": "principal:acme",
                "final_name": operation == "delete" ? NOTHING : "report-2026-05.csv",
                "operation": operation,
                "reason_code": NOTHING,
                "reason_desc": NOTHING,
                "checksum": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                "checksum_algorithm": "SHA-256",
                "transfer_info": NOTHING,
            };
        }

        private nothing registerOutboundListener() {
            string event_name = getName();
            listener_id = getExchange().registerOutboundEventListener(sub(hash<VirtualSftpOutboundEventInfo> event) {
                if (event.event_type == event_name) {
                    # DP3: emit completed_at as a date (the exchange records epoch seconds)
                    notifyObservers(event_name, sftpServerEpochKeysToDate(event, "completed_at"));
                }
            });
        }
    }

    public class SftpServerArchiveOutboundDataProvider inherits SftpServerCompleteOutboundDataProvider {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": "archive-outbound",
                "desc": "Archive an outbound exchange entry in a virtual SFTP exchange",
                "type": "SftpServerArchiveOutboundDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_request": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
        }

        constructor(*hash<auto> options) : SftpServerCompleteOutboundDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerCompleteOutboundDataProvider(store) {
        }

        string getName() {
            return "archive-outbound";
        }

        private auto doRequestImpl(auto req, *hash<auto> request_options) {
            return store.archiveOutboundRecord(cast<hash<VirtualSftpRecordCompletionRequest>>(req));
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerOutboundClaimedEventDataProvider inherits SftpServerOutboundCompletionEventDataProvider {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": EventOutboundFileClaimed,
                "desc": "Raise an event when an outbound file is claimed from a virtual SFTP exchange",
                "type": "SftpServerOutboundClaimedEventDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_observable": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
        }

        constructor(*hash<auto> options) : SftpServerOutboundCompletionEventDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerOutboundCompletionEventDataProvider(store) {
        }

        string getName() {
            return EventOutboundFileClaimed;
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerOutboundArchivedEventDataProvider inherits SftpServerOutboundCompletionEventDataProvider {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": EventOutboundFileArchived,
                "desc": "Raise an event when an outbound file is archived from a virtual SFTP exchange",
                "type": "SftpServerOutboundArchivedEventDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_observable": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
        }

        constructor(*hash<auto> options) : SftpServerOutboundCompletionEventDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerOutboundCompletionEventDataProvider(store) {
        }

        string getName() {
            return EventOutboundFileArchived;
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerDeleteOutboundDataProvider inherits SftpServerCompleteOutboundDataProvider {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": "delete-outbound",
                "desc": "Delete an outbound exchange entry from a virtual SFTP exchange",
                "type": "SftpServerDeleteOutboundDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_request": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
        }

        constructor(*hash<auto> options) : SftpServerCompleteOutboundDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerCompleteOutboundDataProvider(store) {
        }

        string getName() {
            return "delete-outbound";
        }

        private auto doRequestImpl(auto req, *hash<auto> request_options) {
            return store.deleteOutboundRecord(cast<hash<VirtualSftpRecordCompletionRequest>>(req));
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }

    public class SftpServerOutboundDeletedEventDataProvider inherits SftpServerOutboundCompletionEventDataProvider {
        public {
            const ProviderInfo = <DataProviderInfo>{
                "name": EventOutboundFileDeleted,
                "desc": "Raise an event when an outbound file is deleted from a virtual SFTP exchange",
                "type": "SftpServerOutboundDeletedEventDataProvider",
                "constructor_options": ConstructorOptions,
                "supports_observable": True,
            };
            const ProviderSummaryInfo = cast<hash<DataProviderSummaryInfo>>(ProviderInfo{
                AbstractDataProvider::DataProviderSummaryInfoKeys
            });
        }

        constructor(*hash<auto> options) : SftpServerOutboundCompletionEventDataProvider(options) {
        }

        constructor(VirtualSftpExchangeRecordStore store) : SftpServerOutboundCompletionEventDataProvider(store) {
        }

        string getName() {
            return EventOutboundFileDeleted;
        }

        private hash<DataProviderInfo> getStaticInfoImpl() {
            return ProviderInfo;
        }
    }
}
