public namespace SshServerConnections {
public hashdecl SshServerConnectionLimits {
    *int max_sessions;
}

public hashdecl SshServerConnectionServices {
    *list<string> enabled_auth_methods;
    *bool allow_command_service;
    *bool allow_sftp_service;
}

public hashdecl SshServerConnectionSecurity {
    *string allowed_ciphers;
    *string allowed_kex;
    *string allowed_macs;
    *string allowed_hostkey_algorithms;
    *list<string> allowed_addresses;
    *list<string> denied_addresses;
}

/** Base ConnectionProvider implementation for managed local
    @ref Qore::Ssh::SshServer "Qore::Ssh::SshServer" instances.

    This class provides shared URL parsing, listener projection, typed server
    configuration construction, and server lifecycle helpers for the concrete
    command and SFTP connection-provider classes.
*/
public class AbstractSshServerConnection inherits ConnectionProvider::AbstractConnectionWithInfo {
    public {
        const SharedOptions = {
            "host_keys": <ConnectionOptionInfo>{
                "display_name": "Host Keys",
                "short_desc": "List of host key files for the server listener",
                "type": "list",
                "desc": "List of SSH host key files to load for the listener. "
                    "Each file must contain a host private key supported by libssh.",
                "required": True,
                "preselected": True,
            },
            "listener_name": <ConnectionOptionInfo>{
                "display_name": "Listener Name",
                "short_desc": "Logical listener name reported in session metadata",
                "type": "string",
                "desc": "Logical listener name to place in listener status and accepted session metadata. "
                    "Defaults to the connection name.",
            },
            "limits": <ConnectionOptionInfo>{
                "display_name": "Operational Limits",
                "short_desc": "Grouped operational limits for the listener",
                "type": "hash",
                "desc": "Grouped typed operational limits. "
                    "Currently supports `max_sessions` for a deterministic cap on concurrently "
                    "accepted sessions per listener.",
            },
            "banner": <ConnectionOptionInfo>{
                "display_name": "Banner",
                "short_desc": "SSH identification banner for the listener",
                "type": "string",
                "desc": "Optional SSH server banner presented during handshake.",
            },
            "services": <ConnectionOptionInfo>{
                "display_name": "Service Controls",
                "short_desc": "Grouped auth and service controls for the listener",
                "type": "hash",
                "desc": "Grouped typed service controls. "
                    "Currently supports `enabled_auth_methods`, `allow_command_service`, "
                    "and `allow_sftp_service`.",
            },
            "auth_provider": <ConnectionOptionInfo>{
                "display_name": "Auth Provider",
                "short_desc": "Object-driven authentication provider",
                "type": "object",
                "desc": "Authentication provider object passed to "
                    "`Qore::Ssh::SshServerConfig.auth_provider`. The object must implement "
                    "`authenticate(hash<Qore::Ssh::SshAuthContextInfo>)` and return "
                    "`hash<Qore::Ssh::SshAuthDecision>`.",
            },
            "auth": <ConnectionOptionInfo>{
                "display_name": "Auth Options",
                "short_desc": "Grouped typed authentication configuration",
                "type": "hash",
                "desc": "Grouped typed authentication configuration compatible with "
                    "`SshServerAuthProvider::VirtualSshAuthProviderOptions`. When "
                    "`auth_provider` is not set, the connection synthesizes a built-in "
                    "`SshServerAuthProvider::VirtualSshAuthProvider` from this hash.",
            },
            "server_options": <ConnectionOptionInfo>{
                "display_name": "Listener Server Options",
                "short_desc": "Free-form listener-level libssh options",
                "type": "hash",
                "desc": "Free-form listener-level libssh server options passed through to "
                    "`Qore::Ssh::SshListenerConfig.server_options`.",
            },
            "auth_callback": <ConnectionOptionInfo>{
                "display_name": "Auth Callback",
                "short_desc": "Authentication callback for accepted auth contexts",
                "type": "code",
                "desc": "Authentication callback passed to `Qore::Ssh::SshServerConfig.auth_callback`.",
            },
            "command_callback": <ConnectionOptionInfo>{
                "display_name": "Command Callback",
                "short_desc": "Command callback for accepted command sessions",
                "type": "code",
                "desc": "Command callback passed to `Qore::Ssh::SshServerConfig.command_callback`.",
            },
            "command_backend": <ConnectionOptionInfo>{
                "display_name": "Command Backend",
                "short_desc": "Virtual command backend shared by the server connection",
                "type": "object",
                "desc": "Optional generic virtual command backend object. When `command_callback` is not set, "
                    "the connection synthesizes a typed callback that delegates to "
                    "`command_backend.handle(hash<SshCommandRequest>)`.",
            },
            "audit_callback": <ConnectionOptionInfo>{
                "display_name": "Audit Callback",
                "short_desc": "Audit callback for server-side events",
                "type": "code",
                "desc": "Audit callback passed to `Qore::Ssh::SshServerConfig.audit_callback`.",
            },
            "sftp_factory_callback": <ConnectionOptionInfo>{
                "display_name": "SFTP Factory Callback",
                "short_desc": "Factory callback for accepted SFTP sessions",
                "type": "code",
                "desc": "SFTP factory callback passed to `Qore::Ssh::SshServerConfig.sftp_factory_callback`.",
            },
            "auth_config": <ConnectionOptionInfo>{
                "display_name": "Auth Config",
                "short_desc": "Free-form auth callback configuration",
                "type": "hash",
                "desc": "Free-form auth callback configuration passed to "
                    "`Qore::Ssh::SshServerConfig.auth_config`.",
            },
            "command_config": <ConnectionOptionInfo>{
                "display_name": "Command Config",
                "short_desc": "Free-form command callback configuration",
                "type": "hash",
                "desc": "Free-form command callback configuration passed to "
                    "`Qore::Ssh::SshServerConfig.command_config`.",
            },
            "audit_config": <ConnectionOptionInfo>{
                "display_name": "Audit Config",
                "short_desc": "Free-form audit callback configuration",
                "type": "hash",
                "desc": "Free-form audit callback configuration passed to "
                    "`Qore::Ssh::SshServerConfig.audit_config`.",
            },
            "sftp_config": <ConnectionOptionInfo>{
                "display_name": "SFTP Config",
                "short_desc": "Free-form SFTP callback and policy configuration",
                "type": "hash",
                "desc": "Free-form SFTP callback and policy configuration passed to "
                    "`Qore::Ssh::SshServerConfig.sftp_config`.",
            },
            "default_command_timeout_ms": <ConnectionOptionInfo>{
                "display_name": "Default Command Timeout",
                "short_desc": "Default command timeout in milliseconds",
                "type": "int",
                "desc": "Default command timeout passed to "
                    "`Qore::Ssh::SshServerConfig.default_command_timeout_ms`.",
            },
            "log_authenticated_sessions": <ConnectionOptionInfo>{
                "display_name": "Log Authenticated Sessions",
                "short_desc": "Enable authenticated-session logging",
                "type": "bool",
                "desc": "Controls `Qore::Ssh::SshServerConfig.log_authenticated_sessions`.",
                "default_value": True,
            },
            "log_file_transfers": <ConnectionOptionInfo>{
                "display_name": "Log File Transfers",
                "short_desc": "Enable file-transfer logging",
                "type": "bool",
                "desc": "Controls `Qore::Ssh::SshServerConfig.log_file_transfers`.",
                "default_value": True,
            },
            "logger": <ConnectionOptionInfo>{
                "display_name": "Logger",
                "short_desc": "Logger for server and session events",
                "type": "object",
                "desc": "Optional `LoggerInterface` object passed to `Qore::Ssh::SshServerConfig.logger`.",
            },
            "keepalive_interval_seconds": <ConnectionOptionInfo>{
                "display_name": "Keepalive Interval",
                "short_desc": "Interval in seconds between server-side keepalive probes",
                "type": "int",
                "desc": "Interval in seconds between SSH keepalive probes sent by the server. "
                    "Helps detect dead connections over unreliable networks.",
            },
            "idle_timeout_seconds": <ConnectionOptionInfo>{
                "display_name": "Idle Timeout",
                "short_desc": "Maximum idle time in seconds before disconnecting a session",
                "type": "int",
                "desc": "Maximum idle time in seconds before the server disconnects the session. "
                    "Measured from the last message received from the client.",
            },
            "auth_banner": <ConnectionOptionInfo>{
                "display_name": "Auth Banner",
                "short_desc": "RFC 4252 pre-authentication banner message",
                "type": "string",
                "desc": "Pre-authentication banner sent to the client via `SSH_MSG_USERAUTH_BANNER` "
                    "before the auth exchange begins. Distinct from the SSH identification `banner` "
                    "which is set during the initial handshake.",
            },
            "security": <ConnectionOptionInfo>{
                "display_name": "Security Options",
                "short_desc": "Grouped security options for ciphers, KEX, MACs, and IP filtering",
                "type": "hash",
                "desc": "Grouped typed security options. Supports `allowed_ciphers`, `allowed_kex`, "
                    "`allowed_macs`, `allowed_hostkey_algorithms` (comma-separated algorithm names), "
                    "and `allowed_addresses` / `denied_addresses` (CIDR or bare IP lists).",
            },
        };
    }

