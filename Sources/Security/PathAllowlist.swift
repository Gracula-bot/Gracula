import Foundation

public struct PathAllowlist: Sendable {
    private let approvedDirectories: [URL]

    public init(approvedDirectories: [URL]) {
        self.approvedDirectories = approvedDirectories.map {
            $0.standardizedFileURL.resolvingSymlinksInPath()
        }
    }

    public func validate(_ url: URL) throws -> URL {
        let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = standardizedURL.path

        guard approvedDirectories.contains(where: { directory in
            path == directory.path || path.hasPrefix(directory.path + "/")
        }) else {
            throw SecurityError.pathNotAllowed(path)
        }

        return standardizedURL
    }
}

