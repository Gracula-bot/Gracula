import Foundation

struct LocalSpeechRuntimeConfiguration: Sendable {
    let backend: SpeechRecognitionBackend
    let pythonURL: URL
    let modelDirectoryURL: URL
    let modelName: String
    let languageCode: String
    let computeType: String
    let device: String
    let cpuThreads: Int
    let workerScriptURL: URL
    let ffmpegURL: URL?

    func overriding(device newDevice: String) -> LocalSpeechRuntimeConfiguration {
        LocalSpeechRuntimeConfiguration(
            backend: backend,
            pythonURL: pythonURL,
            modelDirectoryURL: modelDirectoryURL,
            modelName: modelName,
            languageCode: languageCode,
            computeType: computeType,
            device: newDevice,
            cpuThreads: cpuThreads,
            workerScriptURL: workerScriptURL,
            ffmpegURL: ffmpegURL
        )
    }

    static func `default`(
        backend: SpeechRecognitionBackend,
        modelName: String? = nil,
        languageCode: String? = nil
    ) throws -> LocalSpeechRuntimeConfiguration {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GraculaExample", isDirectory: true)

        let repositoryCandidates = candidateRepositoryRoots(
            currentDirectory: URL(fileURLWithPath: fileManager.currentDirectoryPath)
        )

        let pythonCandidates: [URL] = [
            environment["GRACULA_WHISPER_PYTHON"].map { URL(fileURLWithPath: $0) },
            applicationSupportDirectory
                .appendingPathComponent("PythonRuntime", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("python"),
            Self.exampleDirectoryPythonURL(
                in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            ),
        ] + repositoryCandidates.map(Self.examplePythonURL(in:))

        guard let pythonURL = pythonCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw FileSpeechTranscriberError.runtimeMissing(
                "Python runtime not found. Expected `GRACULA_WHISPER_PYTHON`, `~/Library/Application Support/GraculaExample/PythonRuntime/bin/python`, or `Examples/GraculaExample/.whisper-venv/bin/python` under the repository checkout."
            )
        }

        let resolvedModelName = modelName ?? defaultModelName(for: backend)
        let resolvedLanguageCode = languageCode ?? defaultLanguageCode(for: backend)

        let (modelDirectoryURL, workerScriptURL) = backend == .whisper
            ? (
                applicationSupportDirectory.appendingPathComponent("FasterWhisperModels", isDirectory: true),
                applicationSupportDirectory.appendingPathComponent("faster-whisper-worker.py")
            )
            : (
                applicationSupportDirectory.appendingPathComponent("ParakeetModels", isDirectory: true),
                applicationSupportDirectory.appendingPathComponent("parakeet-worker.py")
            )
        try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        try backend.workerScript.writeIfNeeded(to: workerScriptURL)

        let ffmpegCandidates = [
            environment["GRACULA_FFMPEG_PATH"].map { URL(fileURLWithPath: $0) },
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        ]
        .compactMap { $0 }
        let ffmpegURL = ffmpegCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })

        return LocalSpeechRuntimeConfiguration(
            backend: backend,
            pythonURL: pythonURL,
            modelDirectoryURL: modelDirectoryURL,
            modelName: resolvedModelName,
            languageCode: resolvedLanguageCode,
            computeType: "int8",
            device: backend == .parakeet ? "auto" : "cpu",
            cpuThreads: max(1, ProcessInfo.processInfo.activeProcessorCount),
            workerScriptURL: workerScriptURL,
            ffmpegURL: ffmpegURL
        )
    }

    private static func defaultModelName(for backend: SpeechRecognitionBackend) -> String {
        switch backend {
        case .whisper:
            return VoicePipelineSettings.Defaults.whisperModelName
        case .parakeet:
            return VoicePipelineSettings.Defaults.parakeetModelName
        }
    }

    private static func defaultLanguageCode(for backend: SpeechRecognitionBackend) -> String {
        switch backend {
        case .whisper:
            return VoicePipelineSettings.Defaults.whisperLanguageCode
        case .parakeet:
            return VoicePipelineSettings.Defaults.parakeetLanguageCode
        }
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

    private static func candidateRepositoryRoots(currentDirectory: URL) -> [URL] {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []

        if let override = environment["GRACULA_PROJECT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override, isDirectory: true))
        }

        candidates.append(currentDirectory)

        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        candidates.append(homeDirectory.appendingPathComponent("Documents", isDirectory: true))
        candidates.append(homeDirectory.appendingPathComponent("Code", isDirectory: true))
        candidates.append(homeDirectory)

        var resolvedRoots: [URL] = []
        for candidate in candidates {
            if let root = locateGraculaProjectRoot(startingAt: candidate),
               !resolvedRoots.contains(root) {
                resolvedRoots.append(root)
            }
        }

        return resolvedRoots
    }

    private static func locateGraculaProjectRoot(startingAt url: URL) -> URL? {
        let fileManager = FileManager.default
        var candidate = url.standardizedFileURL

        while candidate.path != "/" {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path),
               fileManager.fileExists(atPath: candidate.appendingPathComponent("Examples", isDirectory: true).path),
               fileManager.fileExists(atPath: candidate.appendingPathComponent("Examples/GraculaExample", isDirectory: true).path) {
                return candidate
            }
            candidate = candidate.deletingLastPathComponent()
        }

        return nil
    }
}

