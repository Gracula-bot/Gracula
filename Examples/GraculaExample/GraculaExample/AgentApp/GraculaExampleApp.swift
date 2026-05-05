import SwiftUI

@main
struct GraculaExampleApp: App {
    init() {
        BackupFileCleanup.removeBackupFilesAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            AudioRecorderExampleView(
                viewModel: AudioRecorderViewModel(
                    recorder: DiskAudioRecorder()
                )
            )
        }
    }
}

private enum BackupFileCleanup {
    static func removeBackupFilesAtLaunch(fileManager: FileManager = .default) {
        let repoRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        guard let enumerator = fileManager.enumerator(
            at: repoRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            log.warning("Could not enumerate repo for .bak cleanup at \(repoRootURL.path(percentEncoded: false))")
            return
        }

        var removedCount = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.contains(".bak") else {
                continue
            }

            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }

            do {
                try fileManager.removeItem(at: fileURL)
                removedCount += 1
            } catch {
                log.warning("Failed to remove backup file at \(fileURL.path(percentEncoded: false)): \(error.localizedDescription)")
            }
        }

        if removedCount > 0 {
            log.info("Removed \(removedCount) backup file(s) at launch")
        }
    }
}
