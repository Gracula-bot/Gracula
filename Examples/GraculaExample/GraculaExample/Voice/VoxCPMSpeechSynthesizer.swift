import Foundation

struct VoxCPMSpeechSynthesisConfiguration: Sendable {
    let baseURL: URL
    let modelName: String
    let voiceName: String
}

final class VoxCPMSpeechSynthesizer: SpeechSynthesizing, @unchecked Sendable {
    private let configuration: VoxCPMSpeechSynthesisConfiguration
    private let session: URLSession

    init(
        configuration: VoxCPMSpeechSynthesisConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func synthesizeSpeech(from text: String) async throws -> URL {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw VoiceSynthesisError.emptyText
        }

        let endpointURL = configuration.baseURL
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("speech")

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/wav", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(VoxCPMAudioSpeechRequest(
            model: configuration.modelName,
            input: trimmedText,
            voice: configuration.voiceName
        ))

        let startedAt = PerformanceLog.checkpoint()
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceSynthesisError.unexpectedResponse("VoxCPM server returned a non-HTTP response.")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? "<binary body>"
            throw VoiceSynthesisError.requestFailed("VoxCPM server returned HTTP \(httpResponse.statusCode): \(body)")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxcpm-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try data.write(to: outputURL, options: [.atomic])

        log.debug("VoxCPM synthesis completed in \(PerformanceLog.elapsedDescription(since: startedAt)); file=\(outputURL.lastPathComponent); bytes=\(data.count)")
        return outputURL
    }
}

private struct VoxCPMAudioSpeechRequest: Codable, Sendable {
    let model: String
    let input: String
    let voice: String
}