    constructor(string name, string description, string url, hash<auto> attributes = {}, hash<auto> options = {},
            *LoggerInterface logger)
            : AbstractConnectionWithInfo(name, description, url, attributes, options, logger) {
        validateTypedOptions();
    }

    constructor(hash<auto> config, *hash<auto> attr) : AbstractConnectionWithInfo(config, attr) {
        validateTypedOptions();
    }

    #! returns a typed listener configuration projected from the connection URL and options
    hash<Qore::Ssh::SshListenerConfig> getListenerConfig() {
        string bind_address = urlh.host ?? "127.0.0.1";
        int port = getBindPort();
        list<string> host_keys = ();
        foreach string host_key in (cast<list<string>>(opts.host_keys)) {
            host_keys += substitute_env_vars(host_key);
        }

        hash<Qore::Ssh::SshListenerConfig> listener = <Qore::Ssh::SshListenerConfig>{
            "name": opts.listener_name ?? name,
            "bind_address": bind_address,
            "port": port,
            "host_keys": host_keys,
        };

        *hash<SshServerConnectionLimits> limits = getConnectionLimitsOptions();
        if (limits && limits.max_sessions != NOTHING) {
            listener.max_sessions = limits.max_sessions;
        }
        if (opts.banner) {
            listener.banner = opts.banner;
        }
        *hash<SshServerConnectionServices> services = getConnectionServicesOptions();
        if (services && services.enabled_auth_methods) {
            listener.enabled_auth_methods = services.enabled_auth_methods;
        } else if (*hash<SshServerAuthProvider::VirtualSshAuthProviderOptions> auth = getConnectionAuthOptions()) {
            if (auth.methods) {
                listener.enabled_auth_methods = auth.methods;
            }
        }
        if (services && exists services.allow_command_service) {
            listener.allow_command_service = services.allow_command_service;
        } else {
            listener.allow_command_service = getDefaultAllowCommandService();
        }
        if (services && exists services.allow_sftp_service) {
            listener.allow_sftp_service = services.allow_sftp_service;
        } else {
            listener.allow_sftp_service = getDefaultAllowSftpService();
        }
        if (opts.server_options) {
            listener.server_options = cast<hash<auto>>(opts.server_options);
        }
        if (exists opts.keepalive_interval_seconds) {
            listener.keepalive_interval_seconds = opts.keepalive_interval_seconds;
        }
        if (exists opts.idle_timeout_seconds) {
            listener.idle_timeout_seconds = opts.idle_timeout_seconds;
        }
        if (opts.auth_banner) {
            listener.auth_banner = opts.auth_banner;
        }
        *hash<SshServerConnectionSecurity> security = getConnectionSecurityOptions();
        if (security) {
            if (security.allowed_ciphers) {
                listener.allowed_ciphers = security.allowed_ciphers;
            }
            if (security.allowed_kex) {
                listener.allowed_kex = security.allowed_kex;
            }
            if (security.allowed_macs) {
                listener.allowed_macs = security.allowed_macs;
            }
            if (security.allowed_hostkey_algorithms) {
                listener.allowed_hostkey_algorithms = security.allowed_hostkey_algorithms;
            }
            if (security.allowed_addresses) {
                listener.allowed_addresses = security.allowed_addresses;
            }
            if (security.denied_addresses) {
                listener.denied_addresses = security.denied_addresses;
            }
        }
        return listener;
    }

