# Copyright 2026 Qore Technologies, s.r.o.
public namespace SftpServerDataProvider {
    #! Endpoint agreement for a configured staged exchange.
    public hashdecl SftpPublicationCapabilities {
        int protocol_version = 3;
        string staging_directory = "/staging";
        string final_directory = "/inbound";
        string collision_policy = "no-replace";
        bool durable_publications = True;
        bool durable_staging = False;
        bool sequential_writes = True;
    }

    #! Immutable receipt for one completed rename, ordered within a publication database.
    public hashdecl SftpPublicationInfo {
        string publication_id;
        int version;
        string principal;
        string final_name;
        string staging_name;
        int byte_count;
        int committed_at;
        *string digest;
    }

    #! Metadata-only evidence. Only a published event carries an immutable receipt.
    public hashdecl SftpUploadEvent {
        string kind;
        string principal;
        string path;
        *hash<SftpPublicationInfo> publication;
    }

    #! Principal-private SFTP staging and durable immutable publication.
    /** Attach one instance to a listener and to its consumers. The endpoint accepts
        sequential writes under /staging and ordinary SFTP v3 rename into /inbound.
        @par Example
        @code{.py}
        StagedSftpExchange exchange("/srv/exchange/receipts.sqlite");
        @endcode
    */
    public class StagedSftpExchange {
        private {
            Datasource db;
            *code<nothing(hash<SftpUploadEvent>)> observer;
            *LoggerInterface logger;
            const Columns = "publication_id, version, principal, final_name, staging_name, byte_count, committed_at";
        }

        #! Opens a dedicated SQLite file in an operator-controlled directory.
        /** @param database absolute filename, reused on restart
            @param observer optional synchronous metadata observer
            @param logger optional destination for observer failures
            @throw SFTP-PUBLICATION-ERROR the database path is invalid
        */
        constructor(string database, *code<nothing(hash<SftpUploadEvent>)> observer, *LoggerInterface logger) {
            if (!database.startsWith("/") || database.endsWith("/")) {
                throw "SFTP-PUBLICATION-ERROR", "an absolute publication database filename is required";
            }
            self.observer = observer;
            self.logger = logger;
            db = new Datasource("sqlite3", NOTHING, NOTHING, database);
            on_error db.rollback();
            db.exec("create table if not exists publications (version integer primary key, "
                "publication_id text unique not null, principal text not null, final_name text not null, "
                "staging_name text not null, byte_count integer not null, committed_at integer not null, "
                "unique(principal, final_name))");
            db.exec("create table if not exists publication_chunks (id text not null, pos integer not null, "
                "data blob not null, primary key(id, pos))");
            db.exec("create temp table staging (id text primary key, principal text not null, name text not null, "
                "size integer not null default 0, closed integer not null default 0, unique(principal, name))");
            db.exec("create temp table stage_chunks (id text not null, pos integer not null, data blob not null, "
                "primary key(id, pos))");
            db.commit();
        }

        #! Returns the server-side agreement used to configure a cooperating producer.
        /** @return the SFTP version, namespaces, collision policy and recovery guarantees */
        hash<SftpPublicationCapabilities> getPublicationCapabilities() {
            return <SftpPublicationCapabilities>{};
        }

        private static string owner(*hash<Qore::Ssh::SftpSessionInfo> session) {
            if (!session.principal) {
                throw "SFTP-PUBLICATION-DENIED", "an authenticated principal is required";
            }
            return session.principal;
        }

        private static string member(string path, string directory) {
            string prefix = directory + "/";
            string name = path.substr(prefix.size());
            if (!path.startsWith(prefix) || !name || name == "." || name == ".." || name.find("/") >= 0
                    || name.find("\0") >= 0) {
                throw "SFTP-PUBLICATION-DENIED", sprintf("expected a single filename under %s", directory);
            }
            return name;
        }

        private nothing emit(string kind, string principal, string path, *hash<SftpPublicationInfo> receipt) {
            if (observer) {
                try {
                    observer(<SftpUploadEvent>{"kind": kind, "principal": principal, "path": path,
                        "publication": receipt});
                } catch (hash<ExceptionInfo> ex) {
                    if (logger) {
                        try {
                            logger.error("SFTP upload observer failed: %s", ex.err);
                        } catch (hash<ExceptionInfo> logging_error) {
                            # Notification sinks cannot change an already committed transaction.
                        }
                    }
                }
            }
        }

