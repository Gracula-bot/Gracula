import Foundation

public final class AppConfigurationStore: @unchecked Sendable {
    public enum ConfigurationError: LocalizedError {
        case invalidConfiguration(String)

        public var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message):
                return message
            }
        }
    }

    public let layout: ProjectRuntimeLayout
    private let fileManager: FileManager
    private let encoder: PropertyListEncoder
    private let decoder: PropertyListDecoder

    public init(layout: ProjectRuntimeLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
        self.encoder = PropertyListEncoder()
        self.encoder.outputFormat = .xml
        self.decoder = PropertyListDecoder()
    }

    public func load() throws -> AppConfiguration {
        try loadWithRepairStatus().configuration
    }

    @discardableResult
    public func loadOrCreate() throws -> AppConfiguration {
        try createManagedDirectoriesIfNeeded()
        try migrateCanonicalPlistIfNeeded()
        if !fileManager.fileExists(atPath: layout.configurationFileURL.path) {
            let configuration = try configurationFromTemplateIfAvailable() ?? AppConfigurationDefaults.make(layout: layout)
            try save(configuration)
            return configuration
        }

        let loadResult = try loadWithRepairStatus()
        let configuration = loadResult.configuration
        let normalized = try normalizedConfiguration(from: configuration)
        if loadResult.repaired || normalized != configuration {
            try save(normalized)
        }
        return normalized
    }

    private func loadWithRepairStatus() throws -> (configuration: AppConfiguration, repaired: Bool) {
        let data = try Data(contentsOf: layout.configurationFileURL)
        do {
            return (try decoder.decode(AppConfiguration.self, from: data), false)
        } catch {
            let repaired = try repairConfigurationDataIfPossible(data)
            return (try decoder.decode(AppConfiguration.self, from: repaired), true)
        }
    }

    @discardableResult
    public func update(_ mutate: (inout AppConfiguration) throws -> Void) throws -> AppConfiguration {
        var configuration = try loadOrCreate()
        try mutate(&configuration)
        let normalized = try normalizedConfiguration(from: configuration)
        try save(normalized)
        return normalized
    }

    public func save(_ configuration: AppConfiguration) throws {
        try createManagedDirectoriesIfNeeded()
        let data = try encoder.encode(configuration)
        try data.write(to: layout.configurationFileURL, options: [.atomic])
    }

    public func createManagedDirectoriesIfNeeded() throws {
        for directory in layout.managedDirectories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func normalizedConfiguration(from configuration: AppConfiguration) throws -> AppConfiguration {
        var normalized = configuration
        normalized.runtimePaths.projectRootPath = layout.projectRootURL.path
        normalized.runtimePaths.runtimeRootPath = layout.runtimeRootURL.path
        normalized.runtimePaths.canonicalPlistPath = layout.configurationFileURL.path
        normalized.runtimePaths.binPath = layout.binDirectoryURL.path
        normalized.runtimePaths.workspacePath = layout.workspaceDirectoryURL.path
        normalized.runtimePaths.logsPath = layout.logsDirectoryURL.path
        normalized.runtimePaths.modelCachePath = layout.modelsDirectoryURL.path
        normalized.runtimePaths.downloadsPath = layout.downloadsDirectoryURL.path
        normalized.runtimePaths.recoveryPath = layout.recoveryDirectoryURL.path

        normalized.python.executablePath = layout.pythonExecutableURL.path
        normalized.python.pipExecutablePath = layout.pipExecutableURL.path
        normalized.python.venvPath = layout.venvDirectoryURL.path
        normalized.python.speechRequirementsPath = layout.speechRequirementsURL.path
        normalized.whisper.modelDirectoryPath = layout.modelsDirectoryURL.appendingPathComponent("whisper", isDirectory: true).path
        normalized.whisper.workerScriptPath = layout.pythonDirectoryURL.appendingPathComponent("faster-whisper-worker.py").path
        normalized.qdrant.binaryPath = layout.qdrantBinaryURL.path
        normalized.qdrant.storagePath = layout.qdrantStorageDirectoryURL.path
        normalized.gateway.repositoryPath = layout.openClawGatewayRootURL.path
        normalized.gateway.entrypointPath = layout.openClawGatewayEntrypointURL.path

        if normalized.llm.primaryModelRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.llm.primaryModelRef = AppConfigurationDefaults.make(layout: layout).llm.primaryModelRef
        }
        if normalized.qdrant.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.qdrant.baseURL = AppConfigurationDefaults.make(layout: layout).qdrant.baseURL
        }
        if normalized.llm.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.llm.openAIBaseURL = AppConfigurationDefaults.make(layout: layout).llm.openAIBaseURL
        }
        if normalized.tracing.logLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.tracing.logLevel = AppConfigurationDefaults.make(layout: layout).tracing.logLevel
        }
        return normalized
    }

    private func repairConfigurationDataIfPossible(_ data: Data) throws -> Data {
        let defaultsData = try encoder.encode(AppConfigurationDefaults.make(layout: layout))
        guard
            let defaultsObject = try PropertyListSerialization.propertyList(from: defaultsData, options: [], format: nil) as? [String: Any],
            let existingObject = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            throw ConfigurationError.invalidConfiguration("Canonical plist is unreadable and could not be repaired.")
        }

        let mergedObject = merge(defaults: defaultsObject, existing: existingObject)
        return try PropertyListSerialization.data(fromPropertyList: mergedObject, format: .xml, options: 0)
    }

    private func merge(defaults: [String: Any], existing: [String: Any]) -> [String: Any] {
        var result = defaults
        for (key, value) in existing {
            if let defaultDictionary = defaults[key] as? [String: Any],
               let existingDictionary = value as? [String: Any] {
                result[key] = merge(defaults: defaultDictionary, existing: existingDictionary)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private func migrateCanonicalPlistIfNeeded() throws {
        guard !fileManager.fileExists(atPath: layout.configurationFileURL.path) else {
            return
        }

        let legacyURL = layout.legacyConfigurationFileURL
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        try fileManager.createDirectory(at: layout.configDirectoryURL, withIntermediateDirectories: true)
        try fileManager.moveItem(at: legacyURL, to: layout.configurationFileURL)
    }

    private func configurationFromTemplateIfAvailable() throws -> AppConfiguration? {
        guard fileManager.fileExists(atPath: layout.configurationTemplateFileURL.path) else {
            return nil
        }

        let templateData = try Data(contentsOf: layout.configurationTemplateFileURL)
        let repaired = try repairConfigurationDataIfPossible(templateData)
        return try decoder.decode(AppConfiguration.self, from: repaired)
    }
}
