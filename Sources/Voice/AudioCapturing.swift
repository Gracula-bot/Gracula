import Foundation

public struct AudioFrame: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double
    public let timestampNanos: UInt64

    public init(samples: [Float], sampleRate: Double, timestampNanos: UInt64) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestampNanos = timestampNanos
    }
}

public protocol AudioCapturing: Sendable {
    func frames() async throws -> AsyncThrowingStream<AudioFrame, any Error>
}

