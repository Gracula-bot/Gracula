import SwiftUI

@main
struct GraculaExampleApp: App {
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
