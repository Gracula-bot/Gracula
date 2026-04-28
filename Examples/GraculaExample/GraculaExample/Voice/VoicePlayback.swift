import AVFoundation
import Foundation

protocol AudioPlaying: Sendable {
    @MainActor func play(fileURL: URL) throws
}

@MainActor
final class SystemAudioPlayer: AudioPlaying {
    private var player: AVAudioPlayer?

    func play(fileURL: URL) throws {
        let player = try AVAudioPlayer(contentsOf: fileURL)
        player.prepareToPlay()
        player.play()
        self.player = player
    }
}