    private int getBindPort() {
        *list<string> port_match = url =~ x/^[^:]+:\/\/[^\/:]+:(\d+)(?:\/|$)/;
        if (port_match) {
            return int(port_match[0]);
        }
        if (exists urlh.port) {
            return urlh.port;
        }
        return 22;
    }

    private validateTypedOptions() {
        if (opts.auth_provider && (opts.auth || opts.auth_callback)) {
            throw "CONNECTION-OPTION-ERROR",
                sprintf("connection %y options %y cannot be combined with %y or %y",
                    name, "auth_provider", "auth", "auth_callback");
        }
        if (opts.auth && opts.auth_callback) {
            throw "CONNECTION-OPTION-ERROR",
                sprintf("connection %y options %y and %y cannot be combined",
                    name, "auth", "auth_callback");
        }
        if (opts.limits) {
            hash<SshServerConnectionLimits> limits = getConnectionLimitsOptions();
            if (limits.max_sessions != NOTHING && limits.max_sessions < 0) {
                throw "CONNECTION-OPTION-ERROR",
                    sprintf("connection %y option %y.%y must be >= 0; got %y",
                        name, "limits", "max_sessions", limits.max_sessions);
            }
        }
        if (opts.services) {
            hash<SshServerConnectionServices> services = getConnectionServicesOptions();
            validateEnabledAuthMethods("services.enabled_auth_methods", services.enabled_auth_methods);
        }
        if (opts.auth) {
            hash<SshServerAuthProvider::VirtualSshAuthProviderOptions> auth = getConnectionAuthOptions();
            validateEnabledAuthMethods("auth.methods", auth.methods);
        }
    }

