import Foundation

public struct ProjectRuntimeLayout: Sendable, Equatable {
    public let projectRootURL: URL
    public let runtimeRootURL: URL
    public let configDirectoryURL: URL
    public let configurationFileURL: URL
    public let binDirectoryURL: URL
    public let runtimeDirectoryURL: URL
    public let pythonDirectoryURL: URL
    public let venvDirectoryURL: URL
    public let modelsDirectoryURL: URL
    public let workspaceDirectoryURL: URL
    public let logsDirectoryURL: URL
    public let cacheDirectoryURL: URL
    public let qdrantDirectoryURL: URL
    public let downloadsDirectoryURL: URL
    public let recoveryDirectoryURL: URL
    public let workspaceTemplatesDirectoryURL: URL
    public let runtimeTemplatesDirectoryURL: URL

    public init(projectRootURL: URL) {
        let normalizedProjectRoot = projectRootURL.standardizedFileURL
        let runtimeRootURL = normalizedProjectRoot.appendingPathComponent(".openclaw", isDirectory: true)
        let visibleConfigRootURL = normalizedProjectRoot.appendingPathComponent("ConfigFiles", isDirectory: true)

        self.projectRootURL = normalizedProjectRoot
        self.runtimeRootURL = runtimeRootURL
        self.configDirectoryURL = visibleConfigRootURL
        self.configurationFileURL = configDirectoryURL.appendingPathComponent("AppConfiguration.plist")
        self.binDirectoryURL = runtimeRootURL.appendingPathComponent("bin", isDirectory: true)
        self.runtimeDirectoryURL = runtimeRootURL.appendingPathComponent("runtime", isDirectory: true)
        self.pythonDirectoryURL = runtimeRootURL.appendingPathComponent("python", isDirectory: true)
        self.venvDirectoryURL = runtimeRootURL.appendingPathComponent("venv", isDirectory: true)
        self.modelsDirectoryURL = runtimeRootURL.appendingPathComponent("models", isDirectory: true)
        self.workspaceDirectoryURL = runtimeRootURL.appendingPathComponent("workspace", isDirectory: true)
        self.logsDirectoryURL = runtimeRootURL.appendingPathComponent("logs", isDirectory: true)
        self.cacheDirectoryURL = runtimeRootURL.appendingPathComponent("cache", isDirectory: true)
        self.qdrantDirectoryURL = runtimeRootURL.appendingPathComponent("qdrant", isDirectory: true)
        self.downloadsDirectoryURL = runtimeRootURL.appendingPathComponent("downloads", isDirectory: true)
        self.recoveryDirectoryURL = runtimeRootURL.appendingPathComponent("recovery", isDirectory: true)
        self.workspaceTemplatesDirectoryURL = normalizedProjectRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("WorkspaceTemplates", isDirectory: true)
        self.runtimeTemplatesDirectoryURL = normalizedProjectRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("RuntimeTemplates", isDirectory: true)
    }

    public static func resolveDefault(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sourceFilePath: String = #filePath
    ) -> ProjectRuntimeLayout {
        if let override = environment["GRACULA_PROJECT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return ProjectRuntimeLayout(projectRootURL: URL(fileURLWithPath: override, isDirectory: true))
        }

        let sourceURL = URL(fileURLWithPath: sourceFilePath, isDirectory: false)
        var candidate = sourceURL.deletingLastPathComponent()
        while candidate.path != "/" {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path),
               fileManager.fileExists(atPath: candidate.appendingPathComponent("Examples", isDirectory: true).path) {
                return ProjectRuntimeLayout(projectRootURL: candidate)
            }
            candidate = candidate.deletingLastPathComponent()
        }

        return ProjectRuntimeLayout(projectRootURL: URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true))
    }

    public var managedDirectories: [URL] {
        [
            runtimeRootURL,
            configDirectoryURL,
            binDirectoryURL,
            runtimeDirectoryURL,
            pythonDirectoryURL,
            venvDirectoryURL,
            modelsDirectoryURL,
            workspaceDirectoryURL,
            logsDirectoryURL,
            cacheDirectoryURL,
            qdrantDirectoryURL,
            downloadsDirectoryURL,
            recoveryDirectoryURL
        ]
    }

    public var qdrantStorageDirectoryURL: URL {
        qdrantDirectoryURL.appendingPathComponent("storage", isDirectory: true)
    }

    public var qdrantBinaryURL: URL {
        binDirectoryURL.appendingPathComponent("qdrant")
    }

    public var nodeBinaryURL: URL {
        binDirectoryURL.appendingPathComponent("node")
    }

    public var pnpmBinaryURL: URL {
        binDirectoryURL.appendingPathComponent("pnpm")
    }

    public var pythonExecutableURL: URL {
        venvDirectoryURL.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("python")
    }

    public var pipExecutableURL: URL {
        venvDirectoryURL.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("pip")
    }

    public var ffmpegExecutableURL: URL {
        binDirectoryURL.appendingPathComponent("ffmpeg")
    }

    public var speechRequirementsTemplateURL: URL {
        runtimeTemplatesDirectoryURL.appendingPathComponent("requirements-speech.txt")
    }

    public var configurationTemplateFileURL: URL {
        configDirectoryURL.appendingPathComponent("AppConfiguration.example.plist")
    }

    public var legacyConfigurationFileURL: URL {
        runtimeDirectoryURL.appendingPathComponent("AppConfiguration.plist")
    }

    public var speechRequirementsURL: URL {
        pythonDirectoryURL.appendingPathComponent("requirements-speech.txt")
    }

    public var openClawConfigFileURL: URL {
        runtimeRootURL.appendingPathComponent("openclaw.json")
    }

    public var openClawGatewayRootURL: URL {
        runtimeDirectoryURL.appendingPathComponent("openclaw-gateway", isDirectory: true)
    }

    public var openClawGatewayEntrypointURL: URL {
        openClawGatewayRootURL.appendingPathComponent("dist", isDirectory: true).appendingPathComponent("index.js")
    }
}