        #! Reserves an exclusive staging name for the authenticated principal.
        /** @param req requested staging path, open flags and authenticated session
            @return an exclusive backend handle
            @throw SFTP-PUBLICATION-ERROR the name is already in use
        */
        hash<Qore::Ssh::SftpOpenResult> openWrite(hash<Qore::Ssh::SftpOpenRequest> req) {
            string principal = owner(req.session_info);
            on_error emit("rejected", principal, req.path);
            # SFTP v3 requires WRITE (2) and CREAT (8). READ (1) and APPEND (4) are incompatible.
            if (req.pflags.typeCode() == NT_INT && ((req.pflags & 10) != 10 || (req.pflags & 5))) {
                throw "SFTP-PUBLICATION-DENIED", "staging supports write-only sequential uploads";
            }
            string name = member(req.path, "/staging");
            return <Qore::Ssh::SftpOpenResult>{"path": req.path, "backend_handle": reserve(principal, name)};
        }

        private synchronized string reserve(string principal, string name) {
            on_error db.rollback();
            string id = db.selectRow("select lower(hex(randomblob(16))) as id").id;
            if (db.exec("insert or ignore into staging(id, principal, name) values (%v, %v, %v)",
                    id, principal, name) != 1) {
                throw "SFTP-PUBLICATION-ERROR", "staging filename is already reserved";
            }
            db.commit();
            return id;
        }

        #! Adds one consecutive chunk to a still-open reservation.
        /** @param req open handle, exact next offset and data
            @return the observed byte count for this chunk
            @throw SFTP-PUBLICATION-ERROR invalid handle or offset
        */
        hash<auto> write(hash<Qore::Ssh::SftpWriteRequest> req) {
            string principal = owner(req.session_info);
            string name = member(req.path, "/staging");
            on_error {
                discard(principal, name, req.backend_handle);
                emit("rejected", principal, req.path);
            }
            appendChunk(principal, name, req);
            return {"written": req.data.size()};
        }

        private synchronized nothing appendChunk(string principal, string name, hash<Qore::Ssh::SftpWriteRequest> req) {
            on_error db.rollback();
            int size = req.data.size();
            int changed = db.exec("update staging set size = size + %v where id = %v and principal = %v "
                "and name = %v and size = %v and closed = 0", size, req.backend_handle, principal, name, req.offset);
            if (changed != 1) {
                throw "SFTP-PUBLICATION-ERROR", "invalid staging handle or nonconsecutive write";
            }
            if (size) {
                db.exec("insert into stage_chunks values (%v, %v, %v)", req.backend_handle, req.offset, req.data);
            }
            db.commit();
        }

        #! Ends staging. The principal can reconnect and rename the completed member.
        /** @param req staging handle from openWrite()
            @return the closed staging path
            @throw SFTP-PUBLICATION-ERROR the handle is stale
        */
        hash<Qore::Ssh::SftpOperationResult> closeWrite(hash<Qore::Ssh::SftpCloseRequest> req) {
            string principal = owner(req.session_info);
            string name = member(req.path, "/staging");
            if (req.data.typeCode() != NT_NOTHING) {
                discard(principal, name, req.backend_handle);
                emit("rejected", principal, req.path);
                throw "SFTP-PUBLICATION-ERROR", "staged uploads must supply all data through write()";
            }
            finish(principal, name, req.backend_handle);
            emit("staged", principal, req.path);
            return <Qore::Ssh::SftpOperationResult>{"path": req.path, "completed": True};
        }

        private synchronized nothing finish(string principal, string name, string id) {
            on_error db.rollback();
            if (db.exec("update staging set closed = 1 where id = %v and principal = %v and name = %v "
                    "and closed = 0", id, principal, name) != 1) {
                throw "SFTP-PUBLICATION-ERROR", "staging handle is no longer open";
            }
            db.commit();
        }

        #! Discards an open reservation by identity. Repeated cleanup is safe.
        /** @param req original staging handle and principal
            @return cleanup completion, including when already discarded
            @throw SFTP-PUBLICATION-DENIED invalid principal or path
        */
        hash<Qore::Ssh::SftpOperationResult> abortWrite(hash<Qore::Ssh::SftpCloseRequest> req) {
            string principal = owner(req.session_info);
            if (discard(principal, member(req.path, "/staging"), req.backend_handle)) {
                emit("abandoned", principal, req.path);
            }
            return <Qore::Ssh::SftpOperationResult>{"completed": True};
        }

        private synchronized bool discard(string principal, string name, string id) {
            on_error db.rollback();
            int changed = db.exec("delete from staging where principal = %v and name = %v and id = %v and closed = 0",
                principal, name, id);
            if (changed) {
                db.exec("delete from stage_chunks where id = %v", id);
            }
            db.commit();
            return changed == 1;
        }

