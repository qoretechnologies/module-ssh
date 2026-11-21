public namespace SshServerConnections {
#! connection for managed local SFTP server instances
public class SftpServerConnection inherits AbstractSshServerConnection {
    #! Returns the functional domains of the connection's server (qoretechnologies/qore#7098)
    /** The server listens on the network, reads its host key files, serves local files (\c sftp_config
        \c root_dir) and keeps its staged publications in a SQLite database (\c publication_database)
    */
    private final int getConnectionDomainsImpl() {
        return DOM_NETWORK | DOM_FILESYSTEM | DOM_DATABASE;
    }

    public {
        const DataProviderAppName = "SftpServerExchange";
        const DataProviderSubtype = "exchange";
        const DataProviderConstructorOptions = {
            "backend": <DataProviderOptionInfo>{
                "display_name": "Virtual Exchange Backend",
                "short_desc": "Existing virtual exchange or record-store backend object",
                "type": AbstractDataProviderTypeMap."any",
                "desc": "Optional existing `VirtualSftpExchangeRecordStore` or `VirtualSftpExchange` object to use "
                    "as the generic data-provider backend.",
            },
            "inbound_dir": <DataProviderOptionInfo>{
                "display_name": "Inbound Directory",
                "short_desc": "Virtual inbound exchange directory",
                "type": AbstractDataProviderTypeMap."string",
                "desc": "Optional virtual inbound exchange directory when creating a provider backend from "
                    "constructor options.",
            },
            "outbound_dir": <DataProviderOptionInfo>{
                "display_name": "Outbound Directory",
                "short_desc": "Virtual outbound exchange directory",
                "type": AbstractDataProviderTypeMap."string",
                "desc": "Optional virtual outbound exchange directory when creating a provider backend from "
                    "constructor options.",
            },
            "archive_dir": <DataProviderOptionInfo>{
                "display_name": "Archive Directory",
                "short_desc": "Virtual archive directory for completed outbound files",
                "type": AbstractDataProviderTypeMap."string",
                "desc": "Optional virtual archive directory when creating a provider backend from constructor "
                    "options.",
            },
            "claim_dir": <DataProviderOptionInfo>{
                "display_name": "Claim Directory",
                "short_desc": "Virtual claim directory for claimed outbound files",
                "type": AbstractDataProviderTypeMap."string",
                "desc": "Optional virtual claim directory when creating a provider backend from constructor "
                    "options.",
            },
            "default_file_permissions": <DataProviderOptionInfo>{
                "display_name": "Default File Permissions",
                "short_desc": "Default permissions for created virtual files",
                "type": AbstractDataProviderTypeMap."int",
                "desc": "Optional default virtual file permissions for new provider backend instances.",
            },
            "default_directory_permissions": <DataProviderOptionInfo>{
                "display_name": "Default Directory Permissions",
                "short_desc": "Default permissions for created virtual directories",
                "type": AbstractDataProviderTypeMap."int",
                "desc": "Optional default virtual directory permissions for new provider backend instances.",
            },
            "logger": <DataProviderOptionInfo>{
                "display_name": "Logger",
                "short_desc": "Optional logger for provider and backend events",
                "type": AbstractDataProviderTypeMap."any",
                "desc": "Optional logger object inherited by the generic provider backend and child providers.",
            },
        };

        const ConnectionScheme = ConnectionProvider::connection_scheme_presentation("SshServerConnections",
            "SftpServerConnection", "en", <ConnectionSchemeInfo>{
            "display_name": "SFTP Server Connection",
            "short_desc": "A managed local SFTP server connection definition",
            "desc": "A managed local SFTP server connection definition for SFTP-oriented server listeners. "
                "The connection returns a live `Qore::Ssh::SshServer` object and also exposes the generic "
                "`SftpServerExchange` data-provider bridge.",
            "cls": Class::forName("SftpServerConnection"),
            "options": SharedOptions + {
                "publication_database": <ConnectionOptionInfo>{
                    "display_name": "Publication Database",
                    "short_desc": "SQLite file for immutable staged publication",
                    "type": "string",
                    "desc": "Absolute path to a dedicated SQLite database. Enables private `/staging` uploads, "
                        "no-replace rename to `/inbound`, and replay through `list-publications`.",
                },
                "backend": <ConnectionOptionInfo>{
                    "display_name": "Virtual Exchange Backend",
                    "short_desc": "Existing virtual exchange backend shared by the server and data provider",
                    "type": "object",
                    "desc": "Optional existing `VirtualSftpExchangeRecordStore` or `VirtualSftpExchange` object. "
                        "When set, the connection uses it both for accepted SFTP sessions and for the generic "
                        "`SftpServerExchange` data-provider bridge.",
                },
            },
            "required_options": "host_keys",
            "schemes": {
                "sftpsrv": True,
                "sftpserver": True,
            },
        });
    }

    constructor(string name, string description, string url, hash<auto> attributes = {}, hash<auto> options = {},
            *LoggerInterface logger)
            : AbstractSshServerConnection(name, description, url, attributes, options, logger) {
    }

    constructor(hash<auto> config, *hash<auto> attr) : AbstractSshServerConnection(config, attr) {
    }

    private {
        *object publication_backend;
    }

    private synchronized object getPublicationBackend() {
        if (opts.backend || opts.sftp_factory_callback) {
            throw "CONNECTION-OPTION-ERROR", "publication_database supplies its own SFTP backend and factory";
        }
        if (!publication_backend) {
            load_module("SftpServerDataProvider");
            publication_backend = create_object("SftpServerDataProvider::StagedSftpExchange", opts.publication_database);
        }
        return publication_backend;
    }

    #! Shares the staged exchange between every authenticated session and the receipt provider.
    hash<Qore::Ssh::SshServerConfig> getServerConfig() {
        hash<Qore::Ssh::SshServerConfig> config = AbstractSshServerConnection::getServerConfig();
        if (opts.publication_database != NOTHING) {
            object backend = getPublicationBackend();
            config.sftp_factory_callback = hash<auto> sub(hash<Qore::Ssh::SftpSessionInfo> info) {
                return {"backend": backend};
            };
        }
        return config;
    }

    string getType() {
        return "sftpsrv";
    }

    bool hasDataProvider() {
        return True;
    }

    *string getAppName() {
        return DataProviderAppName;
    }

    DataProvider::AbstractDataProvider getDataProvider(*hash<auto> constructor_options) {
        return getDataProviderImpl(DataProviderSubtype, constructor_options);
    }

    private DataProvider::AbstractDataProvider getDataProviderImpl(string subtype, *hash<auto> constructor_options) {
        if (subtype != DataProviderSubtype) {
            throw "DATA-PROVIDER-ERROR", sprintf("SFTP server connections do not support data provider subtype %y; "
                "supported subtypes: %y", subtype, keys getDataProviderSubtypes());
        }

        load_module("SftpServerDataProvider");
        hash<auto> options = constructor_options ?? {};
        if (opts.publication_database != NOTHING) {
            options.backend = getPublicationBackend();
        } else if (!exists options.backend && opts.backend) {
            options.backend = opts.backend;
        }
        return create_object("SftpServerDataProvider", options);
    }

    *hash<string, hash<DataProviderOptionInfo>> getDataProviderConstructorOptions() {
        return DataProviderConstructorOptions;
    }

    private *hash<string, *hash<string, hash<DataProviderOptionInfo>>> getDataProviderSubtypesImpl() {
        return {
            DataProviderSubtype: DataProviderConstructorOptions,
        };
    }

    private hash<ConnectionSchemeInfo> getConnectionSchemeInfoImpl() {
        return ConnectionScheme;
    }

    private bool getDefaultAllowCommandService() {
        return False;
    }

    private bool getDefaultAllowSftpService() {
        return True;
    }
}
}