    private *hash<SshServerConnectionLimits> getConnectionLimitsOptions() {
        if (!opts.limits) {
            return NOTHING;
        }
        try {
            return cast<hash<SshServerConnectionLimits>>(cast<hash<auto>>(opts.limits));
        } catch (auto e) {
            throw "CONNECTION-OPTION-ERROR",
                sprintf("connection %y option %y must be a hash compatible with "
                    "SshServerConnections::SshServerConnectionLimits", name, "limits");
        }
    }

    private *hash<SshServerConnectionServices> getConnectionServicesOptions() {
        if (!opts.services) {
            return NOTHING;
        }
        try {
            return cast<hash<SshServerConnectionServices>>(cast<hash<auto>>(opts.services));
        } catch (auto e) {
            throw "CONNECTION-OPTION-ERROR",
                sprintf("connection %y option %y must be a hash compatible with "
                    "SshServerConnections::SshServerConnectionServices", name, "services");
        }
    }

    private *hash<SshServerConnectionSecurity> getConnectionSecurityOptions() {
        if (!opts.security) {
            return NOTHING;
        }
        try {
            return cast<hash<SshServerConnectionSecurity>>(cast<hash<auto>>(opts.security));
        } catch (auto e) {
            throw "CONNECTION-OPTION-ERROR",
                sprintf("connection %y option %y must be a hash compatible with "
                    "SshServerConnections::SshServerConnectionSecurity", name, "security");
        }
    }

