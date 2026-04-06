public namespace SshServerConnections {
#! connection for managed local SFTP server instances
public class SftpServerConnection inherits AbstractSshServerConnection {
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

        const ConnectionScheme = <ConnectionSchemeInfo>{
            "display_name": "SFTP Server Connection",
            "short_desc": "A managed local SFTP server connection definition",
            "desc": "A managed local SFTP server connection definition for SFTP-oriented server listeners. "
                "The connection returns a live `Qore::Ssh::SshServer` object and also exposes the generic "
                "`SftpServerExchange` data-provider bridge.",
            "cls": Class::forName("SftpServerConnection"),
            "options": SharedOptions + {
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
        };
    }

    constructor(string name, string description, string url, hash<auto> attributes = {}, hash<auto> options = {},
            *LoggerInterface logger)
            : AbstractSshServerConnection(name, description, url, attributes, options, logger) {
    }

    constructor(hash<auto> config, *hash<auto> attr) : AbstractSshServerConnection(config, attr) {
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
        if (!exists options.backend && opts.backend) {
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