final class FileSpeechTranscriber: @unchecked Sendable {
    private var runtimeResult: Result<LocalSpeechRuntimeConfiguration, Error>
    private var worker: WhisperTranscriptionWorker?

    init(runtime: LocalSpeechRuntimeConfiguration? = nil) {
        if let runtime {
            self.runtimeResult = .success(runtime)
            self.worker = WhisperTranscriptionWorker(runtime: runtime)
            return
        }

        do {
            let runtime = try LocalSpeechRuntimeConfiguration.default(backend: .whisper)
            self.runtimeResult = .success(runtime)
            self.worker = WhisperTranscriptionWorker(runtime: runtime)
        } catch {
            self.runtimeResult = .failure(error)
            self.worker = nil
        }
    }

    convenience init(settings: VoicePipelineSettings) {
        do {
            let runtime: LocalSpeechRuntimeConfiguration
            switch settings.speechRecognitionBackend {
            case .whisper:
                runtime = try LocalSpeechRuntimeConfiguration.default(
                    backend: .whisper,
                    modelName: settings.whisperModelName,
                    languageCode: settings.whisperLanguageCode
                )
            case .parakeet:
                runtime = try LocalSpeechRuntimeConfiguration.default(
                    backend: .parakeet,
                    modelName: settings.parakeetModelName,
                    languageCode: settings.parakeetLanguageCode
                )
            }
            self.init(runtime: runtime)
        } catch {
            self.init(runtime: nil)
        }
    }

    var runtimeSummary: String {
        guard let runtime = try? resolvedRuntime() else {
            if case .failure(let error) = runtimeResult {
                return "unavailable (\(error.localizedDescription))"
            }
            return "unavailable"
        }

        return [
            "backend=\(runtime.backend.rawValue)",
            "python=\(runtime.pythonURL.path)",
            "model=\(runtime.modelName)",
            "language=\(runtime.languageCode)",
            "computeType=\(runtime.computeType)",
            "device=\(runtime.device)",
            "cpuThreads=\(runtime.cpuThreads)",
            "modelDir=\(runtime.modelDirectoryURL.path)",
            "worker=\(runtime.workerScriptURL.lastPathComponent)"
        ].joined(separator: ", ")
    }

    func prewarm() async {
        guard let worker else {
            return
        }

        do {
            _ = try await worker.prewarm()
        } catch {
            if fallbackToCPUIfNeeded(for: error) {
                await prewarm()
                return
            }
            log.warning("Speech prewarm failed: \(error.localizedDescription)")
        }
    }

    func transcribeFile(at url: URL) async throws -> String {
        let startedAt = PerformanceLog.checkpoint()
        let backendName = (try? resolvedRuntime()).map { $0.backend.rawValue } ?? "unknown"
        log.debug("\(backendName.capitalized) transcription requested for \(url.lastPathComponent)")

        guard let worker else {
            throw resolvedRuntimeError()
        }

        do {
            let text = try await worker.transcribe(fileURL: url)
            log.debug("\(backendName.capitalized) transcription finished in \(PerformanceLog.elapsedDescription(since: startedAt)); file=\(url.lastPathComponent); characters=\(text.count)")
            return text
        } catch {
            if fallbackToCPUIfNeeded(for: error) {
                do {
                    let retryText = try await transcribeFile(at: url)
                    return retryText
                } catch {
                    log.error("\(backendName.capitalized) transcription failed after \(PerformanceLog.elapsedDescription(since: startedAt)): \(error.localizedDescription)")
                    throw error
                }
            }
            log.error("\(backendName.capitalized) transcription failed after \(PerformanceLog.elapsedDescription(since: startedAt)): \(error.localizedDescription)")
            throw error
        }
    }

