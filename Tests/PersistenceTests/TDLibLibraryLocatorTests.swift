import Foundation
import Persistence
import Testing

@Test
func tdlibLibraryLocatorPrefersExistingPreferredPath() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tdlib-locator-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let libraryPath = directory.appendingPathComponent("libtdjson.dylib").path
    FileManager.default.createFile(atPath: libraryPath, contents: Data(), attributes: nil)

    let resolvedPath = TDLibLibraryLocator.resolveExistingPath(preferredPath: libraryPath)

    #expect(resolvedPath == libraryPath)
}

@Test
func tdlibLibraryLocatorFallsBackWhenPreferredPathIsMissing() {
    let missingPreferredPath = "/tmp/gracula-missing-\(UUID().uuidString)/libtdjson.dylib"
    let resolvedPath = TDLibLibraryLocator.resolveExistingPath(preferredPath: missingPreferredPath)

    if let resolvedPath {
        #expect(resolvedPath != missingPreferredPath)
    } else {
        #expect(resolvedPath == nil)
    }
}
