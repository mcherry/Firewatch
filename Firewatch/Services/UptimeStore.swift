import Foundation
import SQLite3

/// Persistent SQLite store for service health history.
/// All C-level SQLite interop is contained here — callers use clean Swift methods.
final class UptimeStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.firewatch.uptimestore")

    init() {
        let dir = appSupportDirectory
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let dbPath = dir.appendingPathComponent("uptime.sqlite").path
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            NSLog("[Firewatch] Failed to open uptime database: \(errorMessage)")
            db = nil
            return
        }

        // Enable WAL mode for better concurrent read performance
        execute("PRAGMA journal_mode=WAL")
        createSchema()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Public API

    /// Logs the current health of all services as a single batch.
    func logStatus(services: [ServiceInfo]) {
        queue.sync {
            let now = Date().timeIntervalSince1970
            let sql = "INSERT INTO status_log (timestamp, serviceId, serviceName, health) VALUES (?, ?, ?, ?)"

            guard let stmt = prepareStatement(sql) else { return }
            defer { sqlite3_finalize(stmt) }

            for service in services {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_double(stmt, 1, now)
                bindText(stmt, index: 2, value: service.id)
                bindText(stmt, index: 3, value: service.name)
                sqlite3_bind_int(stmt, 4, Int32(service.health.severity))

                if sqlite3_step(stmt) != SQLITE_DONE {
                    NSLog("[Firewatch] Failed to insert status log: \(errorMessage)")
                }
            }
        }
    }

    /// Fetches log entries for a time range, optionally filtered by service.
    func fetchHistory(serviceId: String? = nil, from: Date, to: Date) -> [StatusLogEntry] {
        queue.sync {
            var entries: [StatusLogEntry] = []
            let fromTs = from.timeIntervalSince1970
            let toTs = to.timeIntervalSince1970

            let sql: String
            if let serviceId {
                sql = """
                    SELECT id, timestamp, serviceId, serviceName, health
                    FROM status_log
                    WHERE serviceId = ? AND timestamp >= ? AND timestamp <= ?
                    ORDER BY timestamp ASC
                    """
                guard let stmt = prepareStatement(sql) else { return entries }
                defer { sqlite3_finalize(stmt) }
                bindText(stmt, index: 1, value: serviceId)
                sqlite3_bind_double(stmt, 2, fromTs)
                sqlite3_bind_double(stmt, 3, toTs)
                entries = readEntries(stmt)
            } else {
                sql = """
                    SELECT id, timestamp, serviceId, serviceName, health
                    FROM status_log
                    WHERE timestamp >= ? AND timestamp <= ?
                    ORDER BY timestamp ASC
                    """
                guard let stmt = prepareStatement(sql) else { return entries }
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_double(stmt, 1, fromTs)
                sqlite3_bind_double(stmt, 2, toTs)
                entries = readEntries(stmt)
            }

            return entries
        }
    }

    /// Calculates uptime percentage (% of polls that were .operational) for a service in a time range.
    func fetchUptimePercentage(serviceId: String, from: Date, to: Date) -> Double {
        queue.sync {
            let fromTs = from.timeIntervalSince1970
            let toTs = to.timeIntervalSince1970
            let sql = """
                SELECT
                    COUNT(*) as total,
                    SUM(CASE WHEN health = 0 THEN 1 ELSE 0 END) as operational
                FROM status_log
                WHERE serviceId = ? AND timestamp >= ? AND timestamp <= ?
                """
            guard let stmt = prepareStatement(sql) else { return 0 }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, index: 1, value: serviceId)
            sqlite3_bind_double(stmt, 2, fromTs)
            sqlite3_bind_double(stmt, 3, toTs)

            if sqlite3_step(stmt) == SQLITE_ROW {
                let total = sqlite3_column_int64(stmt, 0)
                let operational = sqlite3_column_int64(stmt, 1)
                guard total > 0 else { return 0 }
                return Double(operational) / Double(total) * 100.0
            }
            return 0
        }
    }

    /// Returns all distinct services that have log data, with the most recent name used.
    func fetchAllServices() -> [(id: String, name: String)] {
        queue.sync {
            var results: [(id: String, name: String)] = []
            let sql = """
                SELECT serviceId, serviceName
                FROM status_log
                GROUP BY serviceId
                ORDER BY MAX(timestamp) DESC
                """
            guard let stmt = prepareStatement(sql) else { return results }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let sid = columnText(stmt, index: 0)
                let name = columnText(stmt, index: 1)
                results.append((id: sid, name: name))
            }
            return results
        }
    }

    // MARK: - Schema

    private func createSchema() {
        execute("""
            CREATE TABLE IF NOT EXISTS status_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                serviceId TEXT NOT NULL,
                serviceName TEXT NOT NULL,
                health INTEGER NOT NULL
            )
            """)
        execute("CREATE INDEX IF NOT EXISTS idx_status_log_service_time ON status_log (serviceId, timestamp)")
    }

    // MARK: - SQLite Helpers

    private var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Firewatch")
    }

    private var errorMessage: String {
        if let db, let msg = sqlite3_errmsg(db) {
            return String(cString: msg)
        }
        return "unknown error"
    }

    private func execute(_ sql: String) {
        guard let db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            NSLog("[Firewatch] SQL error: \(msg)")
            sqlite3_free(errMsg)
        }
    }

    private func prepareStatement(_ sql: String) -> OpaquePointer? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            NSLog("[Firewatch] Failed to prepare statement: \(errorMessage)")
            return nil
        }
        return stmt
    }

    private func bindText(_ stmt: OpaquePointer, index: Int32, value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func columnText(_ stmt: OpaquePointer, index: Int32) -> String {
        if let cString = sqlite3_column_text(stmt, index) {
            return String(cString: cString)
        }
        return ""
    }

    private func readEntries(_ stmt: OpaquePointer) -> [StatusLogEntry] {
        var entries: [StatusLogEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = StatusLogEntry(
                id: sqlite3_column_int64(stmt, 0),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                serviceId: columnText(stmt, index: 2),
                serviceName: columnText(stmt, index: 3),
                health: Int(sqlite3_column_int(stmt, 4))
            )
            entries.append(entry)
        }
        return entries
    }
}
