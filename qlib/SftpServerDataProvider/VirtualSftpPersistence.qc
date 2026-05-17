public namespace SftpServerDataProvider {
    /** Persistence backend for @ref VirtualSftpFilesystem that supports
        snapshot-based and write-through persistence to a local directory.

        Uses atomic file writes (write to .tmp, rename) to prevent corruption
        on crash.
    */
    public class VirtualSftpPersistenceBackend {
        private {
            string persistence_dir;
            string persistence_mode;
            int snapshot_interval_seconds;
            *LoggerInterface logger;
            string snapshot_path;
            int max_snapshot_bytes;
        }

        constructor(hash<VirtualSftpPersistenceOptions> options, *LoggerInterface logger) {
            if (!options.persistence_dir) {
                throw "VIRTUAL-SFTP-PERSISTENCE-ERROR", "persistence_dir is required";
            }
            persistence_dir = options.persistence_dir;
            persistence_mode = options.persistence_mode ?? "snapshot";
            snapshot_interval_seconds = options.snapshot_interval_seconds ?? 60;
            max_snapshot_bytes = options.max_snapshot_bytes ?? (256 * 1024 * 1024);
            self.logger = logger;
            snapshot_path = persistence_dir + "/vfs-snapshot.json";

            if (persistence_mode != "snapshot" && persistence_mode != "write-through") {
                throw "VIRTUAL-SFTP-PERSISTENCE-ERROR",
                    sprintf("invalid persistence_mode %y; expected \"snapshot\" or \"write-through\"",
                        persistence_mode);
            }

            # ensure persistence directory exists
            if (!is_dir(persistence_dir)) {
                Dir d();
                d.chdir("/");
                list<string> parts = persistence_dir.split("/");
                string current = "";
                foreach string part in (parts) {
                    if (!part.size()) {
                        continue;
                    }
                    current += "/" + part;
                    if (!is_dir(current)) {
                        mkdir(current, 0700);
                    }
                }
            }
        }

        string getMode() {
            return persistence_mode;
        }

        bool isWriteThrough() {
            return persistence_mode == "write-through";
        }

        nothing save(hash<VirtualSftpSnapshot> snapshot) {
            string json_data = make_json(snapshot, JGF_ADD_FORMATTING);
            string tmp_path = snapshot_path + ".tmp";
            {
                File f();
                f.open2(tmp_path, O_CREAT | O_WRONLY | O_TRUNC, 0600);
                f.write(json_data);
            }
            Qore::rename(tmp_path, snapshot_path);
            logDetail(sprintf("persisted snapshot to %s (%d bytes)", snapshot_path, json_data.size()));
        }

        *hash<VirtualSftpSnapshot> restore() {
            if (!is_file(snapshot_path)) {
                logDetail(sprintf("no snapshot file found at %s", snapshot_path));
                return NOTHING;
            }
            # Low/Info: bound the on-disk snapshot before loading it wholesale into memory
            int snapshot_size = hstat(snapshot_path).size;
            if (snapshot_size > max_snapshot_bytes) {
                throw "VIRTUAL-SFTP-PERSISTENCE-ERROR",
                    sprintf("refusing to restore snapshot %s: size %d exceeds max_snapshot_bytes %d",
                        snapshot_path, snapshot_size, max_snapshot_bytes);
            }
            string json_data = ReadOnlyFile::readTextFile(snapshot_path);
            hash<auto> raw = parse_json(json_data);
            logDetail(sprintf("restored snapshot from %s (%d files, %d directories)",
                snapshot_path, raw.file_paths.size(), raw.directory_paths.size()));
            return cast<hash<VirtualSftpSnapshot>>(raw);
        }

        private nothing logDetail(string message) {
            if (logger) {
                try {
                    logger.detail("%s", message);
                } catch (auto e) {
                }
            }
        }
    }
}
