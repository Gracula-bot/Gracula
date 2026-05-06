import Persistence
import SwiftUI

@main
struct GraculaExampleApp: App {
    init() {
        let layout = ProjectRuntimeLayout.resolveDefault()
        let store = AppConfigurationStore(layout: layout)
        let bootstrapper = AppBootstrapper(
            layout: layout,
            store: store,
            verifier: DependencyVerifier(layout: layout),
            installer: RuntimeDependencyInstaller(layout: layout)
        )

        do {
            _ = try bootstrapper.bootstrapFoundation()
        } catch {
            FileHandle.standardError.write(
                Data("GraculaExample bootstrap failed: \(error.localizedDescription)\n".utf8)
            )
        }
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