    @discardableResult
    private func fallbackToCPUIfNeeded(for error: Error) -> Bool {
        guard let runtime = try? resolvedRuntime(),
              runtime.backend == .parakeet,
              runtime.device != "cpu",
              shouldFallbackToCPU(for: error)
        else {
            return false
        }

        let fallbackRuntime = runtime.overriding(device: "cpu")
        runtimeResult = .success(fallbackRuntime)
        worker = WhisperTranscriptionWorker(runtime: fallbackRuntime)
        log.warning("Parakeet MPS path failed; falling back to CPU.")
        return true
    }

    private func shouldFallbackToCPU(for error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("compute function")
            || description.contains("metal")
            || description.contains("mps")
            || description.contains("signal 13")
            || description.contains("exit with code 6")
            || description.contains("speech worker exited with code 6")
    }

    private func resolvedRuntime() throws -> LocalSpeechRuntimeConfiguration {
        switch runtimeResult {
        case .success(let runtime):
            return runtime
        case .failure(let error):
            if let error = error as? FileSpeechTranscriberError {
                throw error
            }
            throw FileSpeechTranscriberError.runtimeMissing(error.localizedDescription)
        }
    }

    private func resolvedRuntimeError() -> Error {
        do {
            _ = try resolvedRuntime()
            return FileSpeechTranscriberError.runtimeMissing("Speech runtime unavailable.")
        } catch {
            return error
        }
    }
}

