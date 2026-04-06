public namespace SftpServerDataProvider {
    /** Record-oriented facade over
        @ref SftpServerDataProvider::VirtualSftpExchange.

        This helper exposes queue-style submit, list, retrieve, claim,
        archive, and delete workflows using typed record requests and results.
    */
    public class VirtualSftpExchangeRecordStore {
        private {
            VirtualSftpExchange exchange;
        }

        constructor(*hash<VirtualSftpExchangeOptions> options) {
            exchange = new VirtualSftpExchange(options);
        }

        constructor(VirtualSftpExchange exchange) {
            self.exchange = exchange;
        }

        VirtualSftpExchange getExchange() {
            return exchange;
        }

        object getBackend() {
            return exchange;
        }

        hash<VirtualSftpRecordInfo> submitInboundRecord(string name, binary data, *hash<auto> metadata) {
            hash<VirtualSftpOperationResult> result = exchange.submit(<VirtualSftpSubmissionRequest>{
                "path": name,
                "data": data,
                "metadata": metadata,
            });
            return makeRecord("inbound", name, result.path ?? (exchange.getInboundDir() + "/" + name), data.size(),
                metadata, NOTHING, result.checksum, result.checksum_algorithm);
        }

        hash<VirtualSftpRecordInfo> submitInboundRecord(hash<VirtualSftpRecordSubmissionRequest> req) {
            return submitInboundRecord(req.name, req.data, req.metadata);
        }

        hash<VirtualSftpRecordInfo> submitInboundTextRecord(string name, string data, *hash<auto> metadata) {
            return submitInboundRecord(name, binary(data), metadata);
        }

        list<hash<VirtualSftpRecordInfo>> listInboundRecords() {
            list<hash<VirtualSftpRecordInfo>> records = ();
            foreach hash<VirtualSftpEntryInfo> entry in (exchange.listInbound()) {
                records += (makeListedRecord("inbound", entry),);
            }
            return records;
        }

        hash<VirtualSftpRecordInfo> retrieveInboundRecord(string name) {
            hash<VirtualSftpRetrieveResult> result = exchange.retrieve(<VirtualSftpPathRequest>{
                "path": exchange.getInboundDir() + "/" + name,
            });
            return makeRecord("inbound", name, exchange.getInboundDir() + "/" + name, result.size ?? 0, NOTHING,
                result.data, result.checksum, result.checksum_algorithm);
        }

        hash<VirtualSftpRecordInfo> retrieveInboundRecord(hash<VirtualSftpRecordRequest> req) {
            return retrieveInboundRecord(req.name);
        }

        nothing addOutboundRecord(string name, binary data, *hash<auto> metadata) {
            exchange.addOutboundData(name, data, metadata);
        }

        nothing addOutboundRecord(hash<VirtualSftpRecordSubmissionRequest> req) {
            addOutboundRecord(req.name, req.data, req.metadata);
        }

        nothing addOutboundTextRecord(string name, string data, *hash<auto> metadata) {
            exchange.addOutboundText(name, data, metadata);
        }

        list<hash<VirtualSftpRecordInfo>> listOutboundRecords() {
            list<hash<VirtualSftpRecordInfo>> records = ();
            foreach hash<VirtualSftpEntryInfo> entry in (exchange.listOutbound()) {
                records += (makeListedRecord("outbound", entry),);
            }
            return records;
        }

        hash<VirtualSftpRecordInfo> retrieveOutboundRecord(string name) {
            hash<VirtualSftpRetrieveResult> result = exchange.retrieve(<VirtualSftpPathRequest>{
                "path": exchange.getOutboundDir() + "/" + name,
            });
            return makeRecord("outbound", name, exchange.getOutboundDir() + "/" + name, result.size ?? 0, NOTHING,
                result.data, result.checksum, result.checksum_algorithm);
        }

        hash<VirtualSftpRecordInfo> retrieveOutboundRecord(hash<VirtualSftpRecordRequest> req) {
            return retrieveOutboundRecord(req.name);
        }

        hash<VirtualSftpRecordInfo> claimOutboundRecord(string name, *string claimed_name, *hash<auto> metadata) {
            hash<auto> result = exchange.claimOutbound(name, claimed_name, metadata);
            string final_name = claimed_name ?? name;
            return makeCompletedRecord("outbound", name, result.path, "claim", final_name, metadata,
                result.checksum, result.checksum_algorithm);
        }

        hash<VirtualSftpRecordInfo> claimOutboundRecord(hash<VirtualSftpRecordCompletionRequest> req) {
            validateRecordCompletionMode(req.completion_mode, "claim", "claimOutboundRecord");
            return claimOutboundRecord(req.name, req.final_name, req.metadata);
        }

        hash<VirtualSftpRecordInfo> archiveOutboundRecord(string name, *string archived_name, *hash<auto> metadata) {
            hash<auto> result = exchange.archiveOutbound(name, archived_name, metadata);
            string final_name = archived_name ?? name;
            return makeCompletedRecord("outbound", name, result.path, "archive", final_name, metadata,
                result.checksum, result.checksum_algorithm);
        }

        hash<VirtualSftpRecordInfo> archiveOutboundRecord(hash<VirtualSftpRecordCompletionRequest> req) {
            validateRecordCompletionMode(req.completion_mode, "archive", "archiveOutboundRecord");
            return archiveOutboundRecord(req.name, req.final_name, req.metadata);
        }

        hash<VirtualSftpRecordInfo> deleteOutboundRecord(string name, *hash<auto> metadata) {
            hash<auto> result = exchange.deleteOutbound(name, metadata);
            return makeCompletedRecord("outbound", name, NOTHING, "delete", name, metadata,
                result.checksum, result.checksum_algorithm);
        }

        hash<VirtualSftpRecordInfo> deleteOutboundRecord(hash<VirtualSftpRecordRequest> req) {
            return deleteOutboundRecord(req.name, req.metadata);
        }

        hash<VirtualSftpRecordInfo> deleteOutboundRecord(hash<VirtualSftpRecordCompletionRequest> req) {
            validateRecordCompletionMode(req.completion_mode, "delete", "deleteOutboundRecord");
            return deleteOutboundRecord(req.name, req.metadata);
        }

        private nothing validateRecordCompletionMode(*string completion_mode, string expected_mode, string method_name) {
            if (!completion_mode || completion_mode == expected_mode) {
                return;
            }
            throw "VIRTUAL-SFTP-EXCHANGE-ERROR",
                sprintf("%s() typed request completion_mode %y does not match required mode %y",
                    method_name, completion_mode, expected_mode);
        }

        private hash<VirtualSftpRecordInfo> makeListedRecord(string queue, hash<VirtualSftpEntryInfo> entry) {
            return <VirtualSftpRecordInfo>{
                "queue": queue,
                "name": entry.filename,
                "path": (queue == "outbound" ? exchange.getOutboundDir() : exchange.getInboundDir()) + "/" + entry.filename,
                "size": entry.size,
                "checksum": entry.checksum ?? (entry.metadata ? entry.metadata.checksum : NOTHING),
                "checksum_algorithm": entry.checksum_algorithm
                    ?? (entry.metadata ? entry.metadata.checksum_algorithm : NOTHING),
                "metadata": entry.metadata ?? {},
            };
        }

        private hash<VirtualSftpRecordInfo> makeRecord(string queue, string name, string path, int size,
                *hash<auto> metadata,
                *binary data, *string checksum, *string checksum_algorithm) {
            hash<VirtualSftpRecordInfo> rv = <VirtualSftpRecordInfo>{
                "queue": queue,
                "name": name,
                "path": path,
                "size": size,
                "checksum": checksum,
                "checksum_algorithm": checksum_algorithm,
                "metadata": metadata ?? {},
            };
            if (data) {
                rv.data = data;
            }
            return rv;
        }

        private hash<VirtualSftpRecordInfo> makeCompletedRecord(string queue, string name, *string final_path,
                string operation, string final_name, *hash<auto> metadata, *string checksum, *string checksum_algorithm) {
            return <VirtualSftpRecordInfo>{
                "queue": queue,
                "name": name,
                "final_name": final_name,
                "path": final_path,
                "operation": operation,
                "completed": True,
                "checksum": checksum,
                "checksum_algorithm": checksum_algorithm,
                "metadata": metadata ?? {},
            };
        }
    }

}
