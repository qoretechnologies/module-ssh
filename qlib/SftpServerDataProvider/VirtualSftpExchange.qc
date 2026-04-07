public namespace SftpServerDataProvider {
    /** Virtual inbound/outbound exchange backend built on top of
        @ref SftpServerDataProvider::VirtualSftpFilesystem.

        This class adds explicit inbound, outbound, archive, and claim areas,
        typed helper APIs, live-upload policy enforcement, and provider/event
        integration for managed SFTP exchange flows.
    */
    public class VirtualSftpExchange {
        private {
            VirtualSftpFilesystem vfs;
            string inbound_dir = "/inbound";
            string outbound_dir = "/outbound";
            *string archive_dir;
            *string claim_dir;
            *hash<VirtualSftpInboundPolicy> inbound_policy;
            *hash<VirtualSftpRetentionPolicy> inbound_retention_policy;
            *hash<VirtualSftpRetentionPolicy> archive_retention_policy;
            *hash<VirtualSftpRetentionPolicy> claim_retention_policy;
            string inbound_event_payload_mode = InboundEventPayloadNone;
            bool generate_inbound_checksum = False;
            *LoggerInterface logger;
            Qore::Thread::Mutex event_lock();
            hash<auto> inbound_event_listeners = {};
            int next_inbound_event_listener_id = 1;
            hash<auto> outbound_event_listeners = {};
            int next_outbound_event_listener_id = 1;
            Qore::Thread::Mutex ownership_lock();
            hash<auto> inbound_file_owners = {};
            Qore::Thread::Mutex upload_lock();
            hash<auto> active_inbound_uploads = {};
            int next_inbound_upload_id = 1;
        }

        constructor(*hash<VirtualSftpExchangeOptions> options) {
            hash<VirtualSftpFilesystemOptions> vfs_options = <VirtualSftpFilesystemOptions>{};
            if (options) {
                if (*string in_dir = options.inbound_dir) {
                    inbound_dir = normalizeDirectory(in_dir, "inbound_dir");
                }
                if (*string out_dir = options.outbound_dir) {
                    outbound_dir = normalizeDirectory(out_dir, "outbound_dir");
                }
                if (*string archive_path = options.archive_dir) {
                    archive_dir = normalizeDirectory(archive_path, "archive_dir");
                    vfs_options.archive_dir = archive_dir;
                }
                if (*string claim_path = options.claim_dir) {
                    claim_dir = normalizeDirectory(claim_path, "claim_dir");
                }
                if (*hash<VirtualSftpInboundPolicy> policy = options.inbound_policy) {
                    inbound_policy = policy;
                }
                if (*hash<VirtualSftpRetentionPolicy> policy = options.inbound_retention_policy) {
                    inbound_retention_policy = policy;
                }
                if (*hash<VirtualSftpRetentionPolicy> policy = options.archive_retention_policy) {
                    archive_retention_policy = policy;
                }
                if (*hash<VirtualSftpRetentionPolicy> policy = options.claim_retention_policy) {
                    claim_retention_policy = policy;
                }
                if (*string payload_mode = options.inbound_event_payload_mode) {
                    inbound_event_payload_mode = normalizeInboundEventPayloadMode(payload_mode);
                }
                if (options.generate_inbound_checksum != NOTHING) {
                    generate_inbound_checksum = options.generate_inbound_checksum;
                }
                if (*LoggerInterface options_logger = options.logger) {
                    logger = options_logger;
                    vfs_options.logger = options_logger;
                }
                if (options.default_file_permissions != NOTHING) {
                    vfs_options.default_file_permissions = options.default_file_permissions;
                }
                if (options.default_directory_permissions != NOTHING) {
                    vfs_options.default_directory_permissions = options.default_directory_permissions;
                }
            }

            vfs = new VirtualSftpFilesystem(vfs_options.empty() ? NOTHING : vfs_options);
            vfs.addDirectory(inbound_dir, {"exchange_role": "inbound"});
            vfs.addDirectory(outbound_dir, {"exchange_role": "outbound"});
            if (archive_dir) {
                vfs.addDirectory(archive_dir, {"exchange_role": "archive"});
            }
            if (claim_dir) {
                vfs.addDirectory(claim_dir, {"exchange_role": "claim"});
            }
        }

        *LoggerInterface getLogger() {
            return logger;
        }

        nothing setLogger(*LoggerInterface new_logger) {
            logger = new_logger;
            vfs.setLogger(new_logger);
        }

        object getBackend() {
            return self;
        }

        VirtualSftpFilesystem getFilesystem() {
            return vfs;
        }

        string getInboundDir() {
            return inbound_dir;
        }

        string getOutboundDir() {
            return outbound_dir;
        }

        string getArchiveDir() {
            return archive_dir;
        }

        string getClaimDir() {
            return claim_dir;
        }

        *hash<VirtualSftpInboundPolicy> getInboundPolicy() {
            return inbound_policy;
        }

        *hash<VirtualSftpRetentionPolicy> getInboundRetentionPolicy() {
            return inbound_retention_policy;
        }

        *hash<VirtualSftpRetentionPolicy> getArchiveRetentionPolicy() {
            return archive_retention_policy;
        }

        *hash<VirtualSftpRetentionPolicy> getClaimRetentionPolicy() {
            return claim_retention_policy;
        }

        string getInboundEventPayloadMode() {
            return inbound_event_payload_mode;
        }

        bool getGenerateInboundChecksum() {
            return generate_inbound_checksum;
        }

        int registerInboundEventListener(code<nothing(hash<VirtualSftpInboundEventInfo>)> listener) {
            event_lock.lock();
            on_exit event_lock.unlock();
            int id = next_inbound_event_listener_id++;
            inbound_event_listeners{id} = listener;
            return id;
        }

        bool deregisterInboundEventListener(int id) {
            event_lock.lock();
            on_exit event_lock.unlock();
            return exists(remove inbound_event_listeners{id});
        }

        int registerOutboundEventListener(code<nothing(hash<VirtualSftpOutboundEventInfo>)> listener) {
            event_lock.lock();
            on_exit event_lock.unlock();
            int id = next_outbound_event_listener_id++;
            outbound_event_listeners{id} = listener;
            return id;
        }

        bool deregisterOutboundEventListener(int id) {
            event_lock.lock();
            on_exit event_lock.unlock();
            return exists(remove outbound_event_listeners{id});
        }

        nothing addOutboundData(string name, binary data, *hash<auto> metadata) {
            vfs.addFile(resolveEntryPath(name, outbound_dir, "addOutboundData"), data, metadata);
        }

        nothing addOutboundText(string name, string data, *hash<auto> metadata) {
            addOutboundData(name, binary(data), metadata);
        }

        nothing addInboundData(string name, binary data, *hash<auto> metadata) {
            string path = resolveEntryPath(name, inbound_dir, "addInboundData");
            validateInboundAcceptance(path, data.size(), "addInboundData", EventSourceHelper, metadata, NOTHING, data,
                NOTHING, NOTHING);
            vfs.addFile(path, data, metadata);
            setInboundFileOwner(path, NOTHING);
            applyRetentionMetadata(path, RetentionQueueInbound);
            *hash<auto> checksum_info = getAcceptedChecksumInfo(data);
            persistAcceptedChecksum(path, checksum_info);
            emitInboundAcceptedEvent(name, path, data.size(), data, metadata, checksum_info,
                NOTHING, EventSourceHelper, NOTHING);
        }

        nothing addInboundText(string name, string data, *hash<auto> metadata) {
            addInboundData(name, binary(data), metadata);
        }

        binary getOutboundData(string name) {
            return vfs.getFileData(resolveEntryPath(name, outbound_dir, "getOutboundData"));
        }

        binary getInboundData(string name) {
            return vfs.getFileData(resolveEntryPath(name, inbound_dir, "getInboundData"));
        }

        list<hash<VirtualSftpEntryInfo>> listOutbound() {
            return vfs.list({"path": outbound_dir}).entries ?? ();
        }

        list<hash<VirtualSftpEntryInfo>> listInbound() {
            return vfs.list({"path": inbound_dir}).entries ?? ();
        }

        hash<VirtualSftpRecordInfo> claimOutbound(string name, *string claimed_name, *hash<auto> metadata) {
            string source_path = resolveEntryPath(name, outbound_dir, "claimOutbound");
            *hash<auto> checksum_info = getChecksumInfoForPath(source_path);
            hash<auto> result = completeRetrieve({
                "path": source_path,
                "target_path": claimed_name ? resolveClaimTarget(claimed_name) : NOTHING,
                "completion_mode": "claim",
                "metadata": metadata ?? {},
            });
            return makeCompletionRecord("outbound", name, result.path, "claim", claimed_name ?? name, metadata,
                checksum_info ? checksum_info.checksum : NOTHING,
                checksum_info ? checksum_info.checksum_algorithm : NOTHING);
        }

        hash<VirtualSftpRecordInfo> archiveOutbound(string name, *string archived_name, *hash<auto> metadata) {
            string source_path = resolveEntryPath(name, outbound_dir, "archiveOutbound");
            *hash<auto> checksum_info = getChecksumInfoForPath(source_path);
            hash<auto> result = completeRetrieve({
                "path": source_path,
                "target_path": archived_name ? resolveArchiveTarget(archived_name) : NOTHING,
                "completion_mode": "archive",
                "metadata": metadata ?? {},
            });
            return makeCompletionRecord("outbound", name, result.path, "archive", archived_name ?? name, metadata,
                checksum_info ? checksum_info.checksum : NOTHING,
                checksum_info ? checksum_info.checksum_algorithm : NOTHING);
        }

        hash<VirtualSftpRecordInfo> deleteOutbound(string name, *hash<auto> metadata) {
            string source_path = resolveEntryPath(name, outbound_dir, "deleteOutbound");
            *hash<auto> checksum_info = getChecksumInfoForPath(source_path);
            hash<auto> result = completeRetrieve({
                "path": source_path,
                "completion_mode": "delete",
                "metadata": metadata ?? {},
            });
            @assert(result.completed);
            return makeCompletionRecord("outbound", name, NOTHING, "delete", name, metadata,
                checksum_info ? checksum_info.checksum : NOTHING,
                checksum_info ? checksum_info.checksum_algorithm : NOTHING);
        }

        hash<auto> stat(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_path = resolved.path;
            if (*string req_path = resolved.path) {
                resolved.path = translateInboundPathForSession(req_path, session_info, False, "stat");
            }
            hash<auto> result = vfs.stat(resolved);
            if (visible_path) {
                result.path = visible_path;
            }
            return result;
        }

        hash<auto> list(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            if (!resolved.path || resolved.path == ".") {
                resolved.path = "/";
            }
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            string visible_path = resolved.path;
            resolved.path = translateInboundPathForSession(resolved.path, session_info, False, "list");
            hash<auto> result = vfs.list(resolved);
            result.path = visible_path;
            return result;
        }

        hash<auto> openRead(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_path = resolved.path;
            if (*string req_path = resolved.path) {
                resolved.path = translateInboundPathForSession(req_path, session_info, False, "openRead");
            }
            hash<auto> result = vfs.openRead(resolved);
            if (visible_path) {
                result.path = visible_path;
            }
            return result;
        }

        hash<auto> openWrite(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string upload_handle;
            if (*string req_path = resolved.path) {
                string path = normalizeAbsolutePath(req_path, "openWrite");
                if (isInboundPath(path)) {
                    string routed_path = translateInboundPathForSession(path, session_info, True, "openWrite");
                    hash<auto> policy_context = getInboundPolicyContext(routed_path, session_info, "openWrite");
                    validateInboundAcceptance(routed_path, NOTHING, "openWrite", EventSourceSftp, resolved.metadata,
                        session_info, NOTHING, policy_context, NOTHING);
                    upload_handle = reserveInboundUpload(routed_path, session_info, policy_context, "openWrite",
                        EventSourceSftp, resolved.metadata);
                    resolved.path = routed_path;
                }
            }
            on_exit {
                if (upload_handle) {
                    releaseInboundUpload(upload_handle, resolved.path);
                }
            }
            hash<auto> result = vfs.openWrite(resolved);
            if (upload_handle) {
                result.backend_handle = upload_handle;
                upload_handle = NOTHING;
            }
            if (req.path != NOTHING) {
                result.path = req.path;
            }
            return result;
        }

        hash<auto> closeWrite(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string upload_handle = resolved.backend_handle;
            if (*string req_path = resolved.path) {
                string path = normalizeAbsolutePath(req_path, "closeWrite");
                if (isInboundPath(path)) {
                    string routed_path = translateInboundPathForSession(path, session_info, True, "closeWrite");
                    hash<auto> policy_context = getInboundPolicyContext(routed_path, session_info, "closeWrite");
                    validateInboundAcceptance(routed_path, resolved.data != NOTHING ? resolved.data.size() : 0,
                        "closeWrite", EventSourceSftp, resolved.metadata, session_info, resolved.data, policy_context,
                        NOTHING);
                    resolved.path = routed_path;
                }
            }
            on_exit {
                if (resolved.path && isInboundPath(resolved.path)) {
                    releaseInboundUpload(upload_handle, resolved.path);
                }
            }
            hash<auto> result = vfs.closeWrite(resolved);
            string path = result.path ?? resolved.path;
            if (path && isInboundPath(path)) {
                setInboundFileOwner(path, getSessionPrincipal(session_info));
                applyRetentionMetadata(path, RetentionQueueInbound, NOTHING, getSessionPrincipal(session_info));
                *hash<auto> checksum_info = getAcceptedChecksumInfo(resolved.data);
                applyChecksumInfoToTransferInfo(result.transfer_info, checksum_info);
                persistAcceptedChecksum(path, checksum_info);
                if (checksum_info) {
                    result.checksum = checksum_info.checksum;
                    result.checksum_algorithm = checksum_info.checksum_algorithm;
                }
                emitInboundAcceptedEvent(getBaseName(path), path, resolved.data != NOTHING ? resolved.data.size() : 0,
                    resolved.data, resolved.metadata, checksum_info,
                    result.transfer_info, EventSourceSftp, session_info);
            }
            if (req.path != NOTHING) {
                result.path = req.path;
            }
            return result;
        }

        hash<auto> removePath(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_path = resolved.path;
            if (*string req_path = resolved.path) {
                resolved.path = translateInboundPathForSession(req_path, session_info, False, "removePath");
            }
            hash<auto> result = vfs.removePath(resolved);
            if (result.completed && resolved.path && isInboundPath(resolved.path)) {
                removeInboundFileOwner(resolved.path);
            }
            if (visible_path) {
                result.path = visible_path;
            }
            return result;
        }

        hash<auto> rename(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_path = resolved.path;
            *string visible_target_path = resolved.target_path;
            if (*string req_path = resolved.path) {
                resolved.path = translateInboundPathForSession(req_path, session_info, False, "rename source");
            }
            if (*string req_target_path = resolved.target_path) {
                resolved.target_path = translateInboundPathForSession(req_target_path, session_info, True,
                    "rename target");
            }
            hash<auto> result = vfs.rename(resolved);
            if (result.completed && resolved.path && resolved.target_path) {
                bool source_inbound = isInboundPath(resolved.path);
                bool target_inbound = isInboundPath(resolved.target_path);
                if (source_inbound && target_inbound) {
                    moveInboundOwnersUnder(resolved.path, resolved.target_path);
                } else if (source_inbound) {
                    removeInboundOwnersUnder(resolved.path);
                }
            }
            if (visible_target_path) {
                result.path = visible_target_path;
            } else if (visible_path) {
                result.path = visible_path;
            }
            return result;
        }

        hash<auto> mkdir(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_path = resolved.path;
            if (*string req_path = resolved.path) {
                resolved.path = translateInboundPathForSession(req_path, session_info, True, "mkdir");
            }
            hash<auto> result = vfs.mkdir(resolved);
            if (visible_path) {
                result.path = visible_path;
            }
            return result;
        }

        hash<auto> rmdir(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_path = resolved.path;
            if (*string req_path = resolved.path) {
                resolved.path = translateInboundPathForSession(req_path, session_info, False, "rmdir");
            }
            hash<auto> result = vfs.rmdir(resolved);
            if (result.completed && resolved.path && isInboundPath(resolved.path)) {
                removeInboundOwnersUnder(resolved.path);
            }
            if (visible_path) {
                result.path = visible_path;
            }
            return result;
        }

        hash<auto> symlink(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_link = resolved.link_path;
            *string visible_target = resolved.target_path;
            if (*string link = resolved.link_path) {
                resolved.link_path = translateInboundPathForSession(link, session_info, True, "symlink link");
            }
            if (*string target = resolved.target_path) {
                resolved.target_path = translateInboundPathForSession(target, session_info, False, "symlink target");
            }
            hash<auto> result = vfs.symlink(resolved);
            if (visible_link) {
                result.path = visible_link;
            }
            return result;
        }

        hash<auto> readlink(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_path = resolved.path;
            if (*string req_path = resolved.path) {
                resolved.path = translateInboundPathForSession(req_path, session_info, False, "readlink");
            }
            hash<auto> result = vfs.readlink(resolved);
            if (visible_path) {
                result.path = visible_path;
            }
            return result;
        }

        hash<auto> setstat(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_path = resolved.path;
            if (*string req_path = resolved.path) {
                resolved.path = translateInboundPathForSession(req_path, session_info, False, "setstat");
            }
            hash<auto> result = vfs.setstat(resolved);
            if (visible_path) {
                result.path = visible_path;
            }
            return result;
        }

        hash<auto> statvfs(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            *string visible_path = resolved.path;
            if (*string req_path = resolved.path) {
                resolved.path = translateInboundPathForSession(req_path, session_info, False, "statvfs");
            }
            return vfs.statvfs(resolved);
        }

        hash<auto> submit(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            resolved.path = resolveRequestPath(req.path, inbound_dir, "submit");
            resolved.path = translateInboundPathForSession(resolved.path, session_info, True, "submit");
            hash<auto> policy_context = getInboundPolicyContext(resolved.path, session_info, "submit");
            if (!resolved.data && resolved.source_path && requiresLoadedSubmissionData(policy_context.policy)) {
                resolved.data = ReadOnlyFile::readBinaryFile(resolved.source_path);
            }
            validateInboundAcceptance(resolved.path, getSubmissionSize(resolved), "submit", EventSourceHelper,
                resolved.metadata, session_info, resolved.data, policy_context, resolved.source_path);
            hash<auto> result = vfs.submit(resolved);
            setInboundFileOwner(resolved.path, getSessionPrincipal(session_info));
            applyRetentionMetadata(resolved.path, RetentionQueueInbound, NOTHING, getSessionPrincipal(session_info));
            *hash<auto> checksum_info = getAcceptedChecksumInfo(resolved.data);
            applyChecksumInfoToTransferInfo(result.transfer_info, checksum_info);
            persistAcceptedChecksum(resolved.path, checksum_info);
            if (checksum_info) {
                result.checksum = checksum_info.checksum;
                result.checksum_algorithm = checksum_info.checksum_algorithm;
            }
            emitInboundAcceptedEvent(getBaseName(resolved.path), resolved.path, getSubmissionSize(resolved),
                resolved.data, resolved.metadata, checksum_info,
                result.transfer_info, EventSourceHelper, session_info);
            return result;
        }

        hash<auto> listAvailable(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            resolved.path = resolveExchangePathOrDefault(req.path, outbound_dir, "listAvailable");
            hash<auto> result = vfs.listAvailable(resolved);
            return {
                "path": result.path,
                "entries": result.entries ?? (),
            };
        }

        hash<auto> retrieve(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            resolved.path = resolveRequestPath(req.path, outbound_dir, "retrieve");
            return vfs.retrieve(resolved);
        }

        hash<auto> completeRetrieve(hash<auto> req) {
            hash<auto> resolved = copyHash(req);
            *hash<Qore::Ssh::SftpSessionInfo> session_info = getRequestSessionInfo(resolved);
            resolved.path = resolveRequestPath(req.path, outbound_dir, "completeRetrieve");
            hash<auto> path_info = vfs.stat({"path": resolved.path});
            string mode = resolved.completion_mode ?? "";
            if (!resolved.target_path) {
                if (mode == "archive") {
                    resolved.target_path = defaultArchiveTarget(resolved.path);
                } else if (mode == "claim") {
                    resolved.target_path = defaultClaimTarget(resolved.path);
                }
            } else {
                if (mode == "archive") {
                    resolved.target_path = resolveArchiveTarget(resolved.target_path);
                } else if (mode == "claim") {
                    resolved.target_path = resolveClaimTarget(resolved.target_path);
                }
            }
            hash<auto> result = vfs.completeRetrieve(resolved);
            *hash<auto> checksum_info = getChecksumInfoFromMetadata(path_info.metadata);
            if (result.completed && mode == "archive" && (result.path ?? resolved.path) != NOTHING) {
                applyRetentionMetadata(result.path ?? resolved.path, RetentionQueueArchive, NOTHING,
                    getSessionPrincipal(session_info));
            } else if (result.completed && mode == "claim" && (result.path ?? resolved.path) != NOTHING) {
                applyRetentionMetadata(result.path ?? resolved.path, RetentionQueueClaim, NOTHING,
                    getSessionPrincipal(session_info));
            }
            if (result.completed && mode.size()) {
                emitOutboundCompletionEvent(mode, getBaseName(resolved.path), result.path ?? resolved.path,
                    getBaseName(result.path ?? resolved.path), path_info.size ?? 0,
                    mergeMetadata(path_info.metadata, resolved.metadata),
                    checksum_info ? checksum_info.checksum : NOTHING,
                    checksum_info ? checksum_info.checksum_algorithm : NOTHING,
                    result.transfer_info,
                    session_info ? EventSourceSftp : EventSourceHelper, session_info);
            }
            return result;
        }

        hash<VirtualSftpOperationResult> submit(hash<VirtualSftpSubmissionRequest> req) {
            hash<auto> result = submit(copyTypedRequest(req));
            return <VirtualSftpOperationResult>{
                "path": result.path,
                "available": result.exists,
                "completed": result.completed,
                "checksum": result.checksum,
                "checksum_algorithm": result.checksum_algorithm,
                "transfer_info": result.transfer_info,
            };
        }

        hash<VirtualSftpListResult> listAvailable(hash<VirtualSftpPathRequest> req) {
            hash<auto> result = listAvailable(copyTypedRequest(req));
            list<hash<VirtualSftpEntryInfo>> entries = ();
            foreach hash<auto> entry in (result.entries ?? ()) {
                entries += (<VirtualSftpEntryInfo>{
                    "filename": entry.filename,
                    "long_name": entry.long_name,
                    "directory": entry.directory,
                    "size": entry.size,
                    "checksum": entry.metadata ? entry.metadata.checksum : NOTHING,
                    "checksum_algorithm": entry.metadata ? entry.metadata.checksum_algorithm : NOTHING,
                    "permissions": entry.permissions,
                    "mtime": entry.mtime,
                    "atime": entry.atime,
                    "state": entry.state,
                    "metadata": entry.metadata ?? {},
                },);
            }
            return <VirtualSftpListResult>{
                "path": result.path,
                "available": result.exists ?? True,
                "entries": entries,
            };
        }

        hash<VirtualSftpRetrieveResult> retrieve(hash<VirtualSftpPathRequest> req) {
            hash<auto> result = retrieve(copyTypedRequest(req));
            *hash<auto> checksum_info = getChecksumInfoForPath(resolveRequestPath(req.path, outbound_dir, "retrieve"));
            return <VirtualSftpRetrieveResult>{
                "path": result.path,
                "available": result.exists,
                "completed": result.completed ?? False,
                "checksum": checksum_info ? checksum_info.checksum : NOTHING,
                "checksum_algorithm": checksum_info ? checksum_info.checksum_algorithm : NOTHING,
                "data": result.data,
                "size": result.size,
                "permissions": result.permissions,
                "transfer_info": result.transfer_info,
            };
        }

        hash<VirtualSftpOperationResult> completeRetrieve(hash<VirtualSftpCompletionRequest> req) {
            *hash<auto> checksum_info = getChecksumInfoForPath(resolveRequestPath(req.path, outbound_dir,
                "completeRetrieve"));
            hash<auto> result = completeRetrieve(copyTypedRequest(req));
            return <VirtualSftpOperationResult>{
                "path": result.path,
                "available": result.exists,
                "completed": result.completed,
                "checksum": checksum_info ? checksum_info.checksum : NOTHING,
                "checksum_algorithm": checksum_info ? checksum_info.checksum_algorithm : NOTHING,
                "transfer_info": result.transfer_info,
            };
        }

        hash<VirtualSftpRetentionCleanupResult> cleanupExpired(string queue, *int now_s,
                bool remove_empty_directories = False, *string principal = NOTHING) {
            int evaluated_at = now_s ?? clock_getseconds();
            list<string> removed_paths = ();
            string search_root = getRetentionSearchRoot(queue);

            foreach string path in (vfs.listFilePaths(search_root)) {
                hash<auto> path_info = vfs.stat({"path": path});
                *hash<auto> metadata = path_info.metadata;
                if (!metadata || metadata.retention_queue != queue) {
                    continue;
                }
                if (principal && !matchesRetentionPrincipal(queue, path, metadata, principal)) {
                    continue;
                }
                if (metadata.expires_at == NOTHING || metadata.expires_at > evaluated_at) {
                    continue;
                }
                hash<auto> result = vfs.removePath({"path": path});
                if (result.completed) {
                    removed_paths += (path,);
                    if (queue == RetentionQueueInbound) {
                        removeInboundFileOwner(path);
                    }
                }
            }

            list<string> removed_directories = remove_empty_directories
                ? cleanupEmptyRetentionDirectories(search_root) : ();
            return <VirtualSftpRetentionCleanupResult>{
                "queue": queue,
                "evaluated_at": evaluated_at,
                "principal": principal,
                "removed_count": removed_paths.size(),
                "removed_paths": removed_paths,
                "removed_directories": removed_directories,
            };
        }

        hash<VirtualSftpRetentionCleanupResult> cleanupExpired(hash<VirtualSftpRetentionCleanupRequest> req) {
            return cleanupExpired(req.queue, req.now_s, req.remove_empty_directories ?? False, req.principal);
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
                "backend_handle": result.backend_handle,
                "permissions": result.permissions,
                "metadata": result.metadata,
                "transfer_info": result.transfer_info,
            };
        }

        hash<Qore::Ssh::SftpOperationResult> closeWrite(hash<Qore::Ssh::SftpSubmissionRequest> req) {
            return cast<hash<Qore::Ssh::SftpOperationResult>>(closeWrite(copyTypedRequest(req)));
        }

        hash<Qore::Ssh::SftpOperationResult> closeWrite(hash<Qore::Ssh::SftpCloseRequest> req) {
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

        hash<Qore::Ssh::SftpOperationResult> symlink(hash<Qore::Ssh::SftpSymlinkRequest> req) {
            return cast<hash<Qore::Ssh::SftpOperationResult>>(symlink(copyTypedRequest(req)));
        }

        hash<auto> readlink(hash<Qore::Ssh::SftpPathRequest> req) {
            return readlink(copyTypedRequest(req));
        }

        hash<Qore::Ssh::SftpOperationResult> setstat(hash<Qore::Ssh::SftpSetstatRequest> req) {
            return cast<hash<Qore::Ssh::SftpOperationResult>>(setstat(copyTypedRequest(req)));
        }

        hash<auto> statvfs(hash<Qore::Ssh::SftpPathRequest> req) {
            return statvfs(copyTypedRequest(req));
        }

        private string normalizeDirectory(string path, string operation) {
            string normalized = normalizeAbsolutePath(path, operation);
            return normalized == "/" ? normalized : normalized;
        }

        private string normalizeAbsolutePath(string path, string operation) {
            if (!path.size() || path[0] != '/') {
                throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                    sprintf("%s requires an absolute path; got %y", operation, path);
            }

            list<string> normalized_parts = ();
            foreach string part in (path.split("/")) {
                if (!part.size() || part == ".") {
                    continue;
                }
                if (part == "..") {
                    throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                        sprintf("%s path %y escapes the virtual root", operation, path);
                }
                normalized_parts += (part,);
            }
            return normalized_parts.empty() ? "/" : "/" + normalized_parts.join("/");
        }

        private string resolveEntryPath(string name, string base_dir, string operation) {
            if (!name.size()) {
                throw "VIRTUAL-SFTP-EXCHANGE-ERROR", sprintf("%s requires a non-empty entry name", operation);
            }
            if (name[0] == '/') {
                return normalizeAbsolutePath(name, operation);
            }
            if (name.find("/") >= 0 || name == "." || name == "..") {
                throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                    sprintf("%s expects a simple entry name; got %y", operation, name);
            }
            return base_dir == "/" ? "/" + name : base_dir + "/" + name;
        }

        private string resolveRequestPath(*string path, string base_dir, string operation) {
            if (!path || !path.size()) {
                throw "VIRTUAL-SFTP-EXCHANGE-ERROR", sprintf("%s requires a non-empty path", operation);
            }
            return resolveExchangePathOrDefault(path, base_dir, operation);
        }

        private string resolveExchangePathOrDefault(*string path, string base_dir, string operation) {
            if (!path || !path.size() || path == ".") {
                return base_dir;
            }
            if (path[0] == '/') {
                if (path == "/") {
                    return base_dir;
                }
                if (path == inbound_dir || path == outbound_dir || path == archive_dir || path == claim_dir) {
                    return normalizeAbsolutePath(path, operation);
                }
                if ((path.size() > inbound_dir.size() && path.substr(0, inbound_dir.size()) == inbound_dir
                        && path[inbound_dir.size()] == '/')
                        || (path.size() > outbound_dir.size() && path.substr(0, outbound_dir.size()) == outbound_dir
                            && path[outbound_dir.size()] == '/')
                        || (archive_dir && path.size() > archive_dir.size() && path.substr(0, archive_dir.size()) == archive_dir
                            && path[archive_dir.size()] == '/')
                        || (claim_dir && path.size() > claim_dir.size() && path.substr(0, claim_dir.size()) == claim_dir
                            && path[claim_dir.size()] == '/')) {
                    return normalizeAbsolutePath(path, operation);
                }
                if (path.substr(1).find("/") < 0) {
                    return resolveEntryPath(path.substr(1), base_dir, operation);
                }
                return normalizeAbsolutePath(path, operation);
            }
            if (path.find("/") >= 0) {
                return normalizeAbsolutePath((base_dir == "/" ? "" : base_dir) + "/" + path, operation);
            }
            return resolveEntryPath(path, base_dir, operation);
        }

        private *string defaultArchiveTarget(string path) {
            return archive_dir ? archive_dir + "/" + getBaseName(path) : NOTHING;
        }

        private *string defaultClaimTarget(string path) {
            return claim_dir ? claim_dir + "/" + getBaseName(path) : NOTHING;
        }

        private string resolveArchiveTarget(string name_or_path) {
            if (!archive_dir) {
                throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                    "archive target requested but no archive_dir is configured";
            }
            return resolveEntryPath(name_or_path, archive_dir, "archive target");
        }

        private string resolveClaimTarget(string name_or_path) {
            if (!claim_dir) {
                throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                    "claim target requested but no claim_dir is configured";
            }
            return resolveEntryPath(name_or_path, claim_dir, "claim target");
        }

        private string getBaseName(string path) {
            int pos = path.rfind("/");
            return pos < 0 ? path : path.substr(pos + 1);
        }

        private int getSubmissionSize(hash<auto> req) {
            if (*binary data = req.data) {
                return data.size();
            }
            if (*string source_path = req.source_path) {
                return Qore::hstat(source_path).size;
            }
            return 0;
        }

        private binary getDataDigest(binary data) {
            return digest("sha256", data);
        }

        private string normalizeInboundEventPayloadMode(string mode) {
            switch (mode) {
                case InboundEventPayloadNone:
                case InboundEventPayloadInline:
                    return mode;
                default:
                    throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                        sprintf("unsupported inbound event payload mode %y; expected %y or %y",
                            mode, InboundEventPayloadNone, InboundEventPayloadInline);
            }
        }

        private *hash<VirtualSftpRetentionPolicy> getRetentionPolicy(string queue) {
            switch (queue) {
                case RetentionQueueInbound:
                    return inbound_retention_policy;
                case RetentionQueueArchive:
                    return archive_retention_policy;
                case RetentionQueueClaim:
                    return claim_retention_policy;
                default:
                    throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                        sprintf("unsupported retention queue %y", queue);
            }
        }

        private string getRetentionSearchRoot(string queue) {
            switch (queue) {
                case RetentionQueueInbound:
                    return inbound_dir;
                case RetentionQueueArchive:
                    return archive_dir ?? outbound_dir;
                case RetentionQueueClaim:
                    return claim_dir ?? outbound_dir;
                default:
                    throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                        sprintf("unsupported retention queue %y", queue);
            }
        }

        private nothing applyRetentionMetadata(string path, string queue, *int retained_at = NOTHING,
                *string principal = NOTHING) {
            *hash<VirtualSftpRetentionPolicy> policy = getRetentionPolicy(queue);
            if (!policy) {
                return;
            }
            int retained = retained_at ?? clock_getseconds();
            hash<auto> metadata = {
                "retention_queue": queue,
                "retained_at": retained,
            };
            if (principal) {
                metadata.retention_principal = principal;
            }
            if (*int max_age_seconds = policy.max_age_seconds) {
                metadata.expires_at = retained + max_age_seconds;
            }
            vfs.mergeFileMetadata(path, metadata);
        }

        private bool matchesRetentionPrincipal(string queue, string path, hash<auto> metadata, string principal) {
            if (metadata.retention_principal == principal) {
                return True;
            }
            if (queue == RetentionQueueInbound) {
                return getInboundFileOwner(path) == principal;
            }
            return False;
        }

        private list<string> cleanupEmptyRetentionDirectories(string search_root) {
            list<string> removed_directories = ();
            if (search_root == "/") {
                return removed_directories;
            }
            while (True) {
                bool removed_any = False;
                foreach string dir_path in (vfs.listDirectoryPaths(search_root, False)) {
                    try {
                        hash<auto> result = vfs.rmdir({"path": dir_path});
                        if (result.completed) {
                            removed_directories += (dir_path,);
                            removed_any = True;
                        }
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err != "VIRTUAL-SFTP-FS-ERROR") {
                            throw ex;
                        }
                    }
                }
                if (!removed_any) {
                    break;
                }
            }
            return removed_directories;
        }

        private *hash<auto> getAcceptedChecksumInfo(*binary data) {
            if (!generate_inbound_checksum || !data) {
                return NOTHING;
            }
            return {
                "checksum": getDataDigest(data).toHex(),
                "checksum_algorithm": ChecksumAlgorithmSha256,
            };
        }

        private nothing applyChecksumInfoToTransferInfo(*hash<Qore::Ssh::SftpTransferInfo> transfer_info,
                *hash<auto> checksum_info) {
            if (!transfer_info || !checksum_info) {
                return;
            }
            transfer_info.checksum = checksum_info.checksum;
        }

        private nothing persistAcceptedChecksum(string path, *hash<auto> checksum_info) {
            if (!checksum_info) {
                return;
            }
            vfs.mergeFileMetadata(path, checksum_info);
        }

        private *hash<auto> getChecksumInfoForPath(string path) {
            hash<auto> stat = vfs.stat({"path": path});
            if (!(stat.exists ?? False)) {
                return NOTHING;
            }
            return getChecksumInfoFromMetadata(stat.metadata);
        }

        private *hash<auto> getChecksumInfoFromMetadata(*hash<auto> metadata) {
            if (!metadata || metadata.checksum == NOTHING) {
                return NOTHING;
            }
            return {
                "checksum": metadata.checksum,
                "checksum_algorithm": metadata.checksum_algorithm ?? ChecksumAlgorithmSha256,
            };
        }

        private bool requiresLoadedSubmissionData(hash<auto> policy) {
            if (inbound_event_payload_mode != InboundEventPayloadNone || generate_inbound_checksum) {
                return True;
            }
            if ((policy.hasKey("reject_duplicate_hash") && policy.reject_duplicate_hash)
                    || (policy.hasKey("accept_content_prefix") && policy.accept_content_prefix != NOTHING)
                    || (policy.hasKey("reject_content_prefix") && policy.reject_content_prefix != NOTHING)
                    || (policy.hasKey("validation_callback") && policy.validation_callback != NOTHING)) {
                return True;
            }
            return False;
        }

        private hash<auto> copyInboundPolicyRule(*hash<auto> source) {
            hash<auto> rv = {};
            if (!source) {
                return rv;
            }
            foreach string key in (keys(source)) {
                if (inlist(key, ("accept_filename_glob", "reject_filename_glob", "accept_filename_regex",
                        "reject_filename_regex", "min_size", "max_size", "max_file_count", "max_total_bytes",
                        "max_concurrent_uploads",
                        "allow_overwrite", "reject_duplicate_name", "reject_duplicate_size",
                        "reject_duplicate_hash", "accept_content_prefix", "reject_content_prefix",
                        "accept_content_type_hints", "reject_content_type_hints", "validation_callback",
                        "allow_hidden_files")) && source.hasKey(key)) {
                    rv{key} = source{key};
                }
            }
            return rv;
        }

        private bool pathUnderDirectory(string relative_path, string subdir) {
            if (!subdir.size()) {
                return True;
            }
            return relative_path == subdir
                || (relative_path.size() > subdir.size()
                    && relative_path.substr(0, subdir.size()) == subdir
                    && relative_path[subdir.size()] == '/');
        }

        private hash<auto> getInboundPolicyContext(string path, *hash<Qore::Ssh::SftpSessionInfo> session_info,
                string operation) {
            string scope_root = getEffectiveInboundRoot(session_info, False, operation);
            hash<auto> policy = copyInboundPolicyRule(inbound_policy);
            *string principal = getSessionPrincipal(session_info);
            bool principal_policy_applied = False;
            if (*hash<auto> principal_policy = getPrincipalPolicyRule(principal)) {
                foreach string key in (keys(principal_policy)) {
                    policy{key} = principal_policy{key};
                }
                principal_policy_applied = True;
            }
            if (!inbound_policy || !inbound_policy.directory_policies) {
                return {
                    "policy": policy,
                    "scope_root": scope_root,
                    "scope_principal": principal_policy_applied && !hasPrincipalInboundRoute(principal)
                        ? principal : NOTHING,
                };
            }

            string relative_path = path == scope_root ? ""
                : (path.size() > scope_root.size() + 1 ? path.substr(scope_root.size() + 1) : "");
            foreach hash<VirtualSftpInboundDirectoryPolicy> directory_policy in (inbound_policy.directory_policies) {
                string subdir = normalizeRelativeDirectory(directory_policy.subdir, operation + " directory policy");
                if (!pathUnderDirectory(relative_path, subdir)) {
                    continue;
                }
                foreach string key in (keys(directory_policy.policy)) {
                    if (directory_policy.policy.hasKey(key)) {
                        policy{key} = directory_policy.policy{key};
                    }
                }
                scope_root = subdir.size() ? scope_root + "/" + subdir : scope_root;
            }

            return {
                "policy": policy,
                "scope_root": scope_root,
                "scope_principal": principal_policy_applied && !hasPrincipalInboundRoute(principal)
                    ? principal : NOTHING,
            };
        }

        private string normalizeRelativeDirectory(string subdir, string operation) {
            string normalized = normalizeAbsolutePath("/" + subdir, operation);
            return normalized == "/" ? "" : normalized.substr(1);
        }

        private hash<auto> mergeMetadata(*hash<auto> left, *hash<auto> right) {
            hash<auto> rv = copyHash(left);
            if (!right) {
                return rv;
            }
            foreach string key in (keys(right)) {
                rv{key} = right{key};
            }
            return rv;
        }

        private hash<auto> copyHash(*hash<auto> source) {
            hash<auto> rv = {};
            if (!source) {
                return rv;
            }
            foreach string key in (keys(source)) {
                rv{key} = source{key};
            }
            return rv;
        }

        private hash<auto> copyTypedRequest(hash<auto> req) {
            hash<auto> rv = {};
            foreach string key in (keys(req)) {
                rv{key} = req{key};
            }
            return rv;
        }

        private hash<VirtualSftpRecordInfo> makeCompletionRecord(string queue, string name, *string path,
                string operation, string final_name, *hash<auto> metadata, *string checksum, *string checksum_algorithm) {
            return <VirtualSftpRecordInfo>{
                "queue": queue,
                "name": name,
                "path": path,
                "size": 0,
                "checksum": checksum,
                "checksum_algorithm": checksum_algorithm,
                "metadata": metadata ?? {},
                "final_name": final_name,
                "operation": operation,
                "completed": True,
            };
        }

        private bool isInboundPath(string path) {
            return path == inbound_dir
                || (path.size() > inbound_dir.size() && path.substr(0, inbound_dir.size()) == inbound_dir
                    && path[inbound_dir.size()] == '/');
        }

        private *hash<Qore::Ssh::SftpSessionInfo> getRequestSessionInfo(hash<auto> req) {
            return req.session_info;
        }

        private *string getSessionPrincipal(*hash<Qore::Ssh::SftpSessionInfo> session_info) {
            return session_info ? session_info.principal : NOTHING;
        }

        private *hash<auto> getPrincipalPolicyRule(*string principal) {
            if (!principal || !inbound_policy || !inbound_policy.principal_policies) {
                return NOTHING;
            }
            foreach hash<VirtualSftpPrincipalPolicy> principal_policy in (inbound_policy.principal_policies) {
                if (principal_policy.principal == principal) {
                    return copyInboundPolicyRule(principal_policy.policy);
                }
            }
            return NOTHING;
        }

        private bool hasPrincipalInboundRoute(*string principal) {
            if (!principal || !inbound_policy || !inbound_policy.principal_routes) {
                return False;
            }
            foreach hash<VirtualSftpPrincipalRoute> route in (inbound_policy.principal_routes) {
                if (route.principal == principal) {
                    return True;
                }
            }
            return False;
        }

        private string getEffectiveInboundRoot(*hash<Qore::Ssh::SftpSessionInfo> session_info, bool create_root,
                string operation) {
            *string principal = getSessionPrincipal(session_info);
            if (!principal || !inbound_policy || !inbound_policy.principal_routes) {
                return inbound_dir;
            }

            foreach hash<VirtualSftpPrincipalRoute> route in (inbound_policy.principal_routes) {
                if (route.principal == principal) {
                    string root = resolveEntryPath(route.inbound_subdir, inbound_dir, operation + " principal route");
                    if (create_root && !vfs.exists(root)) {
                        vfs.addDirectory(root, {
                            "exchange_role": "inbound",
                            "principal": principal,
                        });
                    }
                    return root;
                }
            }

            return inbound_dir;
        }

        private string translateInboundPathForSession(string path, *hash<Qore::Ssh::SftpSessionInfo> session_info,
                bool create_root, string operation) {
            string normalized = normalizeAbsolutePath(path, operation);
            if (!isInboundPath(normalized)) {
                return normalized;
            }

            string effective_root = getEffectiveInboundRoot(session_info, create_root, operation);
            if (effective_root == inbound_dir) {
                return normalized;
            }
            if (normalized == inbound_dir) {
                return effective_root;
            }
            return effective_root + normalized.substr(inbound_dir.size());
        }

        private *string findInboundDuplicatePath(string path, string scope_root) {
            return findInboundDuplicatePath(path, scope_root, NOTHING);
        }

        private *string findInboundDuplicatePath(string path, string scope_root, *string principal) {
            string name = getBaseName(path);
            foreach string file_path in (vfs.listFilePaths(scope_root)) {
                if (!matchesPrincipalScope(file_path, principal)) {
                    continue;
                }
                if (getBaseName(file_path) == name) {
                    return file_path;
                }
            }
            return NOTHING;
        }

        private *string findInboundDuplicateSizePath(int size, string scope_root) {
            return findInboundDuplicateSizePath(size, scope_root, NOTHING);
        }

        private *string findInboundDuplicateSizePath(int size, string scope_root, *string principal) {
            foreach string file_path in (vfs.listFilePaths(scope_root)) {
                if (!matchesPrincipalScope(file_path, principal)) {
                    continue;
                }
                if ((vfs.stat({"path": file_path}).size ?? -1) == size) {
                    return file_path;
                }
            }
            return NOTHING;
        }

        private *string findInboundDuplicateHashPath(binary data, int size, string scope_root) {
            return findInboundDuplicateHashPath(data, size, scope_root, NOTHING);
        }

        private *string findInboundDuplicateHashPath(binary data, int size, string scope_root, *string principal) {
            binary digest_value = getDataDigest(data);
            foreach string file_path in (vfs.listFilePaths(scope_root)) {
                if (!matchesPrincipalScope(file_path, principal)) {
                    continue;
                }
                hash<auto> stat = vfs.stat({"path": file_path});
                if ((stat.size ?? -1) != size) {
                    continue;
                }
                if (getDataDigest(vfs.getFileData(file_path)) == digest_value) {
                    return file_path;
                }
            }
            return NOTHING;
        }

        private bool binaryStartsWith(binary data, binary prefix) {
            if (prefix.size() > data.size()) {
                return False;
            }
            return data.substr(0, prefix.size()) == prefix;
        }

        private *string getContentTypeHint(*hash<auto> metadata) {
            if (!metadata) {
                return NOTHING;
            }
            if (metadata.content_type_hint != NOTHING) {
                return metadata.content_type_hint;
            }
            if (metadata.content_type != NOTHING) {
                return metadata.content_type;
            }
            return NOTHING;
        }

        private hash<auto> getInboundUsage(string scope_root) {
            return getInboundUsage(scope_root, NOTHING);
        }

        private hash<auto> getInboundUsage(string scope_root, *string principal) {
            int file_count = 0;
            int total_bytes = 0;
            foreach string file_path in (vfs.listFilePaths(scope_root)) {
                if (!matchesPrincipalScope(file_path, principal)) {
                    continue;
                }
                ++file_count;
                total_bytes += (vfs.stat({"path": file_path}).size ?? 0);
            }
            return {
                "file_count": file_count,
                "total_bytes": total_bytes,
            };
        }

        private int getActiveInboundUploadCount(string scope_root, *string principal) {
            upload_lock.lock();
            on_exit upload_lock.unlock();
            int count = 0;
            foreach string upload_id in (keys(active_inbound_uploads)) {
                *hash<auto> upload = active_inbound_uploads{upload_id};
                if (!upload) {
                    continue;
                }
                if (!pathUnderScope(upload.path, scope_root)) {
                    continue;
                }
                if (principal && upload.principal != principal) {
                    continue;
                }
                ++count;
            }
            return count;
        }

        private bool matchesPrincipalScope(string file_path, *string principal) {
            if (!principal) {
                return True;
            }
            return getInboundFileOwner(file_path) == principal;
        }

        private bool pathUnderScope(string path, string scope_root) {
            return path == scope_root
                || (path.size() > scope_root.size()
                    && path.substr(0, scope_root.size()) == scope_root
                    && path[scope_root.size()] == '/');
        }

        private *string reserveInboundUpload(string path, *hash<Qore::Ssh::SftpSessionInfo> session_info,
                hash<auto> policy_context, string operation, string source, *hash<auto> metadata) {
            hash<auto> policy = policy_context.policy;
            if (!(policy.hasKey("max_concurrent_uploads") && policy.max_concurrent_uploads != NOTHING)) {
                return NOTHING;
            }
            int max_concurrent_uploads = policy.max_concurrent_uploads;
            *string scope_principal = policy_context.scope_principal;
            string scope_root = policy_context.scope_root;
            upload_lock.lock();
            on_exit upload_lock.unlock();
            int active_count = 0;
            foreach string current_upload_id in (keys(active_inbound_uploads)) {
                *hash<auto> upload = active_inbound_uploads{current_upload_id};
                if (!upload) {
                    continue;
                }
                if (!pathUnderScope(upload.path, scope_root)) {
                    continue;
                }
                if (scope_principal && upload.principal != scope_principal) {
                    continue;
                }
                ++active_count;
            }
            if (active_count >= max_concurrent_uploads) {
                throwInboundRejectedEvent(getBaseName(path), path, NOTHING, metadata, source, session_info,
                    InboundRejectMaxConcurrentUploads,
                    sprintf("%s denied inbound file %y: active upload count %d exceeds maximum %d",
                        operation, getBaseName(path), active_count + 1, max_concurrent_uploads));
            }
            string upload_id = sprintf("upload-%d", next_inbound_upload_id++);
            active_inbound_uploads{upload_id} = {
                "path": path,
                "principal": getSessionPrincipal(session_info),
            };
            return upload_id;
        }

        private nothing releaseInboundUpload(*string upload_id, *string path) {
            upload_lock.lock();
            on_exit upload_lock.unlock();
            if (upload_id && exists active_inbound_uploads{upload_id}) {
                delete active_inbound_uploads{upload_id};
                return;
            }
            if (!path) {
                return;
            }
            foreach string current_upload_id in (keys(active_inbound_uploads)) {
                *hash<auto> upload = active_inbound_uploads{current_upload_id};
                if (upload && upload.path == path) {
                    delete active_inbound_uploads{current_upload_id};
                    return;
                }
            }
        }

        private nothing setInboundFileOwner(string path, *string principal) {
            ownership_lock.lock();
            on_exit ownership_lock.unlock();
            if (principal) {
                inbound_file_owners{path} = principal;
            } else {
                delete inbound_file_owners{path};
            }
        }

        private *string getInboundFileOwner(string path) {
            ownership_lock.lock();
            on_exit ownership_lock.unlock();
            return inbound_file_owners{path};
        }

        private nothing removeInboundFileOwner(string path) {
            ownership_lock.lock();
            on_exit ownership_lock.unlock();
            delete inbound_file_owners{path};
        }

        private nothing removeInboundOwnersUnder(string root) {
            ownership_lock.lock();
            on_exit ownership_lock.unlock();
            string prefix = root + "/";
            foreach string path in (keys(inbound_file_owners)) {
                if (path == root || (path.size() > prefix.size() && path.substr(0, prefix.size()) == prefix)) {
                    delete inbound_file_owners{path};
                }
            }
        }

        private nothing moveInboundOwnersUnder(string root, string target_root) {
            ownership_lock.lock();
            on_exit ownership_lock.unlock();
            hash<auto> moved = {};
            string prefix = root + "/";
            string target_prefix = target_root + "/";
            foreach string path in (keys(inbound_file_owners)) {
                if (path == root) {
                    moved{target_root} = inbound_file_owners{path};
                    delete inbound_file_owners{path};
                } else if (path.size() > prefix.size() && path.substr(0, prefix.size()) == prefix) {
                    moved{target_prefix + path.substr(prefix.size())} = inbound_file_owners{path};
                    delete inbound_file_owners{path};
                }
            }
            foreach string path in (keys(moved)) {
                inbound_file_owners{path} = moved{path};
            }
        }

        private nothing validateInboundAcceptance(string path, *int size, string operation, string source,
                *hash<auto> metadata = NOTHING, *hash<Qore::Ssh::SftpSessionInfo> session_info = NOTHING,
                *binary data = NOTHING, *hash<auto> policy_context = NOTHING, *string source_path = NOTHING) {
            if (!inbound_policy) {
                return;
            }

            string name = getBaseName(path);
            hash<auto> effective_policy_context = policy_context ?? getInboundPolicyContext(path, session_info, operation);
            hash<auto> policy = effective_policy_context.policy;
            string scope_root = effective_policy_context.scope_root;
            *string scope_principal = effective_policy_context.scope_principal;
            *string principal = getSessionPrincipal(session_info);
            *string content_type_hint = getContentTypeHint(metadata);
            if (*list<string> allow_principals = inbound_policy.allow_principals) {
                if (!principal || !inlist(principal, allow_principals)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectPrincipalNotAllowed,
                        sprintf("%s denied inbound file %y: principal %y is not allowed",
                            operation, name, principal ?? "<none>"));
                }
            }
            if (*list<string> deny_principals = inbound_policy.deny_principals) {
                if (principal && inlist(principal, deny_principals)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectPrincipalDenied,
                        sprintf("%s denied inbound file %y: principal %y is denied", operation, name, principal));
                }
            }
            if (policy.hasKey("allow_hidden_files") && !policy.allow_hidden_files
                    && name.size() && name.substr(0, 1) == ".") {
                throwInboundRejectedEvent(name, path, size, metadata, source, session_info, InboundRejectHiddenFile,
                    sprintf("%s denied inbound file %y: hidden files are not allowed", operation, name));
            }
            if (*string pattern = policy.accept_filename_glob) {
                if (!matchesGlob(name, pattern)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectFilenameGlob,
                        sprintf("%s denied inbound file %y: filename does not match allowed glob %y",
                            operation, name, pattern));
                }
            }
            if (*string pattern = policy.reject_filename_glob) {
                if (matchesGlob(name, pattern)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectFilenameGlob,
                        sprintf("%s denied inbound file %y: filename matches rejected glob %y",
                            operation, name, pattern));
                }
            }
            if (*string pattern = policy.accept_filename_regex) {
                if (!matchesRegex(name, pattern)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectFilenameRegex,
                        sprintf("%s denied inbound file %y: filename does not match allowed regex %y",
                            operation, name, pattern));
                }
            }
            if (*string pattern = policy.reject_filename_regex) {
                if (matchesRegex(name, pattern)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectFilenameRegex,
                        sprintf("%s denied inbound file %y: filename matches rejected regex %y",
                            operation, name, pattern));
                }
            }
            if (*list<string> accepted_hints = policy.accept_content_type_hints) {
                if (!content_type_hint || !inlist(content_type_hint, accepted_hints)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectContentTypeHint,
                        sprintf("%s denied inbound file %y: content type hint %y is not allowed",
                            operation, name, content_type_hint ?? "<none>"));
                }
            }
            if (*list<string> rejected_hints = policy.reject_content_type_hints) {
                if (content_type_hint && inlist(content_type_hint, rejected_hints)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectContentTypeHint,
                        sprintf("%s denied inbound file %y: content type hint %y is rejected",
                            operation, name, content_type_hint));
                }
            }
            if (size != NOTHING) {
                if (*int min_size = policy.min_size) {
                    if (size < min_size) {
                        throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                            InboundRejectMinSize,
                            sprintf("%s denied inbound file %y: size %d is smaller than minimum %d",
                                operation, name, size, min_size));
                    }
                }
                if (*int max_size = policy.max_size) {
                    if (size > max_size) {
                        throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                            InboundRejectMaxSize,
                            sprintf("%s denied inbound file %y: size %d exceeds maximum %d",
                                operation, name, size, max_size));
                    }
                }
            }
            if (data != NOTHING) {
                if (*binary accepted_prefix = policy.accept_content_prefix) {
                    if (!binaryStartsWith(data, accepted_prefix)) {
                        throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                            InboundRejectContentPrefix,
                            sprintf("%s denied inbound file %y: content does not match the required prefix",
                                operation, name));
                    }
                }
                if (*binary rejected_prefix = policy.reject_content_prefix) {
                    if (binaryStartsWith(data, rejected_prefix)) {
                        throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                            InboundRejectContentPrefix,
                            sprintf("%s denied inbound file %y: content matches a rejected prefix",
                                operation, name));
                    }
                }
            }
            if (policy.hasKey("reject_duplicate_name") && policy.reject_duplicate_name) {
                if (*string duplicate_path = findInboundDuplicatePath(path, scope_root, scope_principal)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectDuplicateName,
                        sprintf("%s denied inbound file %y: duplicate basename already exists at %y",
                            operation, name, duplicate_path));
                }
            }
            if (data != NOTHING && size != NOTHING && policy.hasKey("reject_duplicate_hash")
                    && policy.reject_duplicate_hash) {
                if (*string duplicate_path = findInboundDuplicateHashPath(data, size, scope_root, scope_principal)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectDuplicateHash,
                        sprintf("%s denied inbound file %y: duplicate content already exists at %y",
                            operation, name, duplicate_path));
                }
            }
            if (size != NOTHING && policy.hasKey("reject_duplicate_size") && policy.reject_duplicate_size) {
                if (*string duplicate_path = findInboundDuplicateSizePath(size, scope_root, scope_principal)) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectDuplicateSize,
                        sprintf("%s denied inbound file %y: duplicate size already exists at %y",
                            operation, name, duplicate_path));
                }
            }
            bool path_exists = vfs.exists(path);
            int existing_path_size = path_exists ? (vfs.stat({"path": path}).size ?? 0) : 0;
            if (policy.hasKey("allow_overwrite") && !policy.allow_overwrite && path_exists) {
                throwInboundRejectedEvent(name, path, size, metadata, source, session_info, InboundRejectOverwrite,
                    sprintf("%s denied inbound file %y: overwriting %y is not allowed", operation, name, path));
            }
            if (*int max_file_count = policy.max_file_count) {
                hash<auto> usage = getInboundUsage(scope_root, scope_principal);
                int projected_file_count = usage.file_count + (path_exists ? 0 : 1);
                if (projected_file_count > max_file_count) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectMaxFileCount,
                        sprintf("%s denied inbound file %y: projected file count %d exceeds maximum %d",
                            operation, name, projected_file_count, max_file_count));
                }
            }
            if (size != NOTHING) {
                if (*int max_total_bytes = policy.max_total_bytes) {
                    hash<auto> usage = getInboundUsage(scope_root, scope_principal);
                    int projected_total_bytes = usage.total_bytes - existing_path_size + size;
                    if (projected_total_bytes > max_total_bytes) {
                        throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                            InboundRejectMaxTotalBytes,
                            sprintf("%s denied inbound file %y: projected total bytes %d exceeds maximum %d",
                                operation, name, projected_total_bytes, max_total_bytes));
                    }
                }
            }
            if (*int max_concurrent_uploads = policy.max_concurrent_uploads) {
                int active_upload_count = getActiveInboundUploadCount(scope_root, scope_principal);
                if (active_upload_count > max_concurrent_uploads) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        InboundRejectMaxConcurrentUploads,
                        sprintf("%s denied inbound file %y: active upload count %d exceeds maximum %d",
                                operation, name, active_upload_count, max_concurrent_uploads));
                }
            }
            *code<hash<VirtualSftpInboundValidationResult>(hash<VirtualSftpInboundValidationRequest>)>
                validation_callback = policy.validation_callback;
            if (data != NOTHING && validation_callback) {
                hash<VirtualSftpInboundValidationResult> result
                    = validation_callback(<VirtualSftpInboundValidationRequest>{
                        "name": name,
                        "path": path,
                        "size": size,
                        "metadata": metadata ?? {},
                        "data": data,
                        "source_path": source_path,
                        "source": source,
                        "operation": operation,
                        "session_info": session_info,
                        "principal": principal,
                        "content_type_hint": content_type_hint,
                        "policy": copyHash(policy),
                        "scope_root": scope_root,
                        "scope_principal": scope_principal,
                    });
                if (!result.accepted) {
                    throwInboundRejectedEvent(name, path, size, metadata, source, session_info,
                        result.reason_code ?? InboundRejectCustomValidation,
                        result.reason_desc
                            ?? sprintf("%s denied inbound file %y: rejected by validation callback", operation, name));
                }
            }
        }

        private bool matchesRegex(string value, string pattern) {
            Regex re(pattern);
            return re.match(value);
        }

        private bool matchesGlob(string value, string pattern) {
            Regex re(globToRegex(pattern));
            return re.match(value);
        }

        private string globToRegex(string pattern) {
            string re = "^";
            for (int i = 0; i < pattern.length(); ++i) {
                string ch = pattern[i];
                switch (ch) {
                    case "*":
                        re += ".*";
                        break;
                    case "?":
                        re += ".";
                        break;
                    case ".":
                    case "(":
                    case ")":
                    case "[":
                    case "]":
                    case "{":
                    case "}":
                    case "+":
                    case "^":
                    case "$":
                    case "|":
                    case "\\":
                        re += "\\" + ch;
                        break;
                    default:
                        re += ch;
                        break;
                }
            }
            re += "$";
            return re;
        }

        private string getOutboundEventType(string operation) {
            switch (operation) {
                case "claim":
                    return EventOutboundFileClaimed;
                case "archive":
                    return EventOutboundFileArchived;
                case "delete":
                    return EventOutboundFileDeleted;
                default:
                    throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                        sprintf("unsupported outbound event operation %y", operation);
            }
        }

        private nothing emitInboundAcceptedEvent(string name, string path, int size, *binary data, *hash<auto> metadata,
                *hash<auto> checksum_info, *hash<Qore::Ssh::SftpTransferInfo> transfer_info, string source,
                *hash<Qore::Ssh::SftpSessionInfo> session_info) {
            emitInboundEvent(<VirtualSftpInboundEventInfo>{
                "event_type": EventInboundFileAccepted,
                "name": name,
                "path": path,
                "size": size,
                "metadata": metadata ?? {},
                "data": inbound_event_payload_mode == InboundEventPayloadInline ? (data ?? binary()) : NOTHING,
                "submitted_at": clock_getseconds(),
                "source": source,
                "session_id": session_info && session_info.session_info ? session_info.session_info.session_id : NOTHING,
                "server_name": session_info && session_info.session_info ? session_info.session_info.server_name : NOTHING,
                "listener_name": session_info && session_info.session_info
                    ? session_info.session_info.listener_name : NOTHING,
                "principal": getSessionPrincipal(session_info),
                "accepted": True,
                "checksum": checksum_info ? checksum_info.checksum : NOTHING,
                "checksum_algorithm": checksum_info ? checksum_info.checksum_algorithm : NOTHING,
                "transfer_info": transfer_info,
            });
        }

        private nothing throwInboundRejectedEvent(string name, string path, *int size, *hash<auto> metadata,
                string source, *hash<Qore::Ssh::SftpSessionInfo> session_info, string reason_code, string reason_desc) {
            emitInboundEvent(<VirtualSftpInboundEventInfo>{
                "event_type": EventInboundFileRejected,
                "name": name,
                "path": path,
                "size": size ?? 0,
                "metadata": metadata ?? {},
                "submitted_at": clock_getseconds(),
                "source": source,
                "session_id": session_info && session_info.session_info ? session_info.session_info.session_id : NOTHING,
                "server_name": session_info && session_info.session_info ? session_info.session_info.server_name : NOTHING,
                "listener_name": session_info && session_info.session_info
                    ? session_info.session_info.listener_name : NOTHING,
                "principal": getSessionPrincipal(session_info),
                "accepted": False,
                "reason_code": reason_code,
                "reason_desc": reason_desc,
            });
            throw "VIRTUAL-SFTP-EXCHANGE-ERROR", reason_desc;
        }

        private nothing emitInboundEvent(hash<VirtualSftpInboundEventInfo> event) {
            list<auto> listeners = ();
            {
                event_lock.lock();
                on_exit event_lock.unlock();
                foreach auto key in (keys(inbound_event_listeners)) {
                    listeners += (inbound_event_listeners{key},);
                }
            }

            foreach auto listener in (listeners) {
                try {
                    listener(event);
                } catch (auto e) {
                    if (logger) {
                        logger.error("%s", sprintf("virtual inbound event listener failed for %s: %s: %s",
                            event.path, e.err, e.desc));
                    }
                }
            }
        }

        private nothing emitOutboundCompletionEvent(string operation, string name, string path, string final_name,
                int size, *hash<auto> metadata, *string checksum, *string checksum_algorithm,
                *hash<Qore::Ssh::SftpTransferInfo> transfer_info, string source, *hash<Qore::Ssh::SftpSessionInfo> session_info) {
            emitOutboundEvent(<VirtualSftpOutboundEventInfo>{
                "event_type": getOutboundEventType(operation),
                "name": name,
                "path": path,
                "size": size,
                "metadata": metadata ?? {},
                "completed_at": clock_getseconds(),
                "source": source,
                "session_id": session_info && session_info.session_info ? session_info.session_info.session_id : NOTHING,
                "server_name": session_info && session_info.session_info ? session_info.session_info.server_name : NOTHING,
                "listener_name": session_info && session_info.session_info
                    ? session_info.session_info.listener_name : NOTHING,
                "principal": getSessionPrincipal(session_info),
                "final_name": final_name,
                "operation": operation,
                "checksum": checksum,
                "checksum_algorithm": checksum_algorithm,
                "transfer_info": transfer_info,
            });
        }

        private nothing emitOutboundEvent(hash<VirtualSftpOutboundEventInfo> event) {
            list<auto> listeners = ();
            {
                event_lock.lock();
                on_exit event_lock.unlock();
                foreach auto key in (keys(outbound_event_listeners)) {
                    listeners += (outbound_event_listeners{key},);
                }
            }

            foreach auto listener in (listeners) {
                try {
                    listener(event);
                } catch (auto e) {
                    if (logger) {
                        logger.error("%s", sprintf("virtual outbound event listener failed for %s: %s: %s",
                            event.path, e.err, e.desc));
                    }
                }
            }
        }
    }
}