private actor WhisperTranscriptionWorker {
    private let runtime: LocalSpeechRuntimeConfiguration
    private var operationInProgress = false
    private var stdoutBuffer = ""
    private var stdoutLines: [String] = []
    private var pendingOperationContinuations: [CheckedContinuation<Void, Never>] = []
    private var pendingLineContinuation: CheckedContinuation<String, Error>?
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var terminationStatus: Int32?
    private var started = false

    init(runtime: LocalSpeechRuntimeConfiguration) {
        self.runtime = runtime
    }

    func prewarm() async throws -> String {
        await beginOperation()
        defer { endOperation() }

        return try await ensureStarted()
    }

    func transcribe(fileURL: URL) async throws -> String {
        await beginOperation()
        defer { endOperation() }

        _ = try await ensureStarted()
        return try await sendTranscriptionRequest(fileURL: fileURL)
    }

    private func beginOperation() async {
        guard operationInProgress else {
            operationInProgress = true
            return
        }

        await withCheckedContinuation { continuation in
            pendingOperationContinuations.append(continuation)
        }
    }

    private func endOperation() {
        guard !pendingOperationContinuations.isEmpty else {
            operationInProgress = false
            return
        }

        let continuation = pendingOperationContinuations.removeFirst()
        continuation.resume()
    }

    private func ensureStarted() async throws -> String {
        if started {
            return "ready"
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = runtime.pythonURL
        var arguments = [
            runtime.workerScriptURL.path,
            "--model", runtime.modelName,
            "--model-dir", runtime.modelDirectoryURL.path,
            "--language", runtime.languageCode,
            "--compute-type", runtime.computeType,
            "--device", runtime.device,
            "--cpu-threads", "\(runtime.cpuThreads)"
        ]
        if let ffmpegURL = runtime.ffmpegURL {
            arguments.append(contentsOf: ["--ffmpeg", ffmpegURL.path])
        }
        process.arguments = arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HOME"] = runtime.modelDirectoryURL.path
        environment["XDG_CACHE_HOME"] = runtime.modelDirectoryURL.deletingLastPathComponent().path
        if let ffmpegURL = runtime.ffmpegURL {
            environment["GRACULA_FFMPEG_PATH"] = ffmpegURL.path
            environment["FFMPEG_BINARY"] = ffmpegURL.path
            let ffmpegDirectory = ffmpegURL.deletingLastPathComponent().path
            if let existingPath = environment["PATH"], !existingPath.isEmpty {
                environment["PATH"] = "\(ffmpegDirectory):\(existingPath)"
            } else {
                environment["PATH"] = ffmpegDirectory
            }
        }
        if runtime.backend == .parakeet {
            environment["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        }
        process.environment = environment

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            Task {
                await self?.ingestStdout(data: data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                log.debug("whisper-helper: \(line)")
            }
        }
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(status: process.terminationStatus)
            }
        }

        try process.run()
        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting

        let readyLine = try await waitForLine()
        let message = try decodeMessage(from: readyLine)
        guard message.type == "ready" else {
            throw FileSpeechTranscriberError.transcriptionFailed("Speech worker did not report ready.")
        }

        started = true
        let loadDescription = message.loadMs.map { String(format: "%.2fms", $0) } ?? "unknown"
        log.info("Speech worker ready in \(loadDescription)")
        return "ready"
    }

    private func sendTranscriptionRequest(fileURL: URL) async throws -> String {
        guard let stdinHandle else {
            throw FileSpeechTranscriberError.transcriptionFailed("Speech worker stdin is unavailable.")
        }

        let requestID = Int(Date().timeIntervalSince1970 * 1000)
        let payload = WhisperRequest(id: requestID, path: fileURL.path)
        let requestData = try JSONEncoder().encode(payload)
        var requestPayload = requestData
        requestPayload.append(0x0a)
        try stdinHandle.write(contentsOf: requestPayload)

        let responseLine = try await waitForLine()
        let message = try decodeMessage(from: responseLine)
        guard message.id == requestID else {
            throw FileSpeechTranscriberError.transcriptionFailed("Speech worker returned an out-of-order response.")
        }

        guard message.ok == true else {
            throw FileSpeechTranscriberError.transcriptionFailed(message.error ?? "Speech worker returned an unknown error.")
        }

        return message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func ingestStdout(data: Data) {
        let chunk = String(decoding: data, as: UTF8.self)
        stdoutBuffer += chunk

        var parts = stdoutBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        if parts.count > 1 {
            stdoutBuffer = String(parts.removeLast())
        } else if stdoutBuffer.hasSuffix("\n") {
            stdoutBuffer = ""
        }

        for part in parts where !part.isEmpty {
            let line = String(part)
            if let pendingLineContinuation {
                self.pendingLineContinuation = nil
                pendingLineContinuation.resume(returning: line)
            } else {
                stdoutLines.append(line)
            }
        }
    }

    private func waitForLine() async throws -> String {
        if let line = popLine() {
            return line
        }

        if let terminationStatus {
            throw FileSpeechTranscriberError.transcriptionFailed("Speech worker exited with code \(terminationStatus).")
        }

        return try await withCheckedThrowingContinuation { continuation in
            if let line = popLine() {
                continuation.resume(returning: line)
                return
            }

            if let terminationStatus {
                continuation.resume(
                    throwing: FileSpeechTranscriberError.transcriptionFailed(
                        "Speech worker exited with code \(terminationStatus)."
                    )
                )
                return
            }

            pendingLineContinuation = continuation
        }
    }

    private func popLine() -> String? {
        guard !stdoutLines.isEmpty else {
            return nil
        }
        return stdoutLines.removeFirst()
    }

    private func handleTermination(status: Int32) {
        terminationStatus = status
        guard let pendingLineContinuation else {
            return
        }

        self.pendingLineContinuation = nil
        pendingLineContinuation.resume(
            throwing: FileSpeechTranscriberError.transcriptionFailed(
                "Speech worker exited with code \(status)."
            )
        )
    }

    private func decodeMessage(from line: String) throws -> WhisperWorkerMessage {
        let data = Data(line.utf8)
        do {
            return try JSONDecoder().decode(WhisperWorkerMessage.self, from: data)
        } catch {
            throw FileSpeechTranscriberError.transcriptionFailed("Failed to decode speech worker response: \(error.localizedDescription)")
        }
    }
}

private struct WhisperRequest: Codable {
    let id: Int
    let path: String
}

private struct WhisperWorkerMessage: Decodable {
    let type: String
    let ok: Bool?
    let id: Int?
    let text: String?
    let error: String?
    let loadMs: Double?
    let elapsedMs: Double?
    let language: String?

    enum CodingKeys: String, CodingKey {
        case type
        case ok
        case id
        case text
        case error
        case language
        case loadMs = "load_ms"
        case elapsedMs = "elapsed_ms"
    }
}

private extension SpeechRecognitionBackend {
    var workerScript: LocalSpeechWorkerScript {
        switch self {
        case .whisper:
            return .whisper
        case .parakeet:
            return .parakeet
        }
    }
}

private enum LocalSpeechWorkerScript {
    case whisper
    case parakeet

    func writeIfNeeded(to url: URL) throws {
        switch self {
        case .whisper:
            try WhisperWorkerScript.writeIfNeeded(to: url)
        case .parakeet:
            try ParakeetWorkerScript.writeIfNeeded(to: url)
        }
    }
}

enum FileSpeechTranscriberError: LocalizedError {
    case runtimeMissing(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing(let message):
            return message
        case .transcriptionFailed(let message):
            return message
        }
    }
}

private enum WhisperWorkerScript {
    static let source = """
#!/usr/bin/env python3
import argparse
import json
import os
import sys
import time
import traceback

from faster_whisper import WhisperModel


def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\\n")
    sys.stdout.flush()


def log(payload):
    sys.stderr.write(json.dumps(payload, ensure_ascii=False) + "\\n")
    sys.stderr.flush()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--language", default="en")
    parser.add_argument("--compute-type", default="int8")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--cpu-threads", type=int, default=0)
    parser.add_argument("--ffmpeg", default="")
    args = parser.parse_args()

    os.environ.setdefault("OMP_NUM_THREADS", str(args.cpu_threads))
    started = time.perf_counter()
    model = WhisperModel(
        args.model,
        device="cpu",
        compute_type=args.compute_type,
        cpu_threads=args.cpu_threads,
        num_workers=1,
        download_root=args.model_dir,
    )
    emit({"type": "ready", "load_ms": round((time.perf_counter() - started) * 1000, 2)})

    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        request = json.loads(raw)
        request_id = request["id"]
        audio_path = request["path"]
        started = time.perf_counter()
        try:
            segments, info = model.transcribe(
                audio_path,
                task="transcribe",
                language=args.language,
                beam_size=1,
                best_of=1,
                condition_on_previous_text=False,
                without_timestamps=True,
                vad_filter=True,
                temperature=0.0,
            )
            text = "".join(segment.text for segment in segments).strip()
            emit({
                "id": request_id,
                "ok": True,
                "type": "result",
                "text": text,
                "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
                "language": getattr(info, "language", None),
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

private enum ParakeetWorkerScript {
    static let source = """
#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
import contextlib
import io

import torch


JSON_STDOUT = sys.__stdout__


def emit(payload):
    JSON_STDOUT.write(json.dumps(payload, ensure_ascii=False) + "\\n")
    JSON_STDOUT.flush()


def swallow_stdout():
    return contextlib.redirect_stdout(io.StringIO())


def convert_audio(input_path, ffmpeg_path):
    fd, output_path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    command = [
        ffmpeg_path,
        "-y",
        "-i",
        input_path,
        "-ac",
        "1",
        "-ar",
        "16000",
        "-vn",
        output_path,
    ]
    subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return output_path


def ffmpeg_binary(args):
    return args.ffmpeg or os.environ.get("GRACULA_FFMPEG_PATH") or shutil.which("ffmpeg") or "ffmpeg"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--language", default="auto")
    parser.add_argument("--compute-type", default="int8")
    parser.add_argument("--device", default="auto")
    parser.add_argument("--cpu-threads", type=int, default=0)
    parser.add_argument("--ffmpeg", default="")
    args = parser.parse_args()

    os.environ.setdefault("HF_HOME", args.model_dir)
    os.environ.setdefault("HUGGINGFACE_HUB_CACHE", os.path.join(args.model_dir, "hub"))
    os.environ.setdefault("TORCH_HOME", os.path.join(args.model_dir, "torch"))
    os.environ.setdefault("XDG_CACHE_HOME", os.path.dirname(args.model_dir))
    os.environ.setdefault("OMP_NUM_THREADS", str(args.cpu_threads))
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
    os.environ.setdefault("FFMPEG_BINARY", ffmpeg_binary(args))

    if args.device == "auto":
        if torch.backends.mps.is_available() and torch.backends.mps.is_built():
            device = "mps"
        else:
            device = "cpu"
    else:
        device = args.device

    started = time.perf_counter()
    with swallow_stdout():
        from nemo.collections.asr.models import ASRModel
        model = ASRModel.from_pretrained(args.model)
        model.eval()
        if device != "cpu":
            model = model.to(device)
    emit({"type": "ready", "load_ms": round((time.perf_counter() - started) * 1000, 2)})

    ffmpeg_path = ffmpeg_binary(args)

    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        request = json.loads(raw)
        request_id = request["id"]
        audio_path = request["path"]
        started = time.perf_counter()
        wav_path = None
        try:
            wav_path = convert_audio(audio_path, ffmpeg_path)
            with swallow_stdout():
                hypotheses = model.transcribe([wav_path])
            transcript = hypotheses[0]
            text = getattr(transcript, "text", "").strip()
            emit({
                "id": request_id,
                "ok": True,
                "type": "result",
                "text": text,
                "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
                "language": getattr(transcript, "language", None) or args.language,
            })
        except Exception as exc:
            emit({
                "id": request_id,
                "ok": False,
                "type": "error",
                "error": f"{exc}\\n{traceback.format_exc()}",
            })
        finally:
            if wav_path and os.path.exists(wav_path):
                try:
                    os.unlink(wav_path)
                except OSError:
                    pass


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
