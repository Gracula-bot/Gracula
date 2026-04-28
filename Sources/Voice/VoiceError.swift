public enum VoiceError: Error, Sendable, Equatable {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case pipelineAlreadyRunning
}

