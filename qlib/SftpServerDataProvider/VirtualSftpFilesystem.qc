public namespace SftpServerDataProvider {
    /** In-memory virtual SFTP filesystem backend for helper APIs and live
        @ref Qore::Ssh::SftpSession "Qore::Ssh::SftpSession" attachment.

        The filesystem supports virtual path management, typed submit/retrieve
        helpers, and typed low-level backend verbs for use through the ssh
        module's SFTP backend contract.
    */
    public class VirtualSftpFilesystem {
        private {
            hash<auto> files = {};
            hash<auto> directories = {};
            *string archive_dir;
            *LoggerInterface logger;
            Qore::Thread::Mutex state_lock();
            int default_file_permissions = 0100644;
            int default_directory_permissions = 0040755;
        }

        constructor(*hash<VirtualSftpFilesystemOptions> options) {
            directories{"/"} = {
                "permissions": default_directory_permissions,
                "metadata": {},
                "mtime": getUnixTime(),
                "atime": getUnixTime(),
            };

            if (options) {
                if (*int file_permissions = options.default_file_permissions) {
                    default_file_permissions = file_permissions;
                }
                if (*int directory_permissions = options.default_directory_permissions) {
                    default_directory_permissions = directory_permissions;
                    directories{"/"}.permissions = directory_permissions;
                }
                if (*string archive_path = options.archive_dir) {
                    archive_dir = normalizePath(archive_path, "archive_dir");
                    ensureParentDirectories(archive_dir);
                    ensureDirectoryExists(archive_dir);
                }
                if (*LoggerInterface options_logger = options.logger) {
                    setLogger(options_logger);
                }
            }
        }

        *LoggerInterface getLogger() {
            return logger;
        }

        nothing setLogger(*LoggerInterface new_logger) {
            logger = new_logger;
        }

        nothing clear() {
            state_lock.lock();
            on_exit state_lock.unlock();
            files = {};
            directories = (
                "/": {
                    "permissions": default_directory_permissions,
                    "metadata": {},
                    "mtime": getUnixTime(),
                    "atime": getUnixTime(),
                },
            );
            if (archive_dir) {
                ensureParentDirectories(archive_dir);
                ensureDirectoryExists(archive_dir);
            }
        }

        nothing addDirectory(string path, *hash<auto> metadata) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "addDirectory");
            ensureParentDirectories(normalized);
            ensureDirectoryExists(normalized, metadata);
            logDetail("virtual directory added: %s", normalized);
        }

        nothing addFile(string path, binary data, *hash<auto> metadata) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "addFile");
            ensureParentDirectories(normalized);
            files{normalized} = makeFileEntry(data, metadata);
            logDetail("virtual file added: %s (%d bytes)", normalized, data.size());
        }

        nothing addTextFile(string path, string data, *hash<auto> metadata) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "addTextFile");
            ensureParentDirectories(normalized);
            binary b = binary(data);
            files{normalized} = makeFileEntry(b, metadata);
            logDetail("virtual file added: %s (%d bytes)", normalized, b.size());
        }

        bool exists(string path) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "exists");
            return directories{normalized} != NOTHING || files{normalized} != NOTHING;
        }

        binary getFileData(string path) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "getFileData");
            *hash<auto> entry = files{normalized};
            if (!entry) {
                throw "VIRTUAL-SFTP-FS-ERROR", sprintf("virtual file %y does not exist", normalized);
            }
            return entry.data;
        }

        string getFileText(string path, *string encoding) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "getFileText");
            *hash<auto> entry = files{normalized};
            if (!entry) {
                throw "VIRTUAL-SFTP-FS-ERROR", sprintf("virtual file %y does not exist", normalized);
            }
            return entry.data.toString(encoding ?? "UTF-8");
        }

        list<string> listFilePaths(*string root_path) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string root = normalizePath(root_path ?? "/", "listFilePaths");
            return listFilePathsUnlocked(root);
        }

        list<string> listDirectoryPaths(*string root_path, bool include_root = True) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string root = normalizePath(root_path ?? "/", "listDirectoryPaths");
            return listDirectoryPathsUnlocked(root, include_root);
        }

        hash<VirtualSftpSnapshot> exportSnapshot(*string root_path) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string root = normalizePath(root_path ?? "/", "exportSnapshot");
            hash<auto> file_entries = {};
            list<string> file_paths = listFilePathsUnlocked(root);
            list<string> directory_paths = listDirectoryPathsUnlocked(root);
            foreach string file_path in (file_paths) {
                *hash<auto> entry = files{file_path};
                if (!entry) {
                    continue;
                }
                file_entries{file_path} = <VirtualSftpFileSnapshot>{
                    "size": entry.data.size(),
                    "data": entry.data,
                    "checksum": getChecksumValue(entry.metadata),
                    "checksum_algorithm": getChecksumAlgorithmValue(entry.metadata),
                    "state": getBuiltinState(entry.metadata),
                    "metadata": copyMetadata(entry.metadata),
                    "permissions": entry.permissions,
                    "mtime": entry.mtime,
                    "atime": entry.atime,
                };
            }
            return <VirtualSftpSnapshot>{
                "root_path": root,
                "file_paths": file_paths,
                "directory_paths": directory_paths,
                "files": file_entries,
            };
        }

        nothing mergeFileMetadata(string path, hash<auto> metadata) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "mergeFileMetadata");
            if (!files{normalized}) {
                throw "VIRTUAL-SFTP-FS-ERROR", sprintf("virtual file %y does not exist", normalized);
            }
            foreach string key in (keys(metadata)) {
                files{normalized}.metadata{key} = metadata{key};
            }
        }

        hash<auto> stat(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "stat");
            if (*hash<auto> dir = directories{path}) {
                return makeDirectoryStat(path, dir);
            }
            if (*hash<auto> file = files{path}) {
                return makeFileStat(path, file);
            }
            return {"path": path, "exists": False};
        }

        hash<auto> list(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "list");
            *hash<auto> dir = directories{path};
            if (!dir) {
                return {"path": path, "exists": False};
            }

            list<hash<auto>> entries = ();
            string prefix = path == "/" ? "/" : path + "/";

            foreach string dir_path in (sort(keys(directories))) {
                if (dir_path == path || dir_path == "/") {
                    continue;
                }
                if (dir_path.size() <= prefix.size() || dir_path.substr(0, prefix.size()) != prefix) {
                    continue;
                }
                string relative = dir_path.substr(prefix.size());
                if (relative.find("/") >= 0) {
                    continue;
                }
                *hash<auto> child = directories{dir_path};
                if (!child) {
                    continue;
                }
                entries += (makeListEntry(relative, True, 0, child.permissions, child),);
            }

            foreach string file_path in (sort(keys(files))) {
                if (file_path.size() <= prefix.size() || file_path.substr(0, prefix.size()) != prefix) {
                    continue;
                }
                string relative = file_path.substr(prefix.size());
                if (relative.find("/") >= 0) {
                    continue;
                }
                *hash<auto> child = files{file_path};
                if (!child) {
                    continue;
                }
                entries += (makeListEntry(relative, False, child.data.size(), child.permissions, child),);
            }

            return {
                "path": path,
                "exists": True,
                "entries": entries,
            };
        }

        hash<auto> openRead(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "openRead");
            *hash<auto> file = files{path};
            if (!file) {
                return {"path": path, "exists": False};
            }
            touchEntry(file, False);
            return {
                "path": path,
                "exists": True,
                "data": file.data,
                "size": file.data.size(),
                "permissions": file.permissions,
                "directory": False,
                "mtime": file.mtime,
                "atime": file.atime,
                "metadata": copyMetadata(file.metadata),
            };
        }

        hash<auto> openWrite(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "openWrite");
            ensureParentDirectories(path);
            return {
                "path": path,
                "exists": True,
                "permissions": default_file_permissions,
            };
        }

        hash<auto> closeWrite(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "closeWrite");
            ensureParentDirectories(path);
            binary data = req.data ?? binary();
            *hash<auto> metadata = req.metadata;
            files{path} = makeFileEntry(data, metadata);
            logDetail("virtual file written: %s (%d bytes)", path, data.size());
            return {
                "path": path,
                "exists": True,
                "completed": True,
            };
        }

        hash<auto> removePath(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "removePath");
            if (!files{path}) {
                return {"path": path, "exists": False};
            }
            delete files{path};
            logDetail("virtual file removed: %s", path);
            return {"path": path, "exists": True, "completed": True};
        }

        hash<auto> rename(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "rename");
            *string raw_target = req.target_path;
            if (!raw_target || !raw_target.size()) {
                throw "VIRTUAL-SFTP-FS-ERROR", "rename requires target_path";
            }
            string target_path = normalizePath(raw_target, "rename");
            ensureParentDirectories(target_path);

            if (*hash<auto> file = files{path}) {
                files{target_path} = file;
                delete files{path};
                logDetail("virtual file renamed: %s -> %s", path, target_path);
                return {"path": target_path, "exists": True, "completed": True};
            }

            *hash<auto> dir = directories{path};
            if (!dir) {
                return {"path": path, "exists": False};
            }
            if (path == "/") {
                throw "VIRTUAL-SFTP-FS-ERROR", "cannot rename the virtual root directory";
            }

            hash<auto> moved_dirs = {};
            hash<auto> moved_files = {};
            string prefix = path + "/";
            string target_prefix = target_path + "/";

            foreach string dir_path in (keys(directories)) {
                if (dir_path == path || (dir_path.size() > prefix.size() && dir_path.substr(0, prefix.size()) == prefix)) {
                    string new_path = dir_path == path ? target_path : target_prefix + dir_path.substr(prefix.size());
                    moved_dirs{new_path} = directories{dir_path};
                }
            }
            foreach string file_path in (keys(files)) {
                if (file_path.size() > prefix.size() && file_path.substr(0, prefix.size()) == prefix) {
                    string new_path = target_prefix + file_path.substr(prefix.size());
                    moved_files{new_path} = files{file_path};
                }
            }
            foreach string dir_path in (keys(directories)) {
                if (dir_path == path || (dir_path.size() > prefix.size() && dir_path.substr(0, prefix.size()) == prefix)) {
                    delete directories{dir_path};
                }
            }
            foreach string file_path in (keys(files)) {
                if (file_path.size() > prefix.size() && file_path.substr(0, prefix.size()) == prefix) {
                    delete files{file_path};
                }
            }
            foreach string dir_path in (keys(moved_dirs)) {
                directories{dir_path} = moved_dirs{dir_path};
            }
            foreach string file_path in (keys(moved_files)) {
                files{file_path} = moved_files{file_path};
            }

            logDetail("virtual directory renamed: %s -> %s", path, target_path);
            return {"path": target_path, "exists": True, "completed": True};
        }

        hash<auto> mkdir(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "mkdir");
            ensureParentDirectories(path);
            ensureDirectoryExists(path, req.metadata);
            logDetail("virtual directory created: %s", path);
            return {"path": path, "exists": True, "completed": True};
        }

        hash<auto> rmdir(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "rmdir");
            if (path == "/") {
                throw "VIRTUAL-SFTP-FS-ERROR", "cannot remove the virtual root directory";
            }
            if (!directories{path}) {
                return {"path": path, "exists": False};
            }
            if (!directoryEmpty(path)) {
                throw "VIRTUAL-SFTP-FS-ERROR", sprintf("virtual directory %y is not empty", path);
            }
            delete directories{path};
            logDetail("virtual directory removed: %s", path);
            return {"path": path, "exists": True, "completed": True};
        }

        hash<auto> submit(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "submit");
            binary data;
            if (*binary req_data = req.data) {
                data = req_data;
            } else if (*string source_path = req.source_path) {
                data = ReadOnlyFile::readBinaryFile(source_path);
            } else {
                throw "VIRTUAL-SFTP-FS-ERROR", "submit requires either data or source_path";
            }
            ensureParentDirectories(path);
            files{path} = makeFileEntry(data, req.metadata);
            logDetail("virtual file added: %s (%d bytes)", path, data.size());
            return {
                "path": path,
                "exists": True,
                "completed": True,
                "transfer_info": <Qore::Ssh::SftpTransferInfo>{
                    "operation": "submit",
                    "path": path,
                    "final_path": path,
                    "size": data.size(),
                    "atomic_publish": False,
                    "completed": True,
                },
            };
        }

        hash<auto> listAvailable(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "listAvailable");
            *hash<auto> dir = directories{path};
            if (!dir) {
                return {"path": path, "exists": False, "entries": ()};
            }

            list<hash<auto>> entries = ();
            string prefix = path == "/" ? "/" : path + "/";

            foreach string dir_path in (sort(keys(directories))) {
                if (dir_path == path || dir_path == "/") {
                    continue;
                }
                if (dir_path.size() <= prefix.size() || dir_path.substr(0, prefix.size()) != prefix) {
                    continue;
                }
                string relative = dir_path.substr(prefix.size());
                if (relative.find("/") >= 0) {
                    continue;
                }
                *hash<auto> child = directories{dir_path};
                if (!child) {
                    continue;
                }
                entries += (makeListEntry(relative, True, 0, child.permissions, child),);
            }

            foreach string file_path in (sort(keys(files))) {
                if (file_path.size() <= prefix.size() || file_path.substr(0, prefix.size()) != prefix) {
                    continue;
                }
                string relative = file_path.substr(prefix.size());
                if (relative.find("/") >= 0) {
                    continue;
                }
                *hash<auto> child = files{file_path};
                if (!child) {
                    continue;
                }
                entries += (makeListEntry(relative, False, child.data.size(), child.permissions, child),);
            }

            return {
                "path": path,
                "exists": True,
                "entries": entries,
            };
        }

        hash<auto> retrieve(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "retrieve");
            *hash<auto> file = files{path};
            if (!file) {
                return {"path": path, "exists": False};
            }
            touchEntry(file, False);
            binary data = file.data;
            return {
                "path": path,
                "exists": True,
                "data": data,
                "size": data.size(),
                "permissions": file.permissions,
                "transfer_info": <Qore::Ssh::SftpTransferInfo>{
                    "operation": "retrieve",
                    "path": path,
                    "final_path": path,
                    "size": data.size(),
                    "atomic_publish": False,
                    "completed": False,
                },
            };
        }

        hash<auto> completeRetrieve(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "completeRetrieve");
            *hash<auto> file = files{path};
            if (!file) {
                return {"path": path, "exists": False};
            }

            string mode = req.completion_mode ?? "";
            *string target_path = req.target_path ? normalizePath(req.target_path, "completeRetrieve target_path") : NOTHING;

            if (mode == "delete") {
                delete files{path};
            } else if (mode == "archive") {
                archiveFile(path, target_path);
            } else if (mode == "claim") {
                claimFile(path, target_path);
            }

            return {
                "path": target_path ?? path,
                "exists": True,
                "completed": True,
                "transfer_info": <Qore::Ssh::SftpTransferInfo>{
                    "operation": "retrieve",
                    "path": path,
                    "final_path": target_path ?? path,
                    "size": 0,
                    "atomic_publish": False,
                    "completed": True,
                },
            };
        }

        hash<VirtualSftpOperationResult> submit(hash<VirtualSftpSubmissionRequest> req) {
            hash<auto> result = submit(copyTypedRequest(req));
            return <VirtualSftpOperationResult>{
                "path": result.path,
                "available": result.exists,
                "completed": result.completed,
                "transfer_info": result.transfer_info,
            };
        }

        hash<VirtualSftpListResult> listAvailable(hash<VirtualSftpPathRequest> req) {
            hash<auto> result = listAvailable(copyTypedRequest(req));
            return <VirtualSftpListResult>{
                "path": result.path,
                "available": result.exists,
                "entries": result.entries ?? (),
            };
        }

        hash<VirtualSftpRetrieveResult> retrieve(hash<VirtualSftpPathRequest> req) {
            hash<auto> result = retrieve(copyTypedRequest(req));
            return <VirtualSftpRetrieveResult>{
                "path": result.path,
                "available": result.exists,
                "completed": result.completed ?? False,
                "checksum": result.checksum,
                "checksum_algorithm": result.checksum_algorithm,
                "data": result.data,
                "size": result.size,
                "permissions": result.permissions,
                "transfer_info": result.transfer_info,
            };
        }

        hash<VirtualSftpOperationResult> completeRetrieve(hash<VirtualSftpCompletionRequest> req) {
            hash<auto> result = completeRetrieve(copyTypedRequest(req));
            return <VirtualSftpOperationResult>{
                "path": result.path,
                "available": result.exists,
                "completed": result.completed,
                "checksum": result.checksum,
                "checksum_algorithm": result.checksum_algorithm,
                "transfer_info": result.transfer_info,
            };
        }

        hash<Qore::Ssh::SftpPathInfo> stat(hash<Qore::Ssh::SftpPathRequest> req) {
            hash<auto> result = stat(copyTypedRequest(req));
            return <Qore::Ssh::SftpPathInfo>{
                "path": result.path,
                "exists": result.exists,
                "directory": result.directory,
                "size": result.size,
                "permissions": result.permissions,
                "metadata": result.metadata,
            };
        }

        hash<Qore::Ssh::SftpListResult> list(hash<Qore::Ssh::SftpPathRequest> req) {
            hash<auto> result = list(copyTypedRequest(req));
            return <Qore::Ssh::SftpListResult>{
                "path": result.path,
                "entries": result.entries ?? (),
            };
        }

        hash<Qore::Ssh::SftpOpenResult> openRead(hash<Qore::Ssh::SftpOpenRequest> req) {
            hash<auto> result = openRead(copyTypedRequest(req));
            return <Qore::Ssh::SftpOpenResult>{
                "path": result.path,
                "exists": result.exists,
                "data": result.data,
                "size": result.size,
                "permissions": result.permissions,
                "metadata": result.metadata,
                "transfer_info": result.transfer_info,
            };
        }

        hash<Qore::Ssh::SftpOpenResult> openWrite(hash<Qore::Ssh::SftpOpenRequest> req) {
            hash<auto> result = openWrite(copyTypedRequest(req));
            return <Qore::Ssh::SftpOpenResult>{
                "path": result.path,
                "exists": result.exists,
                "permissions": result.permissions,
                "metadata": result.metadata,
                "transfer_info": result.transfer_info,
            };
        }

        hash<Qore::Ssh::SftpOperationResult> closeWrite(hash<Qore::Ssh::SftpSubmissionRequest> req) {
            return cast<hash<Qore::Ssh::SftpOperationResult>>(closeWrite(copyTypedRequest(req)));
        }

        hash<Qore::Ssh::SftpOperationResult> removePath(hash<Qore::Ssh::SftpPathRequest> req) {
            return cast<hash<Qore::Ssh::SftpOperationResult>>(removePath(copyTypedRequest(req)));
        }

        hash<Qore::Ssh::SftpOperationResult> rename(hash<Qore::Ssh::SftpRenameRequest> req) {
            return cast<hash<Qore::Ssh::SftpOperationResult>>(rename(copyTypedRequest(req)));
        }

        hash<Qore::Ssh::SftpOperationResult> mkdir(hash<Qore::Ssh::SftpPathRequest> req) {
            return cast<hash<Qore::Ssh::SftpOperationResult>>(mkdir(copyTypedRequest(req)));
        }

        hash<Qore::Ssh::SftpOperationResult> rmdir(hash<Qore::Ssh::SftpPathRequest> req) {
            return cast<hash<Qore::Ssh::SftpOperationResult>>(rmdir(copyTypedRequest(req)));
        }

        private int getUnixTime() {
            return clock_getseconds();
        }

        private nothing logDetail(string fmt, ...) {
            if (logger) {
                logger.detail("%s", vsprintf(fmt, argv));
            }
        }

        private nothing logInfo(string fmt, ...) {
            if (logger) {
                logger.info("%s", vsprintf(fmt, argv));
            }
        }

        private hash<auto> copyMetadata(*hash<auto> metadata) {
            hash<auto> rv = {};
            if (!metadata) {
                return rv;
            }
            foreach string key in (keys(metadata)) {
                rv{key} = metadata{key};
            }
            return rv;
        }

        private *hash<VirtualSftpBuiltinState> getBuiltinState(*hash<auto> metadata) {
            if (!metadata) {
                return NOTHING;
            }

            hash<VirtualSftpBuiltinState> state = <VirtualSftpBuiltinState>{};
            bool has_state = False;

            if (metadata.archive != NOTHING) {
                state.archived = metadata.archive;
                has_state = True;
            }
            if (metadata.archived_at != NOTHING) {
                state.archived_at = metadata.archived_at;
                has_state = True;
            }
            if (metadata.claimed != NOTHING) {
                state.claimed = metadata.claimed;
                has_state = True;
            }
            if (metadata.claimed_at != NOTHING) {
                state.claimed_at = metadata.claimed_at;
                has_state = True;
            }
            if (metadata.exchange_role != NOTHING) {
                state.exchange_role = metadata.exchange_role;
                has_state = True;
            }

            return has_state ? state : NOTHING;
        }

        private hash<auto> copyTypedRequest(hash<auto> req) {
            hash<auto> rv = {};
            foreach string key in (keys(req)) {
                rv{key} = req{key};
            }
            return rv;
        }

        private list<string> listFilePathsUnlocked(string root) {
            list<string> rv = ();
            string prefix = root == "/" ? "/" : root + "/";
            foreach string file_path in (sort(keys(files))) {
                if (file_path == root || (file_path.size() > prefix.size()
                        && file_path.substr(0, prefix.size()) == prefix) || root == "/") {
                    rv += (file_path,);
                }
            }
            return rv;
        }

        private list<string> listDirectoryPathsUnlocked(string root, bool include_root = True) {
            list<string> rv = ();
            string prefix = root == "/" ? "/" : root + "/";
            foreach string dir_path in (sort(keys(directories))) {
                if (dir_path == root) {
                    if (include_root) {
                        rv += (dir_path,);
                    }
                    continue;
                }
                if (root == "/" || (dir_path.size() > prefix.size() && dir_path.substr(0, prefix.size()) == prefix)) {
                    rv += (dir_path,);
                }
            }
            return rv;
        }

        private string getRequestPath(hash<auto> req, string operation) {
            *string raw_path = req.path;
            if (!raw_path || !raw_path.size()) {
                throw "VIRTUAL-SFTP-FS-ERROR", sprintf("%s requires a non-empty path", operation);
            }
            return normalizePath(raw_path, operation);
        }

        private string normalizePath(string path, string operation) {
            if (!path.size() || path[0] != '/') {
                throw "VIRTUAL-SFTP-FS-ERROR", sprintf("%s requires an absolute virtual path; got %y", operation, path);
            }

            list<string> normalized_parts = ();
            foreach string part in (path.split("/")) {
                if (!part.size() || part == ".") {
                    continue;
                }
                if (part == "..") {
                    throw "VIRTUAL-SFTP-FS-ERROR", sprintf("%s path %y escapes the virtual root", operation, path);
                }
                normalized_parts += (part,);
            }

            return normalized_parts.empty() ? "/" : "/" + normalized_parts.join("/");
        }

        private string getParentPath(string path) {
            @assert(path[0] == '/');
            if (path == "/") {
                return "/";
            }
            int pos = path.rfind("/");
            return pos <= 0 ? "/" : path.substr(0, pos);
        }

        private string getBaseName(string path) {
            @assert(path[0] == '/');
            if (path == "/") {
                return "/";
            }
            int pos = path.rfind("/");
            return pos < 0 ? path : path.substr(pos + 1);
        }

        private nothing ensureParentDirectories(string path) {
            if (path == "/") {
                return;
            }
            string current = "";
            foreach string part in (normalizePath(path, "ensureParentDirectories").split("/")) {
                if (!part.size()) {
                    continue;
                }
                current += "/" + part;
                if (current == path) {
                    break;
                }
                ensureDirectoryExists(current);
            }
        }

        private nothing ensureDirectoryExists(string path, *hash<auto> metadata) {
            string normalized = normalizePath(path, "ensureDirectoryExists");
            if (files{normalized}) {
                throw "VIRTUAL-SFTP-FS-ERROR",
                    sprintf("cannot create virtual directory %y because a file exists there", normalized);
            }
            if (!directories{normalized}) {
                directories{normalized} = makeDirectoryEntry(metadata);
            } else if (metadata) {
                directories{normalized}.metadata = copyMetadata(metadata);
                directories{normalized}.mtime = getUnixTime();
            }
        }

        private hash<auto> makeDirectoryEntry(*hash<auto> metadata) {
            return {
                "permissions": default_directory_permissions,
                "metadata": copyMetadata(metadata),
                "mtime": getUnixTime(),
                "atime": getUnixTime(),
            };
        }

        private hash<auto> makeFileEntry(binary data, *hash<auto> metadata) {
            return {
                "data": data,
                "permissions": default_file_permissions,
                "metadata": copyMetadata(metadata),
                "mtime": getUnixTime(),
                "atime": getUnixTime(),
            };
        }

        private nothing touchEntry(hash<auto> entry, bool write) {
            entry.atime = getUnixTime();
            if (write) {
                entry.mtime = entry.atime;
            }
        }

        private hash<auto> makeDirectoryStat(string path, hash<auto> dir) {
            return {
                "path": path,
                "exists": True,
                "directory": True,
                "permissions": dir.permissions,
                "size": 0,
                "mtime": dir.mtime,
                "atime": dir.atime,
                "state": getBuiltinState(dir.metadata),
                "metadata": copyMetadata(dir.metadata),
            };
        }

        private hash<auto> makeFileStat(string path, hash<auto> file) {
            return {
                "path": path,
                "exists": True,
                "directory": False,
                "permissions": file.permissions,
                "size": file.data.size(),
                "mtime": file.mtime,
                "atime": file.atime,
                "state": getBuiltinState(file.metadata),
                "metadata": copyMetadata(file.metadata),
            };
        }

        private hash<VirtualSftpEntryInfo> makeListEntry(string name, bool directory, int size, int permissions,
                hash<auto> entry) {
            return <VirtualSftpEntryInfo>{
                "filename": name,
                "long_name": name,
                "directory": directory,
                "size": size,
                "permissions": permissions,
                "mtime": entry.mtime,
                "atime": entry.atime,
                "state": getBuiltinState(entry.metadata),
                "metadata": copyMetadata(entry.metadata),
            };
        }

        private *string getChecksumValue(*hash<auto> metadata) {
            return metadata ? metadata.checksum : NOTHING;
        }

        private *string getChecksumAlgorithmValue(*hash<auto> metadata) {
            return metadata ? metadata.checksum_algorithm : NOTHING;
        }

        private bool directoryEmpty(string path) {
            string prefix = path + "/";
            foreach string dir_path in (keys(directories)) {
                if (dir_path != path && dir_path.size() > prefix.size() && dir_path.substr(0, prefix.size()) == prefix) {
                    return False;
                }
            }
            foreach string file_path in (keys(files)) {
                if (file_path.size() > prefix.size() && file_path.substr(0, prefix.size()) == prefix) {
                    return False;
                }
            }
            return True;
        }

        private nothing archiveFile(string path, *string target_path) {
            *string destination = target_path;
            if (!destination) {
                if (!archive_dir) {
                    files{path}.metadata.archive = True;
                    files{path}.metadata.archived_at = getUnixTime();
                    return;
                }
                destination = archive_dir + "/" + getBaseName(path);
            }
            ensureParentDirectories(destination);
            files{destination} = files{path};
            delete files{path};
            logInfo("virtual file archived: %s -> %s", path, destination);
        }

        private nothing claimFile(string path, *string target_path) {
            if (target_path) {
                ensureParentDirectories(target_path);
                files{target_path} = files{path};
                delete files{path};
                logInfo("virtual file claimed: %s -> %s", path, target_path);
                return;
            }
            files{path}.metadata.claimed = True;
            files{path}.metadata.claimed_at = getUnixTime();
            logInfo("virtual file claimed: %s", path);
        }
    }
}
