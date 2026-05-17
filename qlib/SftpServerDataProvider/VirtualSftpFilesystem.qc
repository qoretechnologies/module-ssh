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
            hash<auto> symlinks = {};
            *string archive_dir;
            *LoggerInterface logger;
            *VirtualSftpPersistenceBackend persistence;
            Qore::Thread::Mutex state_lock();
            int default_file_permissions = 0100644;
            int default_directory_permissions = 0040755;
            int default_symlink_permissions = 0120777;
            #! M-1: allow-listed real-filesystem roots for submit() source_path reads (fail-closed)
            *softlist<string> allowed_source_path_roots;
            #! M-8: global virtual-filesystem resource caps (independent of any inbound policy)
            *int max_total_bytes;
            *int max_file_count;
            *int max_file_size;
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
                if (options.allowed_source_path_roots) {
                    allowed_source_path_roots = options.allowed_source_path_roots;
                }
                if (exists options.max_total_bytes) {
                    max_total_bytes = options.max_total_bytes;
                }
                if (exists options.max_file_count) {
                    max_file_count = options.max_file_count;
                }
                if (exists options.max_file_size) {
                    max_file_size = options.max_file_size;
                }
                if (*LoggerInterface options_logger = options.logger) {
                    setLogger(options_logger);
                }
                if (*hash<VirtualSftpPersistenceOptions> p_opts = options.persistence) {
                    if (p_opts.persistence_dir) {
                        persistence = new VirtualSftpPersistenceBackend(p_opts, logger);
                        if (p_opts.restore_on_construct) {
                            *hash<VirtualSftpSnapshot> snapshot = persistence.restore();
                            if (snapshot) {
                                restoreFromSnapshot(snapshot);
                            }
                        }
                    }
                }
            }
        }

        *LoggerInterface getLogger() {
            return logger;
        }

        nothing setLogger(*LoggerInterface new_logger) {
            logger = new_logger;
        }

        #! M-1: validate a server-local submit() source_path against the allow-listed roots.
        /** Disabled (fail-closed) unless allowed_source_path_roots is configured; the path is
            symlink-resolved with realpath() and must resolve inside a resolved allowed root. */
        private string confineSourcePath(string source_path, string operation) {
            if (!allowed_source_path_roots) {
                throw "VIRTUAL-SFTP-FS-ERROR",
                    sprintf("%s: reading a local source_path is disabled; set "
                        "allowed_source_path_roots to an allow-listed base directory to enable it",
                        operation);
            }
            string resolved;
            try {
                resolved = realpath(source_path);
            } catch (hash<ExceptionInfo> ex) {
                throw "VIRTUAL-SFTP-FS-ERROR",
                    sprintf("%s: source_path %y cannot be resolved: %s", operation, source_path, ex.desc);
            }
            foreach string root in (allowed_source_path_roots) {
                string canon_root;
                try {
                    canon_root = realpath(root);
                } catch (hash<ExceptionInfo> ex) {
                    continue;
                }
                string prefix = (canon_root == "/") ? "/" : (canon_root + "/");
                if (resolved == canon_root
                        || (resolved.size() >= prefix.size() && resolved.substr(0, prefix.size()) == prefix)) {
                    return resolved;
                }
            }
            throw "VIRTUAL-SFTP-FS-ERROR",
                sprintf("%s: source_path %y resolves outside every allowed source root", operation,
                    source_path);
        }

        #! M-1: confined read of a server-local submission source file
        binary readSourceFile(string source_path, string operation = "submit") {
            return ReadOnlyFile::readBinaryFile(confineSourcePath(source_path, operation));
        }

        #! M-1: confined size lookup for a server-local submission source file
        int sourceFileSize(string source_path, string operation = "submit") {
            return hstat(confineSourcePath(source_path, operation)).size;
        }

        #! Saves the current filesystem state to the configured persistence directory
        nothing saveSnapshot() {
            if (!persistence) {
                throw "VIRTUAL-SFTP-FS-ERROR", "persistence is not configured";
            }
            state_lock.lock();
            on_exit state_lock.unlock();
            persistence.save(exportSnapshotUnlocked("/"));
        }

        nothing clear() {
            state_lock.lock();
            on_exit state_lock.unlock();
            files = {};
            symlinks = {};
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
            enforceCapacity(normalized, data.size());
            files{normalized} = makeFileEntry(data, metadata);
            logDetail("virtual file added: %s (%d bytes)", normalized, data.size());
        }

        nothing addTextFile(string path, string data, *hash<auto> metadata) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "addTextFile");
            ensureParentDirectories(normalized);
            binary b = binary(data);
            enforceCapacity(normalized, b.size());
            files{normalized} = makeFileEntry(b, metadata);
            logDetail("virtual file added: %s (%d bytes)", normalized, b.size());
        }

        bool exists(string path) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "exists");
            return directories{normalized} != NOTHING || files{normalized} != NOTHING
                || symlinks{normalized} != NOTHING;
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
            return exportSnapshotUnlocked(root);
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

        hash<Qore::Ssh::SftpPathInfo> stat(hash<Qore::Ssh::SftpPathRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "stat");
            if (*hash<auto> dir = directories{path}) {
                return cast<hash<Qore::Ssh::SftpPathInfo>>(makeDirectoryStat(path, dir));
            }
            if (*hash<auto> file = files{path}) {
                return cast<hash<Qore::Ssh::SftpPathInfo>>(makeFileStat(path, file));
            }
            if (*hash<auto> link = symlinks{path}) {
                return cast<hash<Qore::Ssh::SftpPathInfo>>(makeSymlinkStat(path, link));
            }
            return <Qore::Ssh::SftpPathInfo>{"path": path, "exists": False};
        }

        hash<Qore::Ssh::SftpListResult> list(hash<Qore::Ssh::SftpPathRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "list");
            *hash<auto> dir = directories{path};
            if (!dir) {
                return <Qore::Ssh::SftpListResult>{"path": path};
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

            foreach string link_path in (sort(keys(symlinks))) {
                if (link_path.size() <= prefix.size() || link_path.substr(0, prefix.size()) != prefix) {
                    continue;
                }
                string relative = link_path.substr(prefix.size());
                if (relative.find("/") >= 0) {
                    continue;
                }
                *hash<auto> child = symlinks{link_path};
                if (!child) {
                    continue;
                }
                hash<VirtualSftpEntryInfo> entry = makeListEntry(relative, False, 0, child.permissions, child);
                entry.symlink = True;
                entry.target_path = child.target_path;
                entries += (entry,);
            }

            return <Qore::Ssh::SftpListResult>{
                "path": path,
                "entries": entries,
            };
        }

        hash<Qore::Ssh::SftpOpenResult> openRead(hash<Qore::Ssh::SftpOpenRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "openRead");
            *hash<auto> file = files{path};
            if (!file) {
                return <Qore::Ssh::SftpOpenResult>{"path": path, "exists": False};
            }
            touchEntry(file, False);
            return <Qore::Ssh::SftpOpenResult>{
                "path": path,
                "exists": True,
                "data": file.data,
                "size": file.data.size(),
                "permissions": file.permissions,
                "metadata": copyMetadata(file.metadata),
            };
        }

        hash<Qore::Ssh::SftpOpenResult> openWrite(hash<Qore::Ssh::SftpOpenRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "openWrite");
            ensureParentDirectories(path);
            return <Qore::Ssh::SftpOpenResult>{
                "path": path,
                "exists": True,
                "permissions": default_file_permissions,
            };
        }

        hash<Qore::Ssh::SftpOperationResult> closeWrite(hash<Qore::Ssh::SftpCloseRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "closeWrite");
            ensureParentDirectories(path);
            binary data = req.data ?? binary();
            *hash<auto> metadata = req.metadata;
            enforceCapacity(path, data.size());
            files{path} = makeFileEntry(data, metadata);
            logDetail("virtual file written: %s (%d bytes)", path, data.size());
            persistIfNeeded();
            return <Qore::Ssh::SftpOperationResult>{
                "path": path,
                "exists": True,
                "completed": True,
            };
        }

        hash<Qore::Ssh::SftpOperationResult> removePath(hash<Qore::Ssh::SftpPathRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "removePath");
            if (files{path}) {
                delete files{path};
                logDetail("virtual file removed: %s", path);
                persistIfNeeded();
                return <Qore::Ssh::SftpOperationResult>{"path": path, "exists": True, "completed": True};
            }
            if (symlinks{path}) {
                delete symlinks{path};
                logDetail("virtual symlink removed: %s", path);
                persistIfNeeded();
                return <Qore::Ssh::SftpOperationResult>{"path": path, "exists": True, "completed": True};
            }
            return <Qore::Ssh::SftpOperationResult>{"path": path, "exists": False};
        }

        hash<Qore::Ssh::SftpOperationResult> rename(hash<Qore::Ssh::SftpRenameRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "rename");
            *string raw_target = req.target_path;
            if (!raw_target || !raw_target.size()) {
                throw "VIRTUAL-SFTP-FS-ERROR", "rename requires target_path";
            }
            string target_path = normalizePath(raw_target, "rename");
            ensureParentDirectories(target_path);

            if (*hash<auto> link = symlinks{path}) {
                symlinks{target_path} = link;
                delete symlinks{path};
                logDetail("virtual symlink renamed: %s -> %s", path, target_path);
                persistIfNeeded();
                return <Qore::Ssh::SftpOperationResult>{"path": target_path, "exists": True, "completed": True};
            }

            if (*hash<auto> file = files{path}) {
                files{target_path} = file;
                delete files{path};
                logDetail("virtual file renamed: %s -> %s", path, target_path);
                persistIfNeeded();
                return <Qore::Ssh::SftpOperationResult>{"path": target_path, "exists": True, "completed": True};
            }

            *hash<auto> dir = directories{path};
            if (!dir) {
                return <Qore::Ssh::SftpOperationResult>{"path": path, "exists": False};
            }
            if (path == "/") {
                throw "VIRTUAL-SFTP-FS-ERROR", "cannot rename the virtual root directory";
            }

            hash<auto> moved_dirs = {};
            hash<auto> moved_files = {};
            hash<auto> moved_symlinks = {};
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
            foreach string link_path in (keys(symlinks)) {
                if (link_path.size() > prefix.size() && link_path.substr(0, prefix.size()) == prefix) {
                    string new_path = target_prefix + link_path.substr(prefix.size());
                    moved_symlinks{new_path} = symlinks{link_path};
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
            foreach string link_path in (keys(symlinks)) {
                if (link_path.size() > prefix.size() && link_path.substr(0, prefix.size()) == prefix) {
                    delete symlinks{link_path};
                }
            }
            foreach string dir_path in (keys(moved_dirs)) {
                directories{dir_path} = moved_dirs{dir_path};
            }
            foreach string file_path in (keys(moved_files)) {
                files{file_path} = moved_files{file_path};
            }
            foreach string link_path in (keys(moved_symlinks)) {
                symlinks{link_path} = moved_symlinks{link_path};
            }

            logDetail("virtual directory renamed: %s -> %s", path, target_path);
            persistIfNeeded();
            return <Qore::Ssh::SftpOperationResult>{"path": target_path, "exists": True, "completed": True};
        }

        hash<Qore::Ssh::SftpOperationResult> mkdir(hash<Qore::Ssh::SftpPathRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "mkdir");
            ensureParentDirectories(path);
            ensureDirectoryExists(path, req.metadata);
            logDetail("virtual directory created: %s", path);
            persistIfNeeded();
            return <Qore::Ssh::SftpOperationResult>{"path": path, "exists": True, "completed": True};
        }

        hash<Qore::Ssh::SftpOperationResult> rmdir(hash<Qore::Ssh::SftpPathRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "rmdir");
            if (path == "/") {
                throw "VIRTUAL-SFTP-FS-ERROR", "cannot remove the virtual root directory";
            }
            if (!directories{path}) {
                return <Qore::Ssh::SftpOperationResult>{"path": path, "exists": False};
            }
            if (!directoryEmpty(path)) {
                throw "VIRTUAL-SFTP-FS-ERROR", sprintf("virtual directory %y is not empty", path);
            }
            delete directories{path};
            logDetail("virtual directory removed: %s", path);
            persistIfNeeded();
            return <Qore::Ssh::SftpOperationResult>{"path": path, "exists": True, "completed": True};
        }

        hash<Qore::Ssh::SftpStatvfsResult> statvfs(hash<Qore::Ssh::SftpPathRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            int file_count = files.size();
            int dir_count = directories.size();
            int link_count = symlinks.size();
            int total_bytes = 0;
            foreach string file_path in (keys(files)) {
                total_bytes += files{file_path}.data.size();
            }
            int bsize = 4096;
            int total_blocks = (total_bytes + bsize - 1) / bsize + 1024;
            int used_blocks = (total_bytes + bsize - 1) / bsize;
            return <Qore::Ssh::SftpStatvfsResult>{
                "f_bsize": bsize,
                "f_frsize": bsize,
                "f_blocks": total_blocks,
                "f_bfree": total_blocks - used_blocks,
                "f_bavail": total_blocks - used_blocks,
                "f_files": file_count + dir_count + link_count,
                "f_ffree": 1000000 - file_count - dir_count - link_count,
                "f_favail": 1000000 - file_count - dir_count - link_count,
                "f_fsid": 0,
                "f_flag": 0,
                "f_namemax": 255,
            };
        }

        nothing addSymlink(string path, string target_path) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string normalized = normalizePath(path, "addSymlink");
            string normalized_target = normalizePath(target_path, "addSymlink");
            ensureParentDirectories(normalized);
            symlinks{normalized} = makeSymlinkEntry(normalized_target);
            logDetail("virtual symlink added: %s -> %s", normalized, normalized_target);
        }

        hash<Qore::Ssh::SftpOperationResult> symlink(hash<Qore::Ssh::SftpSymlinkRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            *string raw_link = req.link_path;
            *string raw_target = req.target_path;
            if (!raw_link || !raw_link.size()) {
                throw "VIRTUAL-SFTP-FS-ERROR", "symlink requires link_path";
            }
            if (!raw_target || !raw_target.size()) {
                throw "VIRTUAL-SFTP-FS-ERROR", "symlink requires target_path";
            }
            string link_path = normalizePath(raw_link, "symlink");
            string target_path = normalizePath(raw_target, "symlink");
            if (files{link_path} || directories{link_path} || symlinks{link_path}) {
                throw "VIRTUAL-SFTP-FS-ERROR", sprintf("symlink path %y already exists", link_path);
            }
            ensureParentDirectories(link_path);
            symlinks{link_path} = makeSymlinkEntry(target_path);
            logDetail("virtual symlink created: %s -> %s", link_path, target_path);
            persistIfNeeded();
            return <Qore::Ssh::SftpOperationResult>{"path": link_path, "exists": True, "completed": True};
        }

        hash<auto> readlink(hash<Qore::Ssh::SftpPathRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "readlink");
            *hash<auto> link = symlinks{path};
            if (!link) {
                return {"path": path, "exists": False};
            }
            return {"path": path, "exists": True, "target_path": link.target_path};
        }

        hash<Qore::Ssh::SftpOperationResult> setstat(hash<Qore::Ssh::SftpSetstatRequest> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "setstat");
            *hash<auto> entry;
            bool is_dir = False;
            if (*hash<auto> dir = directories{path}) {
                entry = dir;
                is_dir = True;
            } else if (*hash<auto> file = files{path}) {
                entry = file;
            } else if (*hash<auto> link = symlinks{path}) {
                entry = link;
            }
            if (!entry) {
                return <Qore::Ssh::SftpOperationResult>{"path": path, "exists": False};
            }

            if (exists req.permissions) {
                entry.permissions = req.permissions;
            }
            if (exists req.atime) {
                entry.atime = req.atime;
            }
            if (exists req.mtime) {
                entry.mtime = req.mtime;
            }

            # write back updated entry
            if (is_dir) {
                directories{path} = entry;
            } else if (files{path}) {
                files{path} = entry;
            } else {
                symlinks{path} = entry;
            }

            logDetail("virtual setstat: %s (flags=%d)", path, req.attr_flags ?? 0);
            return <Qore::Ssh::SftpOperationResult>{"path": path, "exists": True, "completed": True};
        }

        hash<auto> submit(hash<auto> req) {
            state_lock.lock();
            on_exit state_lock.unlock();
            string path = getRequestPath(req, "submit");
            binary data;
            if (*binary req_data = req.data) {
                data = req_data;
            } else if (*string source_path = req.source_path) {
                data = readSourceFile(source_path, "submit");
            } else {
                throw "VIRTUAL-SFTP-FS-ERROR", "submit requires either data or source_path";
            }
            ensureParentDirectories(path);
            enforceCapacity(path, data.size());
            files{path} = makeFileEntry(data, req.metadata);
            logDetail("virtual file added: %s (%d bytes)", path, data.size());
            persistIfNeeded();
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

            persistIfNeeded();
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

        hash<Qore::Ssh::SftpOperationResult> closeWrite(hash<Qore::Ssh::SftpSubmissionRequest> req) {
            return closeWrite(cast<hash<Qore::Ssh::SftpCloseRequest>>(copyTypedRequest(req)));
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

        private nothing persistIfNeeded() {
            if (persistence && persistence.isWriteThrough()) {
                persistence.save(exportSnapshotUnlocked("/"));
            }
        }

        private nothing restoreFromSnapshot(hash<VirtualSftpSnapshot> snapshot) {
            foreach string dir_path in (snapshot.directory_paths) {
                if (!directories{dir_path}) {
                    directories{dir_path} = makeDirectoryEntry();
                }
            }
            foreach string file_path in (keys(snapshot.files)) {
                hash<auto> entry = snapshot.files{file_path};
                # JSON serialization encodes binary as base64 strings; decode if needed
                binary data;
                if (entry.data.typeCode() == NT_STRING) {
                    data = parse_base64_string(entry.data);
                } else if (entry.data.typeCode() == NT_BINARY) {
                    data = entry.data;
                } else {
                    data = binary();
                }
                files{file_path} = {
                    "data": data,
                    "permissions": entry.permissions ?? default_file_permissions,
                    "metadata": entry.metadata ?? {},
                    "mtime": entry.mtime ?? getUnixTime(),
                    "atime": entry.atime ?? getUnixTime(),
                };
            }
        }

        private hash<VirtualSftpSnapshot> exportSnapshotUnlocked(string root) {
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
            # M-3: reject embedded NUL/control characters (a NUL truncates the real path and
            # desyncs audit logs; newlines enable log injection via crafted names) and bound
            # the overall path length
            if (path.size() > 4096) {
                throw "VIRTUAL-SFTP-FS-ERROR", sprintf("%s path is too long (%d bytes)", operation, path.size());
            }
            if (regex(path, "[[:cntrl:]]")) {
                throw "VIRTUAL-SFTP-FS-ERROR",
                    sprintf("%s path contains illegal control characters", operation);
            }

            list<string> normalized_parts = ();
            foreach string part in (path.split("/")) {
                if (!part.size() || part == ".") {
                    continue;
                }
                if (part == "..") {
                    throw "VIRTUAL-SFTP-FS-ERROR", sprintf("%s path %y escapes the virtual root", operation, path);
                }
                if (part.size() > 255) {
                    throw "VIRTUAL-SFTP-FS-ERROR",
                        sprintf("%s path component is too long (%d bytes)", operation, part.size());
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

        # M-8: enforce global virtual-filesystem caps before a file is added/replaced.  Always
        # called with state_lock held.  Independent of any inbound policy so plain client writes
        # to arbitrary virtual paths cannot exhaust server memory.
        private nothing enforceCapacity(string normalized, int new_size) {
            if (exists max_file_size && new_size > max_file_size) {
                throw "VIRTUAL-SFTP-FS-ERROR",
                    sprintf("file size %d exceeds the configured max_file_size %d", new_size,
                        max_file_size);
            }
            bool replacing = exists files{normalized};
            if (exists max_file_count && !replacing && (files.size() + 1) > max_file_count) {
                throw "VIRTUAL-SFTP-FS-ERROR",
                    sprintf("virtual filesystem file-count limit reached (max_file_count=%d)",
                        max_file_count);
            }
            if (exists max_total_bytes) {
                int existing = replacing ? files{normalized}.data.size() : 0;
                int total = 0;
                foreach auto entry in (files.values()) {
                    total += entry.data.size();
                }
                int projected = total - existing + new_size;
                if (projected > max_total_bytes) {
                    throw "VIRTUAL-SFTP-FS-ERROR",
                        sprintf("virtual filesystem total-size limit exceeded: %d > "
                            "max_total_bytes %d", projected, max_total_bytes);
                }
            }
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

        private hash<auto> makeSymlinkEntry(string target_path, *hash<auto> metadata) {
            return {
                "target_path": target_path,
                "permissions": default_symlink_permissions,
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
                "metadata": copyMetadata(file.metadata),
            };
        }

        private hash<auto> makeSymlinkStat(string path, hash<auto> link) {
            return {
                "path": path,
                "exists": True,
                "directory": False,
                "symlink": True,
                "target_path": link.target_path,
                "permissions": link.permissions,
                "size": 0,
                "mtime": link.mtime,
                "atime": link.atime,
                "metadata": copyMetadata(link.metadata),
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
            foreach string link_path in (keys(symlinks)) {
                if (link_path.size() > prefix.size() && link_path.substr(0, prefix.size()) == prefix) {
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