        #! Commits a closed stage and returns its publication facts in the backend result metadata.
        /** @param req source and destination in the authenticated namespace
            @return the receipt in the operation metadata
            @throw SFTP-PUBLICATION-ERROR the stage or destination cannot be committed
        */
        hash<Qore::Ssh::SftpOperationResult> rename(hash<Qore::Ssh::SftpRenameRequest> req) {
            string principal = owner(req.session_info);
            hash<SftpPublicationInfo> receipt = commitPublication(principal, member(req.path, "/staging"),
                member(req.target_path, "/inbound"));
            return <Qore::Ssh::SftpOperationResult>{"path": req.target_path, "completed": True, "metadata": receipt};
        }

        #! Commits a completed member from a trusted application.
        /** @param principal authenticated owner of both names
            @param staging_name closed staging filename
            @param final_name unused logical destination filename
            @return the immutable receipt previously made visible in the database
            @throw SFTP-PUBLICATION-ERROR the stage is incomplete or the destination exists
        */
        hash<SftpPublicationInfo> commitPublication(string principal, string staging_name, string final_name) {
            on_error emit("rejected", principal, "/staging/" + staging_name);
            hash<SftpPublicationInfo> receipt = publish(principal, member("/staging/" + staging_name, "/staging"),
                member("/inbound/" + final_name, "/inbound"));
            emit("published", principal, "/inbound/" + final_name, receipt);
            return receipt;
        }

        #! Removes a completed, unpublished stage. A published member cannot be removed over SFTP.
        /** @param req a closed staging member in the authenticated namespace
            @return whether a stage was removed
            @throw SFTP-PUBLICATION-DENIED the path is outside staging
        */
        synchronized hash<Qore::Ssh::SftpOperationResult> removePath(hash<Qore::Ssh::SftpPathRequest> req) {
            string name = member(req.path, "/staging");
            on_error db.rollback();
            *hash<auto> row = db.selectRow("select id from staging where principal = %v and name = %v and closed = 1",
                owner(req.session_info), name);
            if (row) {
                db.exec("delete from stage_chunks where id = %v", row.id);
                db.exec("delete from staging where id = %v", row.id);
            }
            db.commit();
            return <Qore::Ssh::SftpOperationResult>{"path": req.path, "completed": row != NOTHING};
        }

        private synchronized hash<SftpPublicationInfo> publish(string principal, string name, string final_name) {
            on_error db.rollback();
            # A single unique insert arbitrates concurrent publishers, including other database connections.
            int changed = db.exec("insert or ignore into publications "
                "(publication_id, principal, staging_name, final_name, byte_count, committed_at) "
                "select id, principal, name, %v, size, 0 from staging "
                "where principal = %v and name = %v and closed = 1", final_name, principal, name);
            if (changed != 1) {
                throw "SFTP-PUBLICATION-ERROR", "a closed stage and an unused final name are required";
            }
            hash<SftpPublicationInfo> receipt = cast<hash<SftpPublicationInfo>>(db.selectRow("select " + Columns
                + " from publications where principal = %v and final_name = %v", principal, final_name));
            # Bound each copy statement so a large publication can be interrupted between chunks of work.
            for (int pos = 0; pos < receipt.byte_count; pos += 1048576) {
                db.exec("insert into publication_chunks select * from stage_chunks where id = %v and pos >= %v "
                    "and pos < %v", receipt.publication_id, pos, pos + 1048576);
            }
            db.exec("delete from stage_chunks where id = %v", receipt.publication_id);
            db.exec("delete from staging where id = %v", receipt.publication_id);
            receipt.committed_at = clock_getseconds();
            db.exec("update publications set committed_at = %v where publication_id = %v",
                receipt.committed_at, receipt.publication_id);
            db.commit();
            return receipt;
        }

        #! Enumerates committed metadata in increasing version order for one principal.
        /** @param principal authenticated exchange principal
            @param after_version exclusive cursor, initially zero
            @param limit maximum receipts per page (1 to 1000)
            @return a page of immutable receipts, including after a process restart
            @throw SFTP-PUBLICATION-ERROR invalid principal, cursor or page size
        */
        synchronized list<hash<SftpPublicationInfo>> listPublications(string principal, int after_version = 0,
                int limit = 100) {
            if (!principal || after_version < 0 || limit < 1 || limit > 1000) {
                throw "SFTP-PUBLICATION-ERROR", "invalid publication query";
            }
            on_error db.rollback();
            list<hash<SftpPublicationInfo>> result = ();
            foreach hash<auto> row in (db.selectRows("select " + Columns + " from publications where principal = %v "
                    "and version > %v order by version limit %v", principal, after_version, limit)) {
                result += cast<hash<SftpPublicationInfo>>(row);
            }
            db.commit();
            return result;
        }

