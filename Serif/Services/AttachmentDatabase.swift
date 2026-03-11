import Foundation
import SQLite3

/// SQLITE_TRANSIENT tells SQLite to copy bound data immediately.
/// Using `OpaquePointer(bitPattern:)` avoids the undefined behavior of
/// `unsafeBitCast(-1, to: sqlite3_destructor_type.self)` which casts an
/// Int to a function pointer.
private let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

// MARK: - Error

enum AttachmentDatabaseError: Error {
    case openFailed(String)
    case schemaFailed(String)
    case queryFailed(String)
}

// MARK: - AttachmentDatabase

final class AttachmentDatabase: @unchecked Sendable {

    static let shared = AttachmentDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.serif.attachment-db", qos: .utility)

    // MARK: - Lifecycle

    private init() {
        do {
            try openDatabase()
            try createSchema()
        } catch {
            print("[AttachmentDB] Init failed: \(error)")
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Open

    private func openDatabase() throws {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("com.genyus.serif.app", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let path = dir.appendingPathComponent("attachment-index.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw AttachmentDatabaseError.openFailed(msg)
        }

        // WAL mode for better concurrency
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA foreign_keys=ON")
    }

    // MARK: - Schema
    //
    // MIGRATION RULES:
    // 1. NEVER DROP the main 'attachments' table
    // 2. New columns: ALTER TABLE ADD COLUMN (silently ignored if exists)
    // 3. FTS changes: drop/recreate FTS virtual table + triggers, then rebuild from main table
    // 4. Bump PRAGMA user_version only after successful migration

    private func createSchema() throws {
        // 1. Base table
        let createTable = """
        CREATE TABLE IF NOT EXISTS attachments (
            id              TEXT PRIMARY KEY,
            messageId       TEXT NOT NULL,
            attachmentId    TEXT NOT NULL,
            filename        TEXT NOT NULL,
            mimeType        TEXT,
            fileType        TEXT,
            size            INTEGER DEFAULT 0,
            senderEmail     TEXT,
            senderName      TEXT,
            emailSubject    TEXT,
            emailDate       REAL,
            direction       TEXT DEFAULT 'received',
            indexedAt       REAL,
            indexingStatus  TEXT DEFAULT 'pending',
            extractedText   TEXT,
            embedding       BLOB
        );
        """
        if sqlite3_exec(db, createTable, nil, nil, nil) != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw AttachmentDatabaseError.schemaFailed(msg)
        }

        // 1b. Scanned messages tracking table
        sqlite3_exec(db, """
        CREATE TABLE IF NOT EXISTS scanned_messages (
            messageID TEXT NOT NULL,
            accountID TEXT NOT NULL,
            PRIMARY KEY (messageID, accountID)
        )
        """, nil, nil, nil)

        // 1c. Attachment scan state tracking table
        sqlite3_exec(db, """
        CREATE TABLE IF NOT EXISTS scan_state (
            accountID  TEXT PRIMARY KEY,
            pageToken  TEXT,
            isComplete INTEGER DEFAULT 0,
            updatedAt  REAL
        )
        """, nil, nil, nil)

        // 2. Column migrations (only if column doesn't exist yet)
        addColumnIfMissing("attachments", column: "retryCount", definition: "INTEGER DEFAULT 0")
        addColumnIfMissing("attachments", column: "emailBody", definition: "TEXT")
        addColumnIfMissing("attachments", column: "accountID", definition: "TEXT")
        // Clean up pre-migration rows without accountID — they can't be attributed to any account
        sqlite3_exec(db, "DELETE FROM attachments WHERE accountID IS NULL", nil, nil, nil)

        // 3. FTS migration — rebuild when schema changes
        migrateFTS()
    }

    private func migrateFTS() {
        // Check schema version
        var version: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW { version = sqlite3_column_int(stmt, 0) }
            sqlite3_finalize(stmt)
        }

        // v0 → v1: add emailBody to FTS index
        if version < 1 {
            exec("DROP TRIGGER IF EXISTS attachments_ai")
            exec("DROP TRIGGER IF EXISTS attachments_ad")
            exec("DROP TRIGGER IF EXISTS attachments_au")
            exec("DROP TABLE IF EXISTS attachments_fts")
        }

        // Create FTS + triggers (idempotent via IF NOT EXISTS)
        let fts = """
        CREATE VIRTUAL TABLE IF NOT EXISTS attachments_fts USING fts5 (
            extractedText, filename, emailSubject, emailBody,
            content='attachments', content_rowid='rowid'
        );

        CREATE TRIGGER IF NOT EXISTS attachments_ai AFTER INSERT ON attachments BEGIN
            INSERT INTO attachments_fts (rowid, extractedText, filename, emailSubject, emailBody)
            VALUES (new.rowid, new.extractedText, new.filename, new.emailSubject, new.emailBody);
        END;

        CREATE TRIGGER IF NOT EXISTS attachments_ad AFTER DELETE ON attachments BEGIN
            INSERT INTO attachments_fts (attachments_fts, rowid, extractedText, filename, emailSubject, emailBody)
            VALUES ('delete', old.rowid, old.extractedText, old.filename, old.emailSubject, old.emailBody);
        END;

        CREATE TRIGGER IF NOT EXISTS attachments_au
            AFTER UPDATE OF extractedText, filename, emailSubject, emailBody ON attachments BEGIN
            INSERT INTO attachments_fts (attachments_fts, rowid, extractedText, filename, emailSubject, emailBody)
            VALUES ('delete', old.rowid, old.extractedText, old.filename, old.emailSubject, old.emailBody);
            INSERT INTO attachments_fts (rowid, extractedText, filename, emailSubject, emailBody)
            VALUES (new.rowid, new.extractedText, new.filename, new.emailSubject, new.emailBody);
        END;
        """
        sqlite3_exec(db, fts, nil, nil, nil)

        if version < 1 {
            exec("INSERT INTO attachments_fts(attachments_fts) VALUES('rebuild')")
            exec("PRAGMA user_version = 1")
            print("[AttachmentDB] Migrated FTS to v1 (added emailBody)")
        }

        // v1 → v2: rebuild FTS + vacuum after accountID cleanup
        if version < 2 {
            exec("INSERT INTO attachments_fts(attachments_fts) VALUES('rebuild')")
            exec("VACUUM")
            exec("PRAGMA user_version = 2")
            print("[AttachmentDB] Migrated to v2 (accountID cleanup + vacuum)")
        }
    }

    // MARK: - Insert

    func insertAttachment(_ attachment: IndexedAttachment) {
        queue.sync {
            _insertAttachment(attachment)
        }
    }

    private func _insertAttachment(_ attachment: IndexedAttachment) {
        let sql = """
        INSERT OR IGNORE INTO attachments
            (id, messageId, attachmentId, filename, mimeType, fileType, size,
             senderEmail, senderName, emailSubject, emailDate, direction,
             indexedAt, indexingStatus, extractedText, emailBody, accountID)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, attachment.id)
        bindText(stmt, 2, attachment.messageId)
        bindText(stmt, 3, attachment.attachmentId)
        bindText(stmt, 4, attachment.filename)
        bindTextOrNull(stmt, 5, attachment.mimeType)
        bindText(stmt, 6, attachment.fileType)
        sqlite3_bind_int64(stmt, 7, Int64(attachment.size))
        bindTextOrNull(stmt, 8, attachment.senderEmail)
        bindTextOrNull(stmt, 9, attachment.senderName)
        bindTextOrNull(stmt, 10, attachment.emailSubject)
        if let date = attachment.emailDate {
            sqlite3_bind_double(stmt, 11, date.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        bindText(stmt, 12, attachment.direction.rawValue)
        if let indexedAt = attachment.indexedAt {
            sqlite3_bind_double(stmt, 13, indexedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 13)
        }
        bindText(stmt, 14, attachment.indexingStatus.rawValue)
        bindTextOrNull(stmt, 15, attachment.extractedText)
        bindTextOrNull(stmt, 16, attachment.emailBody)
        bindText(stmt, 17, attachment.accountID)

        sqlite3_step(stmt)
    }

    // MARK: - Update indexed content

    func updateIndexedContent(id: String, text: String?, embedding: [Float]?, status: IndexedAttachment.IndexingStatus) {
        queue.sync {
            let sql = """
            UPDATE attachments
            SET extractedText = ?, embedding = ?, indexingStatus = ?, indexedAt = ?
            WHERE id = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            bindTextOrNull(stmt, 1, text)

            if let embedding {
                let data = serializeEmbedding(embedding)
                data.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(stmt, 2)
            }

            bindText(stmt, 3, status.rawValue)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            bindText(stmt, 5, id)

            sqlite3_step(stmt)
        }
    }

