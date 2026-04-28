import AppKit
import Foundation

public protocol URLOpening: Sendable {
    func open(_ url: URL) async throws
}

public protocol AppOpening: Sendable {
    func openApp(named name: String) async throws
}

public struct WorkspaceOpeningClient: URLOpening, AppOpening {
    public init() {}

    @MainActor
    public func open(_ url: URL) async throws {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    public func openApp(named name: String) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        try await NSWorkspace.shared.openApplication(
            at: applicationURL(named: name),
            configuration: configuration
        )
    }

    private func applicationURL(named name: String) throws -> URL {
        let fileManager = FileManager.default
        let candidates = candidateApplicationNames(for: name).flatMap { appName in
            [
                URL(fileURLWithPath: "/Applications").appendingPathComponent(appName),
                URL(fileURLWithPath: "/System/Applications").appendingPathComponent(appName),
                fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications")
                    .appendingPathComponent(appName)
            ]
        }

        if let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return url
        }

        throw AutomationError.applicationNotFound(name)
    }

    private func candidateApplicationNames(for name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if trimmed.hasSuffix(".app") {
            return [trimmed]
        }

        return ["\(trimmed).app", trimmed]
    }
}

public enum AutomationError: Error, Sendable, Equatable {
    case applicationNotFound(String)
}
