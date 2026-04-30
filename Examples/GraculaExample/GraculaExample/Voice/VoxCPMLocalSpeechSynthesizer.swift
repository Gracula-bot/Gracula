import Foundation

struct LocalVoxCPMSpeechRuntimeConfiguration: Sendable {
    let pythonURL: URL
    let modelDirectoryURL: URL
    let modelSource: String
    let workerScriptURL: URL
    let device: String
    let loadDenoiser: Bool
    let cfgValue: Double
    let inferenceTimesteps: Int

    static func `default`(
        modelName: String? = nil,
        device: String = "cpu"
    ) throws -> LocalVoxCPMSpeechRuntimeConfiguration {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment

        let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GraculaExample", isDirectory: true)

        let pythonCandidates: [URL] = [
            environment["GRACULA_VOXCPM_PYTHON"].map { URL(fileURLWithPath: $0) },
            environment["GRACULA_WHISPER_PYTHON"].map { URL(fileURLWithPath: $0) },
            applicationSupportDirectory
                .appendingPathComponent("PythonRuntime", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("python"),
            Self.exampleDirectoryPythonURL(
                in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            ),
            Self.examplePythonURL(
                in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            ),
            Self.examplePythonURL(
                in: homeDirectory
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Gracula", isDirectory: true)
            ),
            Self.examplePythonURL(
                in: homeDirectory.appendingPathComponent("Gracula", isDirectory: true)
            ),
            Self.examplePythonURL(
                in: homeDirectory
                    .appendingPathComponent("Code", isDirectory: true)
                    .appendingPathComponent("Gracula", isDirectory: true)
            )
        ]
        .compactMap { $0 }

        guard let pythonURL = pythonCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw VoiceSynthesisError.invalidConfiguration(
                "Python runtime not found. Expected `GRACULA_VOXCPM_PYTHON`, `GRACULA_WHISPER_PYTHON`, or `Examples/GraculaExample/.whisper-venv/bin/python` under the Gracula checkout."
            )
        }

        let modelDirectoryURL = applicationSupportDirectory.appendingPathComponent("VoxCPMModels", isDirectory: true)
        let workerScriptURL = applicationSupportDirectory.appendingPathComponent("voxcpm-worker.py")
        let resolvedModelSource = try Self.resolveModelSource(
            fileManager: fileManager,
            modelDirectoryURL: modelDirectoryURL,
            requestedModelName: modelName ?? "openbmb/VoxCPM2"
        )

        try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        try VoxCPMLocalWorkerScript.writeIfNeeded(to: workerScriptURL)

        return LocalVoxCPMSpeechRuntimeConfiguration(
            pythonURL: pythonURL,
            modelDirectoryURL: modelDirectoryURL,
            modelSource: resolvedModelSource,
            workerScriptURL: workerScriptURL,
            device: device,
            loadDenoiser: false,
            cfgValue: 2.0,
            inferenceTimesteps: 10
        )
    }

    private static func resolveModelSource(
        fileManager: FileManager,
        modelDirectoryURL: URL,
        requestedModelName: String
    ) throws -> String {
        let modelID = requestedModelName
            .replacingOccurrences(of: "/", with: "--")
            .replacingOccurrences(of: " ", with: "-")

        let snapshotRoot = modelDirectoryURL
            .appendingPathComponent("models--\(modelID)", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)

        if let snapshotPath = try latestSnapshotDirectory(in: snapshotRoot, fileManager: fileManager) {
            return snapshotPath.path
        }

        return requestedModelName
    }