    private *hash<SshServerAuthProvider::VirtualSshAuthProviderOptions> getConnectionAuthOptions() {
        if (!opts.auth) {
            return NOTHING;
        }
        try {
            hash<SshServerAuthProvider::VirtualSshAuthProviderOptions> auth
                = cast<hash<SshServerAuthProvider::VirtualSshAuthProviderOptions>>(cast<hash<auto>>(opts.auth));
            if (auth.logger == NOTHING && opts.logger != NOTHING) {
                auth.logger = cast<LoggerInterface>(opts.logger);
            }
            return auth;
        } catch (auto e) {
            throw "CONNECTION-OPTION-ERROR",
                sprintf("connection %y option %y must be a hash compatible with "
                    "SshServerAuthProvider::VirtualSshAuthProviderOptions", name, "auth");
        }
    }

    private nothing validateEnabledAuthMethods(string option_name, *list<string> methods) {
        if (!methods) {
            return;
        }
        foreach string method in (cast<list<string>>(methods)) {
            if (method != "none" && method != "password" && method != "publickey"
                    && method != "interactive" && method != "hostbased" && method != "gssapi-mic") {
                throw "CONNECTION-OPTION-ERROR",
                    sprintf("connection %y option %y was passed with invalid auth method %y; "
                        "allowed values are: %y", name, option_name, method,
                        ("none", "password", "publickey", "interactive", "hostbased", "gssapi-mic"));
            }
        }
    }

    #! returns a typed server configuration projected from the connection URL and options
    hash<Qore::Ssh::SshServerConfig> getServerConfig() {
        hash<Qore::Ssh::SshServerConfig> config = <Qore::Ssh::SshServerConfig>{
            "name": name,
            "listeners": (getListenerConfig(),),
        };

        if (opts.logger) {
            config.logger = opts.logger;
        }
        if (opts.auth_provider) {
            config.auth_provider = opts.auth_provider;
        } else if (opts.auth) {
            config.auth_provider = new SshServerAuthProvider::VirtualSshAuthProvider(getConnectionAuthOptions());
        } else if (opts.auth_callback) {
            config.auth_callback = opts.auth_callback;
        }
        if (opts.command_callback) {
            config.command_callback = opts.command_callback;
        } else if (opts.command_backend) {
            object command_backend = opts.command_backend;
            config.command_callback = hash<Qore::Ssh::SshCommandResult>
                sub(hash<Qore::Ssh::SshCommandRequest> req) {
                    return command_backend.handle(req);
                };
        }
        if (opts.audit_callback) {
            config.audit_callback = opts.audit_callback;
        }
        if (opts.sftp_factory_callback) {
            config.sftp_factory_callback = opts.sftp_factory_callback;
        } else if (opts.backend) {
            object backend = opts.backend;
            config.sftp_factory_callback = hash<auto> sub(hash<Qore::Ssh::SftpSessionInfo> session_info) {
                return {
                    "backend": backend,
                };
            };
        }
        if (opts.auth_config) {
            config.auth_config = cast<hash<auto>>(opts.auth_config);
        }
        if (opts.command_config) {
            config.command_config = cast<hash<auto>>(opts.command_config);
        }
        if (opts.audit_config) {
            config.audit_config = cast<hash<auto>>(opts.audit_config);
        }
        if (opts.sftp_config) {
            config.sftp_config = cast<hash<auto>>(opts.sftp_config);
        }
        if (exists opts.default_command_timeout_ms) {
            config.default_command_timeout_ms = opts.default_command_timeout_ms;
        }
        if (exists opts.log_authenticated_sessions) {
            config.log_authenticated_sessions = opts.log_authenticated_sessions;
        }
        if (exists opts.log_file_transfers) {
            config.log_file_transfers = opts.log_file_transfers;
        }
        return config;
    }

    #! returns connection-defined features for server-side connection helpers
    private hash<string, bool> getFeaturesImpl() {
        return {
            "local_server": True,
            "single_listener": True,
            "typed_server_config": True,
        };
    }

    #! returns a live Qore::Ssh::SshServer object; starts it when connect is true
    private Qore::Ssh::SshServer getImpl(bool connect = True, *hash<auto> rtopts) {
        Qore::Ssh::SshServer server(getServerConfig());
        if (connect) {
            server.start();
        }
        return server;
    }

    private abstract bool getDefaultAllowCommandService();
    private abstract bool getDefaultAllowSftpService();
}
}
