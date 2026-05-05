import AppKit
import Application
import ApplicationServices
import Foundation

public final class TelegramMacAppAutomationService: TelegramService, @unchecked Sendable {
    private let workspace: NSWorkspace
    private let pasteboard: NSPasteboard
    private let fileManager: FileManager

    public init(
        workspace: NSWorkspace = .shared,
        pasteboard: NSPasteboard = .general,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.pasteboard = pasteboard
        self.fileManager = fileManager
    }

    public func getLatestChat() async throws -> TelegramChat {
        try await ensureTelegramAvailable()
        return TelegramChat(id: "telegram-current-chat", displayName: "текущий чат Telegram")
    }

    public func findChat(byName name: String) async throws -> TelegramChat {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TelegramCommandError.chatNotFound(name)
        }
        try await ensureTelegramAvailable()
        return TelegramChat(id: "telegram-chat-\(trimmedName)", displayName: trimmedName)
    }

    public func getLatestMessage(chatId: String) async throws -> TelegramMessage {
        try await ensureTelegramAvailable()
        throw TelegramCommandError.unsafeCurrentChat
    }

    public func prepareReply(chatId: String, text: String) async throws -> PendingTelegramReply {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TelegramCommandError.emptyMessageText
        }
        try await ensureTelegramAvailable()
        return PendingTelegramReply(
            chatId: chatId,
            chatName: displayName(for: chatId),
            messageText: trimmedText,
            createdAt: Date(),
            status: .pending
        )
    }

    @MainActor
    public func sendReply(_ reply: PendingTelegramReply) async throws {
        guard reply.status == .pending else {
            throw TelegramCommandError.noPendingReply
        }

        let trimmedText = reply.messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TelegramCommandError.emptyMessageText
        }

        try await ensureTelegramAvailable()
        try ensureAccessibilityPermission()
        try await sendViaTelegramUI(chatId: reply.chatId, text: trimmedText)
    }

    @MainActor
    private func sendViaTelegramUI(chatId: String, text: String) async throws {
        guard let appURL = telegramApplicationURL() else {
            throw TelegramCommandError.telegramNotInstalled
        }

        let runningApplication = await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { application, error in
                if let error {
                    NSLog("telegram_open_failed %@", error.localizedDescription)
                }
                continuation.resume(returning: application)
            }
        }
        guard let runningApplication else {
            throw TelegramCommandError.telegramNotRunning
        }

        try await activate(runningApplication)

        let chatName = displayName(for: chatId)
        if chatId != "telegram-current-chat" {
            try setClipboard(chatName)
            pressKey(.k, modifiers: .maskCommand)
            try await pause(0.15)
            pressKey(.v, modifiers: .maskCommand)
            try await pause(0.55)
            pressKey(.return)
            try await pause(0.55)
        }

        try paste(text)
        try await pause(0.15)
        pressKey(.return)
    }

    @MainActor
    private func activate(_ application: NSRunningApplication) async throws {
        application.activate(options: [.activateAllWindows])
        for _ in 0..<20 {
            if application.isActive {
                try await pause(0.2)
                return
            }
            try await pause(0.1)
        }
        throw TelegramCommandError.telegramAPIError("Telegram did not become active.")
    }

    @MainActor
    private func paste(_ text: String) throws {
        try setClipboard(text)
        pressKey(.v, modifiers: .maskCommand)
    }

    @MainActor
    private func setClipboard(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TelegramCommandError.telegramAPIError("Cannot write Telegram message to clipboard.")
        }
    }

    private func pressKey(_ key: KeyboardKey, modifiers: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false) else {
            return
        }
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func pause(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func ensureAccessibilityPermission() throws {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw TelegramCommandError.missingPermission("Accessibility")
        }
    }

    @MainActor
    private func ensureTelegramAvailable() async throws {
        guard telegramApplicationURL() != nil else {
            throw TelegramCommandError.telegramNotInstalled
        }
    }

    private func telegramApplicationURL() -> URL? {
        let candidates = [
            "/Applications/Telegram.app",
            "/Applications/Telegram Desktop.app",
            "\(NSHomeDirectory())/Applications/Telegram.app",
            "\(NSHomeDirectory())/Applications/Telegram Desktop.app"
        ].map(URL.init(fileURLWithPath:))

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func displayName(for chatId: String) -> String {
        let prefix = "telegram-chat-"
        if chatId.hasPrefix(prefix) {
            return String(chatId.dropFirst(prefix.count))
        }
        return "последнем чате Telegram"
    }
}

private enum KeyboardKey: CGKeyCode {
    case k = 40
    case v = 9
    case `return` = 36
}