    private static func latestSnapshotDirectory(in snapshotRoot: URL, fileManager: FileManager) throws -> URL? {
        guard fileManager.fileExists(atPath: snapshotRoot.path) else {
            return nil
        }

        let snapshotURLs = try fileManager.contentsOfDirectory(
            at: snapshotRoot,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return snapshotURLs
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted {
                let leftValues = try? $0.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let rightValues = try? $1.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])

                let leftDate = leftValues?.creationDate ?? leftValues?.contentModificationDate ?? .distantPast
                let rightDate = rightValues?.creationDate ?? rightValues?.contentModificationDate ?? .distantPast
                return leftDate > rightDate
            }
            .first
    }

    private static func examplePythonURL(in repositoryRoot: URL) -> URL {
        repositoryRoot
            .appendingPathComponent("Examples", isDirectory: true)
            .appendingPathComponent("GraculaExample", isDirectory: true)
            .appendingPathComponent(".whisper-venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    private static func exampleDirectoryPythonURL(in exampleDirectory: URL) -> URL {
        exampleDirectory
            .appendingPathComponent(".whisper-venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }
}

final class VoxCPMLocalSpeechSynthesizer: SpeechSynthesizing, @unchecked Sendable {
    private var runtimeResult: Result<LocalVoxCPMSpeechRuntimeConfiguration, Error>
    private var worker: VoxCPMTextToSpeechWorker?

    init(runtime: LocalVoxCPMSpeechRuntimeConfiguration? = nil) {
        if let runtime {
            self.runtimeResult = .success(runtime)
            self.worker = VoxCPMTextToSpeechWorker(runtime: runtime)
            return
        }

        do {
            let runtime = try LocalVoxCPMSpeechRuntimeConfiguration.default()
            self.runtimeResult = .success(runtime)
            self.worker = VoxCPMTextToSpeechWorker(runtime: runtime)
        } catch {
            self.runtimeResult = .failure(error)
            self.worker = nil
        }
    }

    convenience init(settings: VoicePipelineSettings) {
        do {
            let runtime = try LocalVoxCPMSpeechRuntimeConfiguration.default(
                modelName: settings.voxcpmModelName,
                device: settings.voxcpmDevice
            )
            self.init(runtime: runtime)
        } catch {
            self.init(runtime: nil)
        }
    }

    func synthesizeSpeech(from text: String) async throws -> URL {
        guard let worker else {
            throw resolvedRuntimeError()
        }

        return try await worker.synthesize(text: text)
    }

    func prewarm() async throws {
        guard let worker else {
            throw resolvedRuntimeError()
        }

        try await worker.prewarm()
    }

    private func resolvedRuntimeError() -> Error {
        switch runtimeResult {
        case .success:
            return VoiceSynthesisError.requestFailed("VoxCPM worker unavailable.")
        case .failure(let error):
            return error
        }
    }
}

private final class VoxCPMTextToSpeechWorker: @unchecked Sendable {
    private let runtime: LocalVoxCPMSpeechRuntimeConfiguration
    private let queue = DispatchQueue(label: "GraculaExample.VoxCPMWorker")
    private let stdoutSemaphore = DispatchSemaphore(value: 0)
    private let stdoutLock = NSLock()
    private var stdoutBuffer = ""
    private var stdoutLines: [String] = []
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var terminationStatus: Int32?
    private var started = false

    init(runtime: LocalVoxCPMSpeechRuntimeConfiguration) {
        self.runtime = runtime
    }

    func synthesize(text: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    _ = try self.ensureStarted()
                    let response = try self.sendSynthesisRequest(text: text)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func prewarm() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    _ = try self.ensureStarted()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureStarted() throws -> String {
        if started {
            return "ready"
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = runtime.pythonURL
        process.arguments = [
            runtime.workerScriptURL.path,
            "--model", runtime.modelSource,
            "--model-dir", runtime.modelDirectoryURL.path,
            "--device", runtime.device,
            "--cfg-value", "\(runtime.cfgValue)",
            "--inference-timesteps", "\(runtime.inferenceTimesteps)"
        ]
        if runtime.loadDenoiser {
            process.arguments = (process.arguments ?? []) + ["--load-denoiser"]
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HOME"] = runtime.modelDirectoryURL.path
        environment["HUGGINGFACE_HUB_CACHE"] = runtime.modelDirectoryURL.appendingPathComponent("hub").path
        environment["TORCH_HOME"] = runtime.modelDirectoryURL.appendingPathComponent("torch").path
        environment["XDG_CACHE_HOME"] = runtime.modelDirectoryURL.deletingLastPathComponent().path
        environment["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        process.environment = environment

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.ingestStdout(data: handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                log.debug("voxcpm-helper: \(line)")
            }
        }
        process.terminationHandler = { [weak self] process in
            self?.handleTermination(status: process.terminationStatus)
        }

        try process.run()
        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting

        let readyLine = try waitForLine()
        let message = try decodeMessage(from: readyLine)
        guard message.type == "ready" else {
            throw VoiceSynthesisError.requestFailed("VoxCPM worker did not report ready.")
        }

        started = true
        let loadDescription = message.loadMs.map { String(format: "%.2fms", $0) } ?? "unknown"
        log.info("VoxCPM worker ready in \(loadDescription)")
        return "ready"
    }

    private func sendSynthesisRequest(text: String) throws -> URL {
        guard let stdinHandle else {
            throw VoiceSynthesisError.requestFailed("VoxCPM worker stdin is unavailable.")
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw VoiceSynthesisError.emptyText
        }

        let requestID = Int(Date().timeIntervalSince1970 * 1000)
        let payload = VoxCPMRequest(id: requestID, text: trimmedText)
        let requestData = try JSONEncoder().encode(payload)
        var requestPayload = requestData
        requestPayload.append(0x0a)
        try stdinHandle.write(contentsOf: requestPayload)

        let responseLine = try waitForLine()
        let message = try decodeMessage(from: responseLine)
        guard message.id == requestID else {
            throw VoiceSynthesisError.requestFailed("VoxCPM worker returned an out-of-order response.")
        }

        guard message.ok == true else {
            throw VoiceSynthesisError.requestFailed(message.error ?? "VoxCPM worker returned an unknown error.")
        }

        guard let path = message.path else {
            throw VoiceSynthesisError.unexpectedResponse("VoxCPM worker returned no audio path.")
        }

        return URL(fileURLWithPath: path)
    }

    private func ingestStdout(data: Data) {
        guard !data.isEmpty else {
            return
        }

        let chunk = String(decoding: data, as: UTF8.self)
        stdoutLock.lock()
        stdoutBuffer += chunk

        var parts = stdoutBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        if parts.count > 1 {
            stdoutBuffer = String(parts.removeLast())
        } else if stdoutBuffer.hasSuffix("\n") {
            stdoutBuffer = ""
        }

        for part in parts where !part.isEmpty {
            stdoutLines.append(String(part))
            stdoutSemaphore.signal()
        }
        stdoutLock.unlock()
    }

    private func waitForLine() throws -> String {
        while true {
            if let line = popLine() {
                return line
            }

            if let terminationStatus {
                throw VoiceSynthesisError.requestFailed("VoxCPM worker exited with code \(terminationStatus).")
            }

            stdoutSemaphore.wait()
        }
    }

    private func popLine() -> String? {
        stdoutLock.lock()
        defer { stdoutLock.unlock() }

        guard !stdoutLines.isEmpty else {
            return nil
        }

        return stdoutLines.removeFirst()
    }

    private func handleTermination(status: Int32) {
        terminationStatus = status
        stdoutSemaphore.signal()
    }

    private func decodeMessage(from line: String) throws -> VoxCPMWorkerMessage {
        let data = Data(line.utf8)
        do {
            return try JSONDecoder().decode(VoxCPMWorkerMessage.self, from: data)
        } catch {
            throw VoiceSynthesisError.unexpectedResponse("Failed to decode VoxCPM worker response: \(error.localizedDescription)")
        }
    }
}

private struct VoxCPMRequest: Codable {
    let id: Int
    let text: String
}

private struct VoxCPMWorkerMessage: Decodable {
    let type: String
    let ok: Bool?
    let id: Int?
    let path: String?
    let error: String?
    let loadMs: Double?
    let elapsedMs: Double?
    let sampleRate: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case ok
        case id
        case path
        case error
        case sampleRate = "sample_rate"
        case loadMs = "load_ms"
        case elapsedMs = "elapsed_ms"
    }
}

private enum VoxCPMLocalWorkerScript {
    static let source = """
#!/usr/bin/env python3
import argparse
import contextlib
import io
import json
import os
import sys
import tempfile
import time
import traceback

import soundfile as sf
import torch

JSON_STDOUT = sys.__stdout__


def emit(payload):
    JSON_STDOUT.write(json.dumps(payload, ensure_ascii=False) + "\\n")
    JSON_STDOUT.flush()


def swallow_stdout():
    return contextlib.redirect_stdout(io.StringIO())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--cfg-value", type=float, default=2.0)
    parser.add_argument("--inference-timesteps", type=int, default=10)
    parser.add_argument("--load-denoiser", action="store_true")
    args = parser.parse_args()

    os.environ.setdefault("HF_HOME", args.model_dir)
    os.environ.setdefault("HUGGINGFACE_HUB_CACHE", os.path.join(args.model_dir, "hub"))
    os.environ.setdefault("TORCH_HOME", os.path.join(args.model_dir, "torch"))
    os.environ.setdefault("XDG_CACHE_HOME", os.path.dirname(args.model_dir))
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

    started = time.perf_counter()
    with swallow_stdout():
        from voxcpm import VoxCPM
        kwargs = {}
        if args.device and args.device != "auto":
            kwargs["device"] = args.device
        try:
            model = VoxCPM.from_pretrained(args.model, load_denoiser=args.load_denoiser, **kwargs)
        except Exception:
            model = VoxCPM.from_pretrained(args.model, load_denoiser=args.load_denoiser, optimize=False, **kwargs)

    emit({"type": "ready", "load_ms": round((time.perf_counter() - started) * 1000, 2)})

    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue

        request = json.loads(raw)
        request_id = request["id"]
        text = request["text"].strip()
        started = time.perf_counter()
        output_path = None

        try:
            with swallow_stdout():
                wav = model.generate(
                    text=text,
                    cfg_value=args.cfg_value,
                    inference_timesteps=args.inference_timesteps,
                )

            sample_rate = getattr(getattr(model, "tts_model", None), "sample_rate", 48000)
            fd, output_path = tempfile.mkstemp(suffix=".wav")
            os.close(fd)
            sf.write(output_path, wav, sample_rate)

            emit({
                "id": request_id,
                "ok": True,
                "type": "result",
                "path": output_path,
                "sample_rate": sample_rate,
                "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
            })
        except Exception as exc:
            emit({
                "id": request_id,
                "ok": False,
                "type": "error",
                "error": f"{exc}\\n{traceback.format_exc()}",
            })


if __name__ == "__main__":
    main()
"""

    static func writeIfNeeded(to url: URL) throws {
        let data = Data(source.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            if existing == data {
                return
            }
        } else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        try data.write(to: url, options: [.atomic])
    }
}
