import Foundation

private let log = BootstrapLogger()

private struct BootstrapLogger {
    func debug(_ message: @autoclosure () -> String) {
        write(level: "DEBUG", message())
    }

    func error(_ message: @autoclosure () -> String) {
        write(level: "ERROR", message())
    }

    private func write(level: String, _ message: String) {
        FileHandle.standardError.write(Data("[Bootstrap][\(level)] \(message)\n".utf8))
    }
}

public enum BootstrapStatus: Equatable, Sendable {
    case idle
    case bootstrapping
    case ready
    case degraded
    case failed
}

public struct BootstrapDiagnostic: Equatable, Sendable {
    public enum Level: String, Equatable, Sendable {
        case info
        case warning
        case error
    }

    public let level: Level
    public let message: String

    public init(level: Level, message: String) {
        self.level = level
        self.message = message
    }
}

public struct BootstrapDiagnostics: Equatable, Sendable {
    public var status: BootstrapStatus
    public var messages: [BootstrapDiagnostic]

    public init(status: BootstrapStatus = .idle, messages: [BootstrapDiagnostic] = []) {
        self.status = status
        self.messages = messages
    }
}

public struct DependencyReport: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let name: String
        public let available: Bool
        public let status: String
        public let installStrategy: String
        public let configuredPath: String
        public let detail: String
        public let isBlocking: Bool

        public init(
            name: String,
            available: Bool,
            status: String? = nil,
            installStrategy: String,
            configuredPath: String,
            detail: String = "",
            isBlocking: Bool = false
        ) {
            self.name = name
            self.available = available
            self.status = status ?? (available ? "ready" : "missing")
            self.installStrategy = installStrategy
            self.configuredPath = configuredPath
            self.detail = detail
            self.isBlocking = isBlocking
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public var missingCriticalItems: [Item] {
        items.filter { !$0.available && $0.isBlocking }
    }
}

private struct ProcessResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

public struct DependencyVerifier {
    public let layout: ProjectRuntimeLayout
    private let fileManager: FileManager