        #! Looks up private stages or published members without reading payload bytes.
        /** @param req virtual path and authenticated session
            @return existence, type and observed size
            @throw SFTP-PUBLICATION-DENIED invalid principal or member
        */
        synchronized hash<Qore::Ssh::SftpPathInfo> stat(hash<Qore::Ssh::SftpPathRequest> req) {
            string principal = owner(req.session_info);
            if (req.path == "/" || req.path == "/staging" || req.path == "/inbound") {
                return <Qore::Ssh::SftpPathInfo>{"path": req.path, "exists": True, "directory": True};
            }
            on_error db.rollback();
            *hash<auto> row;
            if (req.path.startsWith("/staging/")) {
                row = db.selectRow("select size from staging where principal = %v and name = %v", principal,
                    member(req.path, "/staging"));
            } else if (req.path.startsWith("/inbound/")) {
                row = db.selectRow("select byte_count as size from publications where principal = %v and final_name = %v",
                    principal, member(req.path, "/inbound"));
            }
            db.commit();
            return <Qore::Ssh::SftpPathInfo>{"path": req.path, "exists": row != NOTHING, "size": row.size};
        }

        #! Lists the authenticated principal's files under the requested directory.
        /** @param req directory and authenticated session
            @return directory entries visible to the caller
            @throw SFTP-PUBLICATION-DENIED unknown directory or principal
        */
        synchronized hash<Qore::Ssh::SftpListResult> list(hash<Qore::Ssh::SftpPathRequest> req) {
            string principal = owner(req.session_info);
            on_error db.rollback();
            list<hash<auto>> entries;
            switch (req.path) {
                case "/":
                    entries = ({"filename": "staging", "directory": True}, {"filename": "inbound", "directory": True});
                    break;
                case "/staging":
                    entries = db.selectRows("select name as filename, size from staging where principal = %v "
                        "order by name", principal);
                    break;
                case "/inbound":
                    entries = db.selectRows("select final_name as filename, byte_count as size from publications "
                        "where principal = %v order by version", principal);
                    break;
                default:
                    throw "SFTP-PUBLICATION-DENIED", "unknown exchange directory";
            }
            db.commit();
            return <Qore::Ssh::SftpListResult>{"path": req.path, "entries": entries};
        }

        #! Opens an immutable published member for streamed reading.
        /** @param req published filename and authenticated session
            @return existence and an immutable read handle
            @throw SFTP-PUBLICATION-DENIED invalid namespace or principal
        */
        synchronized hash<Qore::Ssh::SftpOpenResult> openRead(hash<Qore::Ssh::SftpOpenRequest> req) {
            on_error db.rollback();
            *hash<auto> row = db.selectRow("select publication_id, byte_count from publications "
                "where principal = %v and final_name = %v", owner(req.session_info), member(req.path, "/inbound"));
            db.commit();
            return <Qore::Ssh::SftpOpenResult>{"path": req.path, "exists": row != NOTHING,
                "backend_handle": row.publication_id, "size": row.byte_count};
        }

        #! Reads a bounded slice at a byte offset from one committed identity.
        /** @param principal owner of the publication
            @param id immutable publication ID
            @param offset first byte to read
            @param length maximum bytes to return
            @return bytes from one stored chunk, or an empty binary at EOF
            @throw SFTP-PUBLICATION-DENIED unknown publication for this principal
            @throw SFTP-PUBLICATION-ERROR negative offset or length
        */
        synchronized binary readPublication(string principal, string id, int offset, int length) {
            if (offset < 0 || length < 0) {
                throw "SFTP-PUBLICATION-ERROR", "invalid read offset or length";
            }
            on_error db.rollback();
            *hash<auto> row = db.selectRow("select (select substr(data, %v - pos + 1, %v) from publication_chunks "
                "where id = publication_id and pos <= %v order by pos desc limit 1) as data from publications "
                "where principal = %v and publication_id = %v", offset, min(length, 65536), offset, principal, id);
            if (!row) {
                throw "SFTP-PUBLICATION-DENIED", "unknown publication for this principal";
            }
            db.commit();
            return row.data.typeCode() == NT_BINARY ? row.data : binary();
        }

        #! Services a read bound to the original principal and publication identity.
        /** @param req read handle, offset and requested length
            @return one bounded data chunk or EOF
            @throw SFTP-PUBLICATION-DENIED unknown publication for the principal
        */
        hash<Qore::Ssh::SftpReadResult> read(hash<Qore::Ssh::SftpReadRequest> req) {
            binary data = readPublication(owner(req.session_info), req.backend_handle, req.offset, req.length);
            return <Qore::Ssh::SftpReadResult>{"data": data, "eof": !data.size()};
        }

        #! Releases a read capability. Reads hold no database cursor between requests.
        /** @param req the original read path
            @return read completion status
        */
        hash<Qore::Ssh::SftpOperationResult> closeRead(hash<Qore::Ssh::SftpCloseRequest> req) {
            return <Qore::Ssh::SftpOperationResult>{"path": req.path, "completed": True};
        }
    }
}
