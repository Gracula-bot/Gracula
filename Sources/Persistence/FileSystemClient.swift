import Foundation

public protocol FileSystemClient: Sendable {
    func readFile(at url: URL) async throws -> String
    func writeFile(_ text: String, at url: URL) async throws
}

public struct LocalFileSystemClient: FileSystemClient {
    public init() {}

    public func readFile(at url: URL) async throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    public func writeFile(_ text: String, at url: URL) async throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

