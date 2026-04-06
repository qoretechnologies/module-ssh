public namespace SshServerConnections {
#! connection for managed local SSH command server instances
public class SshCommandServerConnection inherits AbstractSshServerConnection {
    public {
        const ConnectionScheme = <ConnectionSchemeInfo>{
            "display_name": "SSH Server Connection",
            "short_desc": "A managed local SSH server connection definition",
            "desc": "A managed local SSH server connection definition for command-oriented server listeners. "
                "The connection returns a live `Qore::Ssh::SshServer` object.",
            "cls": Class::forName("SshCommandServerConnection"),
            "options": SharedOptions,
            "required_options": "host_keys",
            "schemes": {
                "sshsrv": True,
                "sshserver": True,
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
        return "sshsrv";
    }

    private hash<ConnectionSchemeInfo> getConnectionSchemeInfoImpl() {
        return ConnectionScheme;
    }

    private bool getDefaultAllowCommandService() {
        return True;
    }

    private bool getDefaultAllowSftpService() {
        return False;
    }
}
}
