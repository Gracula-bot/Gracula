import Foundation

public enum TDLibLibraryLocator {
    public static func candidatePaths(preferredPath: String?) -> [String] {
        var paths: [String] = []
        if let preferredPath = preferredPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferredPath.isEmpty {
            paths.append(preferredPath)
        }
        paths.append(contentsOf: [
            "/opt/homebrew/lib/libtdjson.dylib",
            "/usr/local/lib/libtdjson.dylib",
            "/usr/lib/libtdjson.dylib",
            "libtdjson.dylib"
        ])
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    public static func resolveExistingPath(
        preferredPath: String?,
        fileManager: FileManager = .default
    ) -> String? {
        candidatePaths(preferredPath: preferredPath).first { candidate in
            candidate != "libtdjson.dylib" && fileManager.fileExists(atPath: candidate)
        }
    }
}