    // MARK: - Update email body (enrich from full-format fetch)

    func updateEmailBody(id: String, body: String) {
        queue.sync {
            let sql = "UPDATE attachments SET emailBody = ? WHERE id = ? AND emailBody IS NULL"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, body)
            bindText(stmt, 2, id)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Exists

    func exists(id: String) -> Bool {
        queue.sync {
            let sql = "SELECT 1 FROM attachments WHERE id = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    // MARK: - Message-level check

    func hasMessageAttachments(messageId: String) -> Bool {
        queue.sync {
            let sql = "SELECT 1 FROM attachments WHERE messageId = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, messageId)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    // MARK: - Retry

    func resetFailedForRetry(maxRetries: Int, accountID: String) {
        queue.sync {
            let sql = "UPDATE attachments SET indexingStatus = 'pending' WHERE indexingStatus = 'failed' AND retryCount < ? AND accountID = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(maxRetries))
            bindText(stmt, 2, accountID)
            sqlite3_step(stmt)
        }
    }

    func incrementRetry(id: String) {
        queue.sync {
            let sql = "UPDATE attachments SET indexingStatus = 'failed', retryCount = retryCount + 1 WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Pending

    func pendingAttachments(limit: Int = 50, accountID: String) -> [IndexedAttachment] {
        queue.sync {
            let sql = """
            SELECT * FROM attachments
            WHERE indexingStatus = 'pending' AND accountID = ?
            ORDER BY emailDate DESC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)
            sqlite3_bind_int64(stmt, 2, Int64(limit))
            return readRows(stmt)
        }
    }

    // MARK: - All

    func allAttachments(limit: Int = 100, offset: Int = 0, accountID: String) -> [IndexedAttachment] {
        queue.sync {
            let sql = """
            SELECT * FROM attachments
            WHERE accountID = ?
            ORDER BY emailDate DESC
            LIMIT ? OFFSET ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)
            sqlite3_bind_int64(stmt, 2, Int64(limit))
            sqlite3_bind_int64(stmt, 3, Int64(offset))
            return readRows(stmt)
        }
    }

    // MARK: - FTS Search

    func searchFTS(query: String, limit: Int = 30, accountID: String) -> [(IndexedAttachment, Double)] {
        queue.sync {
            let sanitized = sanitizeFTSQuery(query)
            guard !sanitized.isEmpty else { return [] }

            let sql = """
            SELECT a.*, abs(bm25(attachments_fts, 1.0, 5.0, 3.0, 0.5)) AS score
            FROM attachments_fts f
            JOIN attachments a ON a.rowid = f.rowid
            WHERE attachments_fts MATCH ? AND a.accountID = ?
            ORDER BY score DESC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, sanitized)
            bindText(stmt, 2, accountID)
            sqlite3_bind_int64(stmt, 3, Int64(limit))

            let columnCount = sqlite3_column_count(stmt)
            let scoreIndex = columnCount - 1  // score is always the last column in our SELECT

            var results: [(IndexedAttachment, Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let att = readRow(stmt)
                let score = sqlite3_column_double(stmt, scoreIndex)
                results.append((att, score))
            }
            return results
        }
    }

    // MARK: - All embeddings (for semantic search)

    func allEmbeddings(accountID: String, limit: Int = 1000) -> [(String, [Float])] {
        queue.sync {
            let sql = "SELECT id, embedding FROM attachments WHERE embedding IS NOT NULL AND accountID = ? ORDER BY emailDate DESC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)
            sqlite3_bind_int64(stmt, 2, Int64(limit))

            var results: [(String, [Float])] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idRaw = sqlite3_column_text(stmt, 0) else { continue }
                let id = String(cString: idRaw)
                if let blobPtr = sqlite3_column_blob(stmt, 1) {
                    let byteCount = Int(sqlite3_column_bytes(stmt, 1))
                    let floats = deserializeEmbedding(blobPtr, byteCount: byteCount)
                    results.append((id, floats))
                }
            }
            return results
        }
    }

    // MARK: - By ID

    func attachment(byId id: String) -> IndexedAttachment? {
        queue.sync {
            let sql = "SELECT * FROM attachments WHERE id = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readRow(stmt)
        }
    }

    // MARK: - Stats

    func stats(accountID: String) -> (total: Int, indexed: Int, pending: Int, failed: Int) {
        queue.sync {
            let sql = """
            SELECT
                COUNT(*),
                SUM(CASE WHEN indexingStatus = 'indexed' THEN 1 ELSE 0 END),
                SUM(CASE WHEN indexingStatus = 'pending' THEN 1 ELSE 0 END),
                SUM(CASE WHEN indexingStatus = 'failed' THEN 1 ELSE 0 END)
            FROM attachments
            WHERE accountID = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (0, 0, 0, 0) }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return (0, 0, 0, 0) }

            let total   = Int(sqlite3_column_int64(stmt, 0))
            let indexed = Int(sqlite3_column_int64(stmt, 1))
            let pending = Int(sqlite3_column_int64(stmt, 2))
            let failed  = Int(sqlite3_column_int64(stmt, 3))
            return (total, indexed, pending, failed)
        }
    }

    /// Distinct MIME types of unsupported attachments (for debugging).
    func unsupportedMimeTypes(accountID: String) -> [(mimeType: String, count: Int)] {
        queue.sync {
            let sql = """
            SELECT COALESCE(mimeType, 'unknown'), COUNT(*)
            FROM attachments
            WHERE indexingStatus = 'unsupported' AND accountID = ?
            GROUP BY mimeType
            ORDER BY COUNT(*) DESC
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)

            var results: [(String, Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let mime = columnText(stmt, 0) ?? "unknown"
                let count = Int(sqlite3_column_int64(stmt, 1))
                results.append((mime, count))
            }
            return results
        }
    }

    // MARK: - Storage Info

    /// Total size on disk (main DB + WAL + SHM files) in bytes.
    func databaseSizeBytes() -> Int64 {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("com.genyus.serif.app", isDirectory: true)
        let basePath = dir.appendingPathComponent("attachment-index.sqlite").path
        var total: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let filePath = basePath + suffix
            if let attrs = try? fm.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    // MARK: - Scanned Messages

    /// Returns all message IDs that have already been scanned (with or without attachments).
    func allScannedMessageIDs(accountID: String) -> Set<String> {
        queue.sync {
            let sql = "SELECT messageID FROM scanned_messages WHERE accountID = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)
            var ids: Set<String> = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let raw = sqlite3_column_text(stmt, 0) {
                    ids.insert(String(cString: raw))
                }
            }
            return ids
        }
    }

    /// Persists a batch of scanned message IDs so they are skipped on next launch.
    func markMessagesScanned(_ ids: [String], accountID: String) {
        queue.sync {
            let sql = "INSERT OR IGNORE INTO scanned_messages (messageID, accountID) VALUES (?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for id in ids {
                sqlite3_reset(stmt)
                bindText(stmt, 1, id)
                bindText(stmt, 2, accountID)
                sqlite3_step(stmt)
            }
        }
    }

    /// Delete all rows for a specific account, rebuild FTS, and reclaim disk space.
    func deleteByAccountID(_ accountID: String) {
        queue.sync {
            let sql = "DELETE FROM attachments WHERE accountID = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)
            sqlite3_step(stmt)
            // Also clean scanned_messages for this account
            let sql2 = "DELETE FROM scanned_messages WHERE accountID = ?"
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(db, sql2, -1, &stmt2, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt2) }
                bindText(stmt2, 1, accountID)
                sqlite3_step(stmt2)
            }
            // Also clean scan_state for this account
            let sql3 = "DELETE FROM scan_state WHERE accountID = ?"
            var stmt3: OpaquePointer?
            if sqlite3_prepare_v2(db, sql3, -1, &stmt3, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt3) }
                bindText(stmt3, 1, accountID)
                sqlite3_step(stmt3)
            }
            exec("INSERT INTO attachments_fts(attachments_fts) VALUES('rebuild')")
            exec("VACUUM")
        }
    }

    /// Delete all rows from the attachments, scanned_messages, and scan_state tables, rebuild FTS, and reclaim disk space.
    func clearAll() {
        queue.sync {
            exec("DELETE FROM attachments")
            exec("DELETE FROM scanned_messages")
            exec("DELETE FROM scan_state")
            exec("INSERT INTO attachments_fts(attachments_fts) VALUES('rebuild')")
            exec("VACUUM")
        }
    }

    // MARK: - Scan State

    struct ScanState {
        let pageToken: String?
        let isComplete: Bool
    }

    func loadScanState(accountID: String) -> ScanState? {
        queue.sync {
            let sql = "SELECT pageToken, isComplete FROM scan_state WHERE accountID = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let pageToken = columnText(stmt, 0)
            let isComplete = sqlite3_column_int(stmt, 1) != 0
            return ScanState(pageToken: pageToken, isComplete: isComplete)
        }
    }

    func saveScanState(accountID: String, pageToken: String?, isComplete: Bool) {
        queue.sync {
            let sql = """
            INSERT INTO scan_state (accountID, pageToken, isComplete, updatedAt)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(accountID) DO UPDATE SET
                pageToken = excluded.pageToken,
                isComplete = excluded.isComplete,
                updatedAt = excluded.updatedAt
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)
            bindTextOrNull(stmt, 2, pageToken)
            sqlite3_bind_int(stmt, 3, isComplete ? 1 : 0)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            sqlite3_step(stmt)
        }
    }

    func clearScanState(accountID: String) {
        queue.sync {
            let sql = "DELETE FROM scan_state WHERE accountID = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, accountID)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Helpers: Row Mapping

    private func readRows(_ stmt: OpaquePointer?) -> [IndexedAttachment] {
        var rows: [IndexedAttachment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(readRow(stmt))
        }
        return rows
    }

    /// Maps a `SELECT *` row to `IndexedAttachment`.
    /// Column order must match the CREATE TABLE definition.
    private func readRow(_ stmt: OpaquePointer?) -> IndexedAttachment {
        let id            = columnText(stmt, 0) ?? ""
        let messageId     = columnText(stmt, 1) ?? ""
        let attachmentId  = columnText(stmt, 2) ?? ""
        let filename      = columnText(stmt, 3) ?? ""
        let mimeType      = columnText(stmt, 4)
        let fileType      = columnText(stmt, 5) ?? "other"
        let size          = Int(sqlite3_column_int64(stmt, 6))
        let senderEmail   = columnText(stmt, 7)
        let senderName    = columnText(stmt, 8)
        let emailSubject  = columnText(stmt, 9)

        var emailDate: Date?
        if sqlite3_column_type(stmt, 10) != SQLITE_NULL {
            emailDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
        }

        let directionRaw  = columnText(stmt, 11) ?? "received"
        let direction     = IndexedAttachment.Direction(rawValue: directionRaw) ?? .received

        var indexedAt: Date?
        if sqlite3_column_type(stmt, 12) != SQLITE_NULL {
            indexedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12))
        }

        let statusRaw     = columnText(stmt, 13) ?? "pending"
        let status        = IndexedAttachment.IndexingStatus(rawValue: statusRaw) ?? .pending
        let extractedText = columnText(stmt, 14)
        // Column 15 = embedding BLOB — not mapped into IndexedAttachment
        // Column 16 = retryCount — managed separately
        let emailBody     = columnText(stmt, 17)
        let accountID     = columnText(stmt, 18) ?? ""

        return IndexedAttachment(
            id: id,
            messageId: messageId,
            attachmentId: attachmentId,
            filename: filename,
            mimeType: mimeType,
            fileType: fileType,
            size: size,
            senderEmail: senderEmail,
            senderName: senderName,
            emailSubject: emailSubject,
            emailDate: emailDate,
            direction: direction,
            indexedAt: indexedAt,
            indexingStatus: status,
            extractedText: extractedText,
            emailBody: emailBody,
            accountID: accountID
        )
    }

    // MARK: - Helpers: SQLite Binding

    /// Bind a non-optional String using strdup so the pointer stays alive until SQLite copies it.
    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        let cStr = strdup(value)
        sqlite3_bind_text(stmt, index, cStr, -1) { ptr in free(ptr) }
    }

    /// Bind an optional String — NULL if nil.
    private func bindTextOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            bindText(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    /// Read a TEXT column as optional String.
    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    /// Adds a column only if it doesn't already exist (avoids "duplicate column" warnings).
    private func addColumnIfMissing(_ table: String, column: String, definition: String) {
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1), String(cString: name) == column { return }
        }
        sqlite3_exec(db, "ALTER TABLE \(table) ADD COLUMN \(column) \(definition)", nil, nil, nil)
    }

    /// Fire-and-forget exec (for PRAGMAs, etc).
    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    // MARK: - Helpers: FTS Query Sanitization

    /// Wraps each word in double-quotes to avoid FTS5 syntax errors.
    private func sanitizeFTSQuery(_ raw: String) -> String {
        raw.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"" }
            .joined(separator: " ")
    }

    // MARK: - Helpers: Embedding Serialization

    private func serializeEmbedding(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func deserializeEmbedding(_ ptr: UnsafeRawPointer, byteCount: Int) -> [Float] {
        let count = byteCount / MemoryLayout<Float>.size
        let typed = ptr.bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: typed, count: count))
    }
}
