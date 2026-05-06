import Foundation
import Persistence

let log = Logger.shared

final class Logger: @unchecked Sendable {
    enum LoggerLevel: Int, Comparable {
        case off
        case error
        case warning
        case info
        case debug

        static func < (lhs: LoggerLevel, rhs: LoggerLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .off:
                return "OFF"
            case .error:
                return "ERROR"
            case .warning:
                return "WARN"
            case .info:
                return "INFO"
            case .debug:
                return "DEBUG"
            }
        }
    }

    static let shared = Logger()

    private let queue = DispatchQueue(label: "GraculaExample.Logger")
    private let fileManager: FileManager
    private let logFileURL: URL

    var level: LoggerLevel {
        currentLevel
    }

    private let currentLevel: LoggerLevel

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.currentLevel = .debug
        self.logFileURL = ProjectRuntimeLayout.resolveDefault().logsDirectoryURL
            .appendingPathComponent("app-debug.log")
    }

    var logFilePath: String {
        logFileURL.path(percentEncoded: false)
    }

    func debug(_ message: @autoclosure @escaping () -> String,
               file: StaticString = #fileID,
               function: StaticString = #function,
               line: UInt = #line) {
        write(.debug, message: message, file: file, function: function, line: line)
    }

    func info(_ message: @autoclosure @escaping () -> String,
              file: StaticString = #fileID,
              function: StaticString = #function,
              line: UInt = #line) {
        write(.info, message: message, file: file, function: function, line: line)
    }

    func warning(_ message: @autoclosure @escaping () -> String,
                 file: StaticString = #fileID,
                 function: StaticString = #function,
                 line: UInt = #line) {
        write(.warning, message: message, file: file, function: function, line: line)
    }

    func error(_ message: @autoclosure @escaping () -> String,
               file: StaticString = #fileID,
               function: StaticString = #function,
               line: UInt = #line) {
        write(.error, message: message, file: file, function: function, line: line)
    }

    private func write(_ level: LoggerLevel,
                       message: @escaping () -> String,
                       file: StaticString,
                       function: StaticString,
                       line: UInt) {
        guard level.rawValue <= currentLevel.rawValue, level != .off else {
            return
        }

        let text = message()
        let filePath = String(describing: file)
        let functionName = String(describing: function)
        let logFileURL = self.logFileURL

        queue.async {
            let timestamp = Self.timestampFormatter.string(from: Date())
            let fileName = filePath.split(separator: "/").last.map(String.init) ?? filePath
            let entry = "[\(timestamp)] [\(level.label)] [\(fileName):\(line)] \(functionName) - \(text)"

            FileHandle.standardError.write(Data((entry + "\n").utf8))

            do {
                try FileManager.default.createDirectory(at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = Data((entry + "\n").utf8)
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    let handle = try FileHandle(forWritingTo: logFileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: logFileURL)
                }
            } catch {
                FileHandle.standardError.write(Data(("[LOGGER_ERROR] \(error.localizedDescription)\n").utf8))
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

enum PerformanceLog {
    static func checkpoint() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func elapsedDescription(since start: UInt64) -> String {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let milliseconds = Double(elapsed) / 1_000_000
        return String(format: "%.2fms", milliseconds)
    }
}
