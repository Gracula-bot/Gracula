import AppKit
import Foundation

public protocol URLOpening: Sendable {
    func open(_ url: URL) async throws
}

public protocol AppOpening: Sendable {
    func openApp(named name: String) async throws
}

public protocol OnlyFansPosting: Sendable {
    func publishPost(text: String) async throws
}

public struct WorkspaceOpeningClient: URLOpening, AppOpening, OnlyFansPosting {
    public init() {}

    @MainActor
    public func open(_ url: URL) async throws {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    public func openApp(named name: String) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        try await NSWorkspace.shared.openApplication(
            at: applicationURL(named: name),
            configuration: configuration
        )
    }

    @MainActor
    public func publishPost(text: String) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AutomationError.emptyPostText
        }

        let createPostURL = URL(string: "https://onlyfans.com/posts/create")!
        NSWorkspace.shared.open(createPostURL)
        try await runOnlyFansPostScript(text: trimmedText)
    }

    private func runOnlyFansPostScript(text: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", onlyFansAppleScript(text: text)]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AutomationError.browserAutomationFailed(message ?? "osascript exited with \(process.terminationStatus)")
        }
    }

    private func onlyFansAppleScript(text: String) -> String {
        let script = singleLineJavaScript(onlyFansPublishJavaScript(text: text))
        return """
        set postURL to "https://onlyfans.com/posts/create"
        set jsSource to \(appleScriptStringLiteral(script))

        tell application "Google Chrome"
            activate
            if (count of windows) = 0 then make new window
            set targetTab to active tab of front window
            set URL of targetTab to postURL
            delay 4
            execute targetTab javascript jsSource
        end tell
        """
    }

    private func onlyFansPublishJavaScript(text: String) -> String {
        """
        (async () => {
          const text = \(jsonStringLiteral(text));
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          const visible = element => {
            const rect = element.getBoundingClientRect();
            const style = window.getComputedStyle(element);
            return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
          };
          const waitFor = async predicate => {
            for (let index = 0; index < 60; index += 1) {
              const value = predicate();
              if (value) return value;
              await sleep(500);
            }
            throw new Error('OnlyFans post editor was not found.');
          };
          const editor = await waitFor(() => {
            const selectors = [
              '[contenteditable="true"]',
              'textarea',
              '[role="textbox"]'
            ];
            for (const selector of selectors) {
              const match = [...document.querySelectorAll(selector)].find(visible);
              if (match) return match;
            }
            return null;
          });
          editor.focus();
          if (editor.tagName === 'TEXTAREA' || editor.tagName === 'INPUT') {
            editor.value = text;
          } else {
            editor.textContent = text;
          }
          editor.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
          editor.dispatchEvent(new Event('change', { bubbles: true }));
          await sleep(1000);
          const button = await waitFor(() => {
            const labels = ['post', 'publish', 'send', 'опубликовать', 'отправить', 'разместить'];
            return [...document.querySelectorAll('button')]
              .filter(visible)
              .find(candidate => {
                const label = (candidate.innerText || candidate.getAttribute('aria-label') || '').trim().toLowerCase();
                return !candidate.disabled && labels.some(value => label.includes(value));
              });
          });
          button.click();
          return true;
        })();
        """
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private func jsonStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }

    private func singleLineJavaScript(_ value: String) -> String {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func applicationURL(named name: String) throws -> URL {
        let fileManager = FileManager.default
        let candidates = candidateApplicationNames(for: name).flatMap { appName in
            [
                URL(fileURLWithPath: "/Applications").appendingPathComponent(appName),
                URL(fileURLWithPath: "/System/Applications").appendingPathComponent(appName),
                fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications")
                    .appendingPathComponent(appName)
            ]
        }

        if let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return url
        }

        throw AutomationError.applicationNotFound(name)
    }

    private func candidateApplicationNames(for name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if trimmed.hasSuffix(".app") {
            return [trimmed]
        }

        return ["\(trimmed).app", trimmed]
    }
}

public enum AutomationError: LocalizedError, Sendable, Equatable {
    case applicationNotFound(String)
    case emptyPostText
    case browserAutomationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .applicationNotFound(let name):
            return "Application not found: \(name)"
        case .emptyPostText:
            return "OnlyFans post text is empty. Add the post text after the command."
        case .browserAutomationFailed(let message):
            return "Browser automation failed: \(message)"
        }
    }
}
