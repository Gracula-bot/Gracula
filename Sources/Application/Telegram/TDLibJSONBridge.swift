import Darwin
import Foundation

public protocol TDLibJSONBridge: Sendable {
    func createClientId() -> Int32
    func send(clientId: Int32, request: [String: Any]) throws
    func receive(timeout: Double) -> [String: Any]?
    func execute(_ request: [String: Any]) throws -> [String: Any]?
}

public enum TDLibJSONBridgeError: Error, Sendable, Equatable, LocalizedError {
    case libraryNotFound([String])
    case missingSymbol(String)
    case invalidJSON
    case invalidRequest

    public var errorDescription: String? {
        switch self {
        case .libraryNotFound(let paths):
            "TDLib JSON library was not found. Checked: \(paths.joined(separator: ", "))"
        case .missingSymbol(let symbol):
            "TDLib JSON library is missing symbol \(symbol)."
        case .invalidJSON:
            "TDLib returned invalid JSON."
        case .invalidRequest:
            "Could not encode TDLib request JSON."
        }
    }
}

public final class DynamicTDLibJSONBridge: TDLibJSONBridge, @unchecked Sendable {
    public typealias CreateClientId = @convention(c) () -> Int32
    public typealias Send = @convention(c) (Int32, UnsafePointer<CChar>) -> Void
    public typealias Receive = @convention(c) (Double) -> UnsafePointer<CChar>?
    public typealias Execute = @convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?

    public let loadedLibraryPath: String

    private let handle: UnsafeMutableRawPointer
    private let tdCreateClientId: CreateClientId
    private let tdSend: Send
    private let tdReceive: Receive
    private let tdExecute: Execute

    public init(libraryPath: String? = nil) throws {
        let candidates = Self.candidateLibraryPaths(explicitPath: libraryPath)
        guard let opened = candidates.lazy.compactMap({ path -> (String, UnsafeMutableRawPointer)? in
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
                return nil
            }
            return (path, handle)
        }).first else {
            throw TDLibJSONBridgeError.libraryNotFound(candidates)
        }

        self.loadedLibraryPath = opened.0
        self.handle = opened.1
        self.tdCreateClientId = try Self.symbol(opened.1, "td_create_client_id")
        self.tdSend = try Self.symbol(opened.1, "td_send")
        self.tdReceive = try Self.symbol(opened.1, "td_receive")
        self.tdExecute = try Self.symbol(opened.1, "td_execute")
    }

    deinit {
        dlclose(handle)
    }

    public static func candidateLibraryPaths(explicitPath: String?) -> [String] {
        var paths: [String] = []
        if let explicitPath = explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitPath.isEmpty {
            paths.append(explicitPath)
        }
        paths.append(contentsOf: [
            "/opt/homebrew/lib/libtdjson.dylib",
            "/usr/local/lib/libtdjson.dylib",
            "/usr/lib/libtdjson.dylib",
            "libtdjson.dylib"
        ])
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    public func createClientId() -> Int32 {
        tdCreateClientId()
    }

    public func send(clientId: Int32, request: [String: Any]) throws {
        let text = try encode(request)
        text.withCString { pointer in
            tdSend(clientId, pointer)
        }
    }

    public func receive(timeout: Double) -> [String: Any]? {
        guard let pointer = tdReceive(timeout) else {
            return nil
        }
        return try? decode(String(cString: pointer))
    }

    public func execute(_ request: [String: Any]) throws -> [String: Any]? {
        let text = try encode(request)
        return try text.withCString { pointer -> [String: Any]? in
            guard let response = tdExecute(pointer) else {
                return nil
            }
            return try decode(String(cString: response))
        }
    }

    private func encode(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            throw TDLibJSONBridgeError.invalidRequest
        }
        return text
    }

    private func decode(_ text: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TDLibJSONBridgeError.invalidJSON
        }
        return object
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws -> T {
        guard let raw = dlsym(handle, name) else {
            throw TDLibJSONBridgeError.missingSymbol(name)
        }
        return unsafeBitCast(raw, to: T.self)
    }
}
