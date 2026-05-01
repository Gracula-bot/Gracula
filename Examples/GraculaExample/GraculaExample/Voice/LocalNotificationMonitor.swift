import Foundation

struct LocalNotification: Identifiable, Equatable, Sendable {
    let id: Int64
    let appIdentifier: String
    let deliveredAt: Date
    let title: String
    let subtitle: String
    let body: String

    var spokenText: String {
        [
            readableAppName,
            title,
            subtitle,
            body
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private var readableAppName: String {
        appIdentifier
            .split(separator: ".")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "-", with: " ")
            ?? appIdentifier
    }
}

enum LocalNotificationMonitorError: LocalizedError {
    case databaseNotFound(String)
    case sqliteUnavailable
    case sqliteFailed(String)
    case invalidSQLiteOutput
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case let .databaseNotFound(path):
            return "Notification Center database was not found at \(path)."
        case .sqliteUnavailable:
            return "The sqlite3 command is not available on this Mac."
        case let .sqliteFailed(message):
            return "Could not read Notification Center database: \(message)"
        case .invalidSQLiteOutput:
            return "Notification Center database returned an unexpected row format."
        case .invalidPayload:
            return "Notification Center returned a notification payload that could not be decoded."
        }
    }
}

struct LocalNotificationReader: Sendable {
    private let databaseURL: URL
    private let sqlitePath: String

    init(
        databaseURL: URL = LocalNotificationReader.defaultDatabaseURL(),
        sqlitePath: String = "/usr/bin/sqlite3"
    ) {
        self.databaseURL = databaseURL
        self.sqlitePath = sqlitePath
    }

    func latestNotificationID() async throws -> Int64 {
        try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: databaseURL.path(percentEncoded: false)) else {
                throw LocalNotificationMonitorError.databaseNotFound(databaseURL.path(percentEncoded: false))
            }

            let output = try runSQLite(
                sqlitePath: sqlitePath,
                databaseURL: databaseURL,
                query: "select coalesce(max(rec_id), 0) from record;"
            )

            return Int64(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }.value
    }

    func notifications(after notificationID: Int64, limit: Int) async throws -> [LocalNotification] {
        try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: databaseURL.path(percentEncoded: false)) else {
                throw LocalNotificationMonitorError.databaseNotFound(databaseURL.path(percentEncoded: false))
            }

            let safeLimit = max(1, min(limit, 20))
            let query = """
            select record.rec_id, app.identifier, coalesce(record.delivered_date, record.request_date, 0), hex(record.data)
            from record
            join app on app.app_id = record.app_id
            where record.rec_id > \(notificationID)
            order by record.rec_id asc
            limit \(safeLimit);
            """

            let output = try runSQLite(
                sqlitePath: sqlitePath,
                databaseURL: databaseURL,
                query: query
            )

            return try output
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { row in
                    try parseNotificationRow(String(row))
                }
        }.value
    }

    static func defaultDatabaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent("group.com.apple.usernoted", isDirectory: true)
            .appendingPathComponent("db2", isDirectory: true)
            .appendingPathComponent("db")
    }
}

private func runSQLite(sqlitePath: String, databaseURL: URL, query: String) throws -> String {
    guard FileManager.default.isExecutableFile(atPath: sqlitePath) else {
        throw LocalNotificationMonitorError.sqliteUnavailable
    }

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: sqlitePath)
    process.arguments = [
        "-separator",
        "\u{1F}",
        databaseURL.path(percentEncoded: false),
        query
    ]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        throw LocalNotificationMonitorError.sqliteFailed(error.localizedDescription)
    }

    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let errorMessage = String(data: errorData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ""

    guard process.terminationStatus == 0 else {
        throw LocalNotificationMonitorError.sqliteFailed(errorMessage.isEmpty ? "sqlite3 exited with \(process.terminationStatus)" : errorMessage)
    }

    return String(data: outputData, encoding: .utf8) ?? ""
}

private func parseNotificationRow(_ row: String) throws -> LocalNotification {
    let fields = row.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
    guard fields.count == 4,
          let id = Int64(fields[0]),
          let deliveredTimeInterval = TimeInterval(fields[2]),
          let payloadData = Data(hexString: fields[3]) else {
        throw LocalNotificationMonitorError.invalidSQLiteOutput
    }

    guard let plist = try PropertyListSerialization.propertyList(
        from: payloadData,
        options: [],
        format: nil
    ) as? [String: Any],
          let request = plist["req"] as? [String: Any] else {
        throw LocalNotificationMonitorError.invalidPayload
    }

    return LocalNotification(
        id: id,
        appIdentifier: (plist["app"] as? String) ?? fields[1],
        deliveredAt: Date(timeIntervalSinceReferenceDate: deliveredTimeInterval),
        title: (request["titl"] as? String) ?? "",
        subtitle: (request["subt"] as? String) ?? "",
        body: (request["body"] as? String) ?? ""
    )
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else {
            return nil
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)

        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        self = Data(bytes)
    }
}
