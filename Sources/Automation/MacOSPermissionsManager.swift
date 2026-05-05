import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Speech

public struct MacOSPermissionSnapshot: Sendable, Equatable {
    public let microphone: MacOSPermissionStatus
    public let speechRecognition: MacOSPermissionStatus
    public let accessibility: MacOSPermissionStatus
    public let automation: MacOSPermissionStatus

    public init(
        microphone: MacOSPermissionStatus,
        speechRecognition: MacOSPermissionStatus,
        accessibility: MacOSPermissionStatus,
        automation: MacOSPermissionStatus
    ) {
        self.microphone = microphone
        self.speechRecognition = speechRecognition
        self.accessibility = accessibility
        self.automation = automation
    }
}

public enum MacOSPermissionStatus: String, Sendable, Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unknown
}

public protocol PermissionsManaging: Sendable {
    func snapshot() async -> MacOSPermissionSnapshot
    func requestMicrophonePermission() async -> MacOSPermissionStatus
    func requestSpeechRecognitionPermission() async -> MacOSPermissionStatus
    func requestAccessibilityPermission(prompt: Bool) async -> MacOSPermissionStatus
}

public struct PermissionsManager: PermissionsManaging {
    public init() {}

    public func snapshot() async -> MacOSPermissionSnapshot {
        MacOSPermissionSnapshot(
            microphone: microphoneStatus(),
            speechRecognition: speechRecognitionStatus(),
            accessibility: accessibilityStatus(prompt: false),
            automation: .notDetermined
        )
    }

    public func requestMicrophonePermission() async -> MacOSPermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .authorized : .denied
    }

    public func requestSpeechRecognitionPermission() async -> MacOSPermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.mapSpeechStatus(status))
            }
        }
    }

    public func requestAccessibilityPermission(prompt: Bool) async -> MacOSPermissionStatus {
        accessibilityStatus(prompt: prompt)
    }

    private func microphoneStatus() -> MacOSPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    private func speechRecognitionStatus() -> MacOSPermissionStatus {
        Self.mapSpeechStatus(SFSpeechRecognizer.authorizationStatus())
    }

    private static func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> MacOSPermissionStatus {
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    private func accessibilityStatus(prompt: Bool) -> MacOSPermissionStatus {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .authorized : .denied
    }
}