    public init(layout: ProjectRuntimeLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func verify(configuration: AppConfiguration) -> DependencyReport {
        let environment = AppConfigurationEnvironmentBuilder.build(configuration: configuration, layout: layout)
        var items: [DependencyReport.Item] = []

        items.append(
            DependencyReport.Item(
                name: "bootstrap-python",
                available: fileManager.isExecutableFile(atPath: configuration.python.bootstrapExecutablePath),
                installStrategy: "Use system Python only to create the project-local venv.",
                configuredPath: configuration.python.bootstrapExecutablePath,
                detail: fileManager.isExecutableFile(atPath: configuration.python.bootstrapExecutablePath) ? "Bootstrap Python is available." : "Bootstrap Python is unavailable.",
                isBlocking: true
            )
        )

        items.append(
            DependencyReport.Item(
                name: "venv-python",
                available: fileManager.isExecutableFile(atPath: configuration.python.executablePath),
                installStrategy: "Create `.openclaw/venv` with `python3 -m venv`.",
                configuredPath: configuration.python.executablePath,
                detail: fileManager.isExecutableFile(atPath: configuration.python.executablePath) ? "Project-local venv Python is available." : "Project-local venv Python is unavailable.",
                isBlocking: true
            )
        )

        items.append(verifySpeechPythonPackages(configuration: configuration, environment: environment))
        items.append(verifyWhisperModel(configuration: configuration, environment: environment))
        items.append(verifyFFmpeg(configuration: configuration, environment: environment))
        items.append(verifyQdrant(configuration: configuration, environment: environment))
        items.append(verifyTDLib(configuration: configuration))
        items.append(verifyGateway(configuration: configuration, environment: environment))
        items.append(verifyOpenAIKey(configuration: configuration))

        return DependencyReport(items: items)
    }

    private func verifySpeechPythonPackages(
        configuration: AppConfiguration,
        environment: [String: String]
    ) -> DependencyReport.Item {
        guard fileManager.isExecutableFile(atPath: configuration.python.executablePath) else {
            return DependencyReport.Item(
                name: "speech-python-packages",
                available: false,
                status: "missing",
                installStrategy: "Create the project-local venv before installing speech packages.",
                configuredPath: configuration.python.executablePath,
                detail: "Speech package verification skipped because venv Python is missing."
            )
        }

        let script = """
import importlib.util
import sys
modules = ["faster_whisper", "ctranslate2", "numpy", "tokenizers", "huggingface_hub"]
missing = [name for name in modules if importlib.util.find_spec(name) is None]
if missing:
    print(",".join(missing))
    raise SystemExit(1)
print("speech-stack-ok")
"""

        let result = runProcess(
            executableURL: URL(fileURLWithPath: configuration.python.executablePath),
            arguments: ["-c", script],
            environment: environment,
            currentDirectoryURL: layout.projectRootURL
        )
        let detail = result.stdout + result.stderr
        return DependencyReport.Item(
            name: "speech-python-packages",
            available: result.exitCode == 0,
            status: result.exitCode == 0 ? "ready" : "missing",
            installStrategy: "Install speech requirements into `.openclaw/venv` with the canonical requirements file.",
            configuredPath: configuration.python.speechRequirementsPath,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func verifyWhisperModel(
        configuration: AppConfiguration,
        environment: [String: String]
    ) -> DependencyReport.Item {
        verifyWhisperModelPresence(
            fileManager: fileManager,
            configuration: configuration,
            environment: environment,
            layout: layout
        )
    }

    private func verifyFFmpeg(
        configuration: AppConfiguration,
        environment: [String: String]
    ) -> DependencyReport.Item {
        let path = configuration.python.ffmpegExecutablePath
        guard fileManager.isExecutableFile(atPath: path) else {
            return DependencyReport.Item(
                name: "ffmpeg",
                available: false,
                status: "missing",
                installStrategy: "Provide a project-local ffmpeg binary at `.openclaw/bin/ffmpeg`.",
                configuredPath: path,
                detail: "ffmpeg is missing."
            )
        }

        let result = runProcess(
            executableURL: URL(fileURLWithPath: path),
            arguments: ["-version"],
            environment: environment,
            currentDirectoryURL: layout.projectRootURL
        )
        return DependencyReport.Item(
            name: "ffmpeg",
            available: result.exitCode == 0,
            status: result.exitCode == 0 ? "ready" : "failed",
            installStrategy: "Provide a runnable project-local ffmpeg binary at `.openclaw/bin/ffmpeg`.",
            configuredPath: path,
            detail: (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func verifyQdrant(
        configuration: AppConfiguration,
        environment: [String: String]
    ) -> DependencyReport.Item {
        let path = configuration.qdrant.binaryPath
        guard fileManager.isExecutableFile(atPath: path) else {
            return DependencyReport.Item(
                name: "qdrant",
                available: false,
                status: "soft-disabled",
                installStrategy: "Provide a project-local qdrant binary at `.openclaw/bin/qdrant`.",
                configuredPath: path,
                detail: "Qdrant is missing."
            )
        }

        let result = runProcess(
            executableURL: URL(fileURLWithPath: path),
            arguments: ["--version"],
            environment: environment,
            currentDirectoryURL: layout.projectRootURL
        )
        return DependencyReport.Item(
            name: "qdrant",
            available: result.exitCode == 0,
            status: result.exitCode == 0 ? "ready" : "soft-disabled",
            installStrategy: "Provide a runnable project-local qdrant binary at `.openclaw/bin/qdrant`.",
            configuredPath: path,
            detail: (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func verifyTDLib(configuration: AppConfiguration) -> DependencyReport.Item {
        let path = configuration.telegram.userTDLibPath
        let exists = fileManager.fileExists(atPath: path)
        return DependencyReport.Item(
            name: "tdlib",
            available: exists,
            status: exists ? "ready" : "soft-disabled",
            installStrategy: "Provide a project-local TDLib dylib at `.openclaw/bin/libtdjson.dylib`.",
            configuredPath: path,
            detail: exists ? "TDLib dylib is present." : "TDLib dylib is missing."
        )
    }

    private func verifyGateway(
        configuration: AppConfiguration,
        environment: [String: String]
    ) -> DependencyReport.Item {
        let entrypointPath = configuration.gateway.entrypointPath
        if fileManager.fileExists(atPath: entrypointPath) {
            return DependencyReport.Item(
                name: "gateway-entrypoint",
                available: true,
                status: "ready",
                installStrategy: "No action required.",
                configuredPath: entrypointPath,
                detail: "OpenClaw gateway entrypoint is present."
            )
        }

        let packagePath = URL(fileURLWithPath: configuration.gateway.repositoryPath, isDirectory: true)
            .appendingPathComponent("package.json").path
        if fileManager.fileExists(atPath: packagePath) {
            let tools = resolveGatewayBuildTools(environment: environment)
            return DependencyReport.Item(
                name: "gateway-entrypoint",
                available: false,
                status: tools == nil ? "source-only" : "build-pending",
                installStrategy: "Build the gateway checkout into `.openclaw/runtime/openclaw-gateway/dist/index.js`.",
                configuredPath: entrypointPath,
                detail: tools == nil
                    ? "Gateway source exists, but Node/package-manager tooling was not found."
                    : "Gateway source exists and can be built when gateway mode is enabled."
            )
        }

        return DependencyReport.Item(
            name: "gateway-entrypoint",
            available: false,
            status: "missing-entrypoint",
            installStrategy: "Provide or bootstrap the OpenClaw gateway checkout under `.openclaw/runtime/openclaw-gateway`.",
            configuredPath: entrypointPath,
            detail: "Gateway source tree is missing or incomplete."
        )
    }

    private func verifyOpenAIKey(configuration: AppConfiguration) -> DependencyReport.Item {
        let selectedModel = configuration.llm.primaryModelRef.lowercased()
        let requiresOpenAIKey = selectedModel.hasPrefix("openai/")
        let hasKey = !configuration.apiKeys.openAI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return DependencyReport.Item(
            name: "openai-api-key",
            available: !requiresOpenAIKey || hasKey,
            status: !requiresOpenAIKey ? "not-required" : (hasKey ? "set" : "missing"),
            installStrategy: "Set the OpenAI API key in the canonical plist-backed settings if you want to use the OpenAI direct chat path.",
            configuredPath: configuration.runtimePaths.canonicalPlistPath,
            detail: requiresOpenAIKey ? (hasKey ? "OpenAI API key is configured." : "OpenAI API key is missing.") : "Selected model does not require an OpenAI key."
        )
    }

}

public struct RuntimeDependencyInstaller {
    public let layout: ProjectRuntimeLayout
    private let fileManager: FileManager

    public init(layout: ProjectRuntimeLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func ensureProjectLocalVenv(configuration: AppConfiguration) throws -> BootstrapDiagnostic? {
        guard !fileManager.isExecutableFile(atPath: configuration.python.executablePath) else {
            log.debug("Project-local venv already exists at \(configuration.python.executablePath).")
            return nil
        }

        guard fileManager.isExecutableFile(atPath: configuration.python.bootstrapExecutablePath) else {
            log.error("Bootstrap Python is unavailable at \(configuration.python.bootstrapExecutablePath).")
            return BootstrapDiagnostic(
                level: .error,
                message: "Bootstrap Python is unavailable at \(configuration.python.bootstrapExecutablePath)."
            )
        }

        log.debug("Creating project-local venv at \(layout.venvDirectoryURL.path).")
        let result = runProcess(
            executableURL: URL(fileURLWithPath: configuration.python.bootstrapExecutablePath),
            arguments: ["-m", "venv", layout.venvDirectoryURL.path],
            environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path
            ],
            currentDirectoryURL: layout.projectRootURL
        )

        if result.exitCode == 0,
           fileManager.isExecutableFile(atPath: configuration.python.executablePath) {
            log.debug("Created project-local Python venv at \(layout.venvDirectoryURL.path).")
            return BootstrapDiagnostic(level: .info, message: "Created project-local Python venv at \(layout.venvDirectoryURL.path).")
        }

        log.error("Failed to create project-local Python venv. \(result.stderr)")
        return BootstrapDiagnostic(
            level: .error,
            message: "Failed to create project-local Python venv at \(layout.venvDirectoryURL.path). \(nonEmptyOutput(stdout: result.stdout, stderr: result.stderr))"
        )
    }

    public func ensureSpeechRequirementsTemplate(configuration: AppConfiguration) throws -> BootstrapDiagnostic? {
        let sourceURL = layout.speechRequirementsTemplateURL
        let destinationURL = URL(fileURLWithPath: configuration.python.speechRequirementsPath)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            log.error("Speech requirements template is missing at \(sourceURL.path).")
            return BootstrapDiagnostic(
                level: .error,
                message: "Speech requirements template is missing at \(sourceURL.path)."
            )
        }

        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sourceData = try Data(contentsOf: sourceURL)
        if let existingData = try? Data(contentsOf: destinationURL), existingData == sourceData {
            log.debug("Speech requirements already up to date at \(destinationURL.path).")
            return nil
        }

        log.debug("Copying speech requirements template to \(destinationURL.path).")
        try sourceData.write(to: destinationURL, options: [.atomic])
        return BootstrapDiagnostic(level: .info, message: "Prepared speech requirements at \(destinationURL.path).")
    }

    public func ensureSpeechPythonPackages(
        configuration: AppConfiguration,
        environment: [String: String]
    ) -> BootstrapDiagnostic? {
        guard fileManager.isExecutableFile(atPath: configuration.python.executablePath) else {
            log.error("Speech package installation skipped because venv Python is missing at \(configuration.python.executablePath).")
            return BootstrapDiagnostic(
                level: .warning,
                message: "Speech package installation skipped because venv Python is missing."
            )
        }

        let verification = verifySpeechImports(configuration: configuration, environment: environment)
        if verification.exitCode == 0 {
            log.debug("Speech Python packages already installed.")
            return BootstrapDiagnostic(level: .info, message: "Speech Python packages are ready.")
        }

        log.debug("Installing speech Python packages from \(configuration.python.speechRequirementsPath).")
        let installResult = runProcess(
            executableURL: URL(fileURLWithPath: configuration.python.executablePath),
            arguments: ["-m", "pip", "install", "-r", configuration.python.speechRequirementsPath],
            environment: environment,
            currentDirectoryURL: layout.projectRootURL
        )
        if installResult.exitCode != 0 {
            log.error("Speech package installation failed. \(installResult.stderr)")
            return BootstrapDiagnostic(
                level: .error,
                message: "Speech package installation failed. \(nonEmptyOutput(stdout: installResult.stdout, stderr: installResult.stderr))"
            )
        }

        let finalVerification = verifySpeechImports(configuration: configuration, environment: environment)
        if finalVerification.exitCode == 0 {
            log.debug("Speech Python packages installed successfully.")
            return BootstrapDiagnostic(level: .info, message: "Installed speech Python packages into `.openclaw/venv`.")
        }

        log.error("Speech package installation completed but imports still fail. \(finalVerification.stderr)")
        return BootstrapDiagnostic(
            level: .error,
            message: "Speech package installation completed, but import verification still failed. \(nonEmptyOutput(stdout: finalVerification.stdout, stderr: finalVerification.stderr))"
        )
    }

    public func ensureWhisperModel(
        configuration: AppConfiguration,
        environment: [String: String]
    ) -> BootstrapDiagnostic? {
        let verification = verifyWhisperModelPresence(
            fileManager: fileManager,
            configuration: configuration,
            environment: environment,
            layout: layout
        )
        if verification.available {
            log.debug("Whisper model \(configuration.whisper.modelIdentifier) is already available.")
            return BootstrapDiagnostic(level: .info, message: "Whisper model \(configuration.whisper.modelIdentifier) is ready.")
        }

        guard verifySpeechImports(configuration: configuration, environment: environment).exitCode == 0 else {
            log.error("Whisper model download skipped because speech Python packages are unavailable.")
            return BootstrapDiagnostic(
                level: .warning,
                message: "Whisper model download skipped because speech Python packages are unavailable."
            )
        }

        let modelDirectory = URL(fileURLWithPath: configuration.whisper.modelDirectoryPath, isDirectory: true)
        do {
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        } catch {
            log.error("Failed to prepare Whisper model directory. \(error.localizedDescription)")
            return BootstrapDiagnostic(
                level: .error,
                message: "Failed to prepare Whisper model directory at \(modelDirectory.path): \(error.localizedDescription)"
            )
        }

        var modelEnvironment = environment
        modelEnvironment["HF_HOME"] = modelDirectory.path
        modelEnvironment["HUGGINGFACE_HUB_CACHE"] = modelDirectory.appendingPathComponent("hub", isDirectory: true).path
        modelEnvironment["XDG_CACHE_HOME"] = modelDirectory.deletingLastPathComponent().path
        modelEnvironment["CT2_CUDA_ALLOW_FP16"] = "0"

        let script = """
from faster_whisper import WhisperModel
WhisperModel(\(pythonLiteral(configuration.whisper.modelIdentifier)), device="cpu", compute_type="int8", cpu_threads=1, num_workers=1, download_root=\(pythonLiteral(configuration.whisper.modelDirectoryPath)))
print("whisper-model-ok")
"""
        log.debug("Preparing Whisper model \(configuration.whisper.modelIdentifier) in \(configuration.whisper.modelDirectoryPath).")
        let result = runProcess(
            executableURL: URL(fileURLWithPath: configuration.python.executablePath),
            arguments: ["-c", script],
            environment: modelEnvironment,
            currentDirectoryURL: layout.projectRootURL
        )
        if result.exitCode != 0 {
            log.error("Whisper model preparation failed. \(result.stderr)")
            return BootstrapDiagnostic(
                level: .error,
                message: "Whisper model preparation failed. \(nonEmptyOutput(stdout: result.stdout, stderr: result.stderr))"
            )
        }

        let finalVerification = verifyWhisperModelPresence(
            fileManager: fileManager,
            configuration: configuration,
            environment: environment,
            layout: layout
        )
        if finalVerification.available {
            log.debug("Whisper model \(configuration.whisper.modelIdentifier) is ready after bootstrap.")
            return BootstrapDiagnostic(level: .info, message: "Prepared Whisper model \(configuration.whisper.modelIdentifier).")
        }

        log.error("Whisper model bootstrap completed but artifacts are still missing.")
        return BootstrapDiagnostic(
            level: .error,
            message: "Whisper model bootstrap completed, but validation still failed."
        )
    }

    public func ensureGatewayBuildIfEnabled(
        configuration: AppConfiguration,
        environment: [String: String]
    ) -> BootstrapDiagnostic? {
        guard configuration.gateway.enabled || configuration.llm.gatewayEnabled else {
            return nil
        }

        let repositoryURL = URL(fileURLWithPath: configuration.gateway.repositoryPath, isDirectory: true)
        let packageURL = repositoryURL.appendingPathComponent("package.json")
        let entrypointURL = URL(fileURLWithPath: configuration.gateway.entrypointPath)

        guard fileManager.fileExists(atPath: packageURL.path) else {
            return BootstrapDiagnostic(
                level: .warning,
                message: "Gateway source tree is missing at \(repositoryURL.path)."
            )
        }

        guard !fileManager.fileExists(atPath: entrypointURL.path) else {
            return BootstrapDiagnostic(level: .info, message: "Gateway build output is ready.")
        }

        guard let tools = resolveGatewayBuildTools(environment: environment) else {
            return BootstrapDiagnostic(
                level: .warning,
                message: "Gateway source exists, but Node or package-manager tooling was not found. Gateway mode remains disabled."
            )
        }

        log.debug("Building gateway with \(tools.displayName) in \(repositoryURL.path).")
        let installResult = runProcess(
            executableURL: tools.executableURL,
            arguments: tools.installArguments,
            environment: environment,
            currentDirectoryURL: repositoryURL
        )
        if installResult.exitCode != 0 {
            log.error("Gateway dependency install failed. \(installResult.stderr)")
            return BootstrapDiagnostic(
                level: .warning,
                message: "Gateway dependency install failed. \(nonEmptyOutput(stdout: installResult.stdout, stderr: installResult.stderr))"
            )
        }

        let buildResult = runProcess(
            executableURL: tools.executableURL,
            arguments: tools.buildArguments,
            environment: environment,
            currentDirectoryURL: repositoryURL
        )
        if buildResult.exitCode != 0 {
            log.error("Gateway build failed. \(buildResult.stderr)")
            return BootstrapDiagnostic(
                level: .warning,
                message: "Gateway build failed. \(nonEmptyOutput(stdout: buildResult.stdout, stderr: buildResult.stderr))"
            )
        }

        if fileManager.fileExists(atPath: entrypointURL.path) {
            log.debug("Gateway build completed successfully.")
            return BootstrapDiagnostic(level: .info, message: "Built OpenClaw gateway entrypoint.")
        }

        log.error("Gateway build completed but dist/index.js is still missing.")
        return BootstrapDiagnostic(
            level: .warning,
            message: "Gateway build completed, but `dist/index.js` is still missing."
        )
    }

    private func verifySpeechImports(
        configuration: AppConfiguration,
        environment: [String: String]
    ) -> ProcessResult {
        let script = """
import importlib.util
import sys
modules = ["faster_whisper", "ctranslate2", "numpy", "tokenizers", "huggingface_hub"]
missing = [name for name in modules if importlib.util.find_spec(name) is None]
if missing:
    print(",".join(missing))
    raise SystemExit(1)
print("speech-stack-ok")
"""
        return runProcess(
            executableURL: URL(fileURLWithPath: configuration.python.executablePath),
            arguments: ["-c", script],
            environment: environment,
            currentDirectoryURL: layout.projectRootURL
        )
    }
}

public final class AppBootstrapper: @unchecked Sendable {
    public struct Result: Equatable, Sendable {
        public let configuration: AppConfiguration
        public let diagnostics: BootstrapDiagnostics
        public let dependencyReport: DependencyReport
    }

    private let layout: ProjectRuntimeLayout
    private let store: AppConfigurationStore
    private let verifier: DependencyVerifier
    private let installer: RuntimeDependencyInstaller
    private let fileManager: FileManager

    public init(
        layout: ProjectRuntimeLayout,
        store: AppConfigurationStore,
        verifier: DependencyVerifier,
        installer: RuntimeDependencyInstaller,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.store = store
        self.verifier = verifier
        self.installer = installer
        self.fileManager = fileManager
    }

    @discardableResult
    public func bootstrapFoundation() throws -> AppConfiguration {
        let configuration = try store.loadOrCreate()
        try store.createManagedDirectoriesIfNeeded()
        try seedWorkspaceTemplatesIfNeeded()
        _ = try installer.ensureProjectLocalVenv(configuration: configuration)
        _ = try installer.ensureSpeechRequirementsTemplate(configuration: try store.loadOrCreate())
        return try store.loadOrCreate()
    }

    public func bootstrap() throws -> Result {
        var diagnostics = BootstrapDiagnostics(status: .bootstrapping)
        log.debug("Starting bootstrap using canonical configuration at \(layout.configurationFileURL.path).")

        let baseConfiguration = try bootstrapFoundation()
        diagnostics.messages.append(.init(level: .info, message: "Loaded canonical configuration from \(layout.configurationFileURL.path)."))
        diagnostics.messages.append(.init(level: .info, message: "Prepared runtime directory layout at \(layout.runtimeRootURL.path)."))
        diagnostics.messages.append(.init(level: .info, message: "Ensured workspace templates exist under \(layout.workspaceDirectoryURL.path)."))

        let configuration = try store.loadOrCreate()
        let environment = AppConfigurationEnvironmentBuilder.build(configuration: configuration, layout: layout)
        log.debug("Built bootstrap environment from canonical plist at \(configuration.runtimePaths.canonicalPlistPath).")

        if let requirementsDiagnostic = try installer.ensureSpeechRequirementsTemplate(configuration: configuration) {
            diagnostics.messages.append(requirementsDiagnostic)
        }
        if let packagesDiagnostic = installer.ensureSpeechPythonPackages(configuration: configuration, environment: environment) {
            diagnostics.messages.append(packagesDiagnostic)
        }
        if configuration.voice.speechRecognitionBackend == "whisper" {
            if let whisperDiagnostic = installer.ensureWhisperModel(configuration: configuration, environment: environment) {
                diagnostics.messages.append(whisperDiagnostic)
            }
        }
        if let gatewayDiagnostic = installer.ensureGatewayBuildIfEnabled(configuration: configuration, environment: environment) {
            diagnostics.messages.append(gatewayDiagnostic)
        }

        let dependencyReport = verifier.verify(configuration: try store.loadOrCreate())
        if dependencyReport.items.allSatisfy(\.available) {
            diagnostics.status = .ready
        } else if dependencyReport.missingCriticalItems.isEmpty {
            diagnostics.status = .degraded
        } else {
            diagnostics.status = .degraded
        }

        for item in dependencyReport.items where !item.available {
            diagnostics.messages.append(
                .init(level: item.isBlocking ? .error : .warning, message: "\(item.name): \(item.detail.isEmpty ? item.installStrategy : item.detail)")
            )
        }

        let finalConfiguration = try store.loadOrCreate()
        log.debug("Bootstrap finished with status \(diagnostics.status).")
        _ = baseConfiguration
        return Result(
            configuration: finalConfiguration,
            diagnostics: diagnostics,
            dependencyReport: dependencyReport
        )
    }

    private func seedWorkspaceTemplatesIfNeeded() throws {
        let templates = [
            "AGENTS.md",
            "BOOTSTRAP.md",
            "HEARTBEAT.md",
            "IDENTITY.md",
            "MEMORY.md",
            "SOUL.md",
            "TOOLS.md",
            "USER.md",
            "persona_compact.md"
        ]

        for fileName in templates {
            let sourceURL = layout.workspaceTemplatesDirectoryURL.appendingPathComponent(fileName)
            let destinationURL = layout.workspaceDirectoryURL.appendingPathComponent(fileName)
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                continue
            }
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: destinationURL, options: [.atomic])
        }
    }
}

private struct GatewayBuildTools {
    let executableURL: URL
    let displayName: String
    let installArguments: [String]
    let buildArguments: [String]
}

private func verifyWhisperModelPresence(
    fileManager: FileManager,
    configuration: AppConfiguration,
    environment: [String: String],
    layout: ProjectRuntimeLayout
) -> DependencyReport.Item {
    let modelDirectory = URL(fileURLWithPath: configuration.whisper.modelDirectoryPath, isDirectory: true)
    let hasMaterializedFiles = containsWhisperModelArtifacts(fileManager: fileManager, in: modelDirectory)
    guard hasMaterializedFiles else {
        return DependencyReport.Item(
            name: "whisper-model",
            available: false,
            status: "missing",
            installStrategy: "Download the configured Whisper model into `.openclaw/models/whisper` using the project-local venv.",
            configuredPath: configuration.whisper.modelDirectoryPath,
            detail: "No materialized Whisper model artifacts were found for \(configuration.whisper.modelIdentifier)."
        )
    }

    guard fileManager.isExecutableFile(atPath: configuration.python.executablePath) else {
        return DependencyReport.Item(
            name: "whisper-model",
            available: false,
            status: "missing",
            installStrategy: "Create the project-local venv before validating the Whisper model.",
            configuredPath: configuration.whisper.modelDirectoryPath,
            detail: "Whisper model files exist, but Python validation could not run because the venv is missing."
        )
    }

    let validationScript = """
from faster_whisper import WhisperModel
WhisperModel(\(pythonLiteral(configuration.whisper.modelIdentifier)), device="cpu", compute_type="int8", cpu_threads=1, num_workers=1, download_root=\(pythonLiteral(configuration.whisper.modelDirectoryPath)))
print("whisper-model-ok")
"""
    var offlineEnvironment = environment
    offlineEnvironment["HF_HUB_OFFLINE"] = "1"
    offlineEnvironment["TRANSFORMERS_OFFLINE"] = "1"
    offlineEnvironment["HF_HOME"] = configuration.whisper.modelDirectoryPath
    offlineEnvironment["HUGGINGFACE_HUB_CACHE"] = URL(fileURLWithPath: configuration.whisper.modelDirectoryPath, isDirectory: true)
        .appendingPathComponent("hub", isDirectory: true).path
    offlineEnvironment["XDG_CACHE_HOME"] = URL(fileURLWithPath: configuration.whisper.modelDirectoryPath, isDirectory: true)
        .deletingLastPathComponent().path

    let result = runProcess(
        executableURL: URL(fileURLWithPath: configuration.python.executablePath),
        arguments: ["-c", validationScript],
        environment: offlineEnvironment,
        currentDirectoryURL: layout.projectRootURL
    )
    return DependencyReport.Item(
        name: "whisper-model",
        available: result.exitCode == 0,
        status: result.exitCode == 0 ? "ready" : "missing",
        installStrategy: "Re-download the configured Whisper model into `.openclaw/models/whisper` if validation fails.",
        configuredPath: configuration.whisper.modelDirectoryPath,
        detail: (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

private func containsWhisperModelArtifacts(fileManager: FileManager, in directory: URL) -> Bool {
    guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
        return false
    }

    var foundConfig = false
    var foundWeights = false
    for case let fileURL as URL in enumerator {
        let name = fileURL.lastPathComponent
        if name == "config.json" {
            foundConfig = true
        }
        if name == "model.bin" || name == "model.bin.index.json" {
            foundWeights = true
        }
        if foundConfig && foundWeights {
            return true
        }
    }

    return false
}

private func resolveGatewayBuildTools(environment: [String: String]) -> GatewayBuildTools? {
    let fileManager = FileManager.default
    let pnpmCandidates = [
        environment["GRACULA_PNPM_EXECUTABLE"],
        "/opt/homebrew/bin/pnpm",
        "/usr/local/bin/pnpm",
        "/usr/bin/pnpm"
    ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

    for candidate in pnpmCandidates {
        let url = URL(fileURLWithPath: candidate)
        if fileManager.isExecutableFile(atPath: url.path) {
            return GatewayBuildTools(
                executableURL: url,
                displayName: "pnpm",
                installArguments: ["install", "--frozen-lockfile"],
                buildArguments: ["build"]
            )
        }
    }

    let corepackCandidates = [
        "/opt/homebrew/bin/corepack",
        "/usr/local/bin/corepack",
        "/usr/bin/corepack"
    ]
    for candidate in corepackCandidates {
        let url = URL(fileURLWithPath: candidate)
        if fileManager.isExecutableFile(atPath: url.path) {
            return GatewayBuildTools(
                executableURL: url,
                displayName: "corepack pnpm",
                installArguments: ["pnpm", "install", "--frozen-lockfile"],
                buildArguments: ["pnpm", "build"]
            )
        }
    }

    return nil
}

private func runProcess(
    executableURL: URL,
    arguments: [String],
    environment: [String: String],
    currentDirectoryURL: URL
) -> ProcessResult {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = currentDirectoryURL
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
        process.waitUntilExit()
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(stdout: stdoutText, stderr: stderrText, exitCode: process.terminationStatus)
    } catch {
        return ProcessResult(stdout: "", stderr: error.localizedDescription, exitCode: 1)
    }
}

private func nonEmptyOutput(stdout: String, stderr: String) -> String {
    let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedStderr.isEmpty {
        return trimmedStderr
    }
    let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedStdout.isEmpty ? "No command output captured." : trimmedStdout
}

private func pythonLiteral(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}
