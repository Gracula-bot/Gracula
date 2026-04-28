# Gracula Xcode Example

Open `GraculaExample.xcodeproj` in Xcode and run the `GraculaExample` scheme on `My Mac`.

The example target is a small manual macOS app for testing microphone recording and local speech recognition. It lets you choose a CoreAudio microphone/input source, then saves each message as a `.caf` audio file under:

```bash
$HOME/Library/Application Support/GraculaExample/Recordings
```

Choose an input source, then tap `Record Message` once to start recording. Tap the same button again to stop recording. The saved audio file path appears in the app as the latest file source, then a local speech worker transcribes the file and shows the recognized text in the UI.

The app keeps speech recognition and speech synthesis behind a config file so you can swap backends without changing the UI wiring. The default recognizer now uses a local Whisper worker, Parakeet stays available as a config option, and recognized text can be spoken back through local VoxCPM, a VoxCPM-compatible TTS endpoint, or a macOS system voice fallback.

The config file lives at:

```bash
$HOME/Library/Application Support/GraculaExample/voice-pipeline.json
```

Useful fields:

- `speechRecognitionBackend`: `whisper` or `parakeet`
- `parakeetModelName`: defaults to `nvidia/parakeet-tdt-0.6b-v3`
- `whisperModelName`: defaults to `small`
- `whisperLanguageCode`: defaults to `ru`
- `speechSynthesisBackend`: `voxcpmLocal`, `voxcpmServer`, `appleSystem`, or `disabled`
- `speakRecognizedText`: `true` or `false`
- `appleSystemVoiceLanguageCode`: defaults to `ru-RU`
- `voxcpmServerBaseURL`: defaults to `http://127.0.0.1:8000`
- `voxcpmModelName`: defaults to `openbmb/VoxCPM2`
- `voxcpmVoiceName`: defaults to `default`
- `voxcpmDevice`: defaults to `cpu`

Whisper is the default and now starts at `small` for better recognition quality. Parakeet v3 auto-detects language and supports Russian, Ukrainian, and other European languages if you want to compare the models later.

Project layout now follows the repo architecture more closely:

```text
GraculaExample/
├─ AgentApp/
│  └─ GraculaExampleApp.swift
├─ AppShell/
│  ├─ AudioRecorderExampleView.swift
│  └─ AudioRecorderViewModel.swift
├─ Persistence/
│  └─ VoicePipelineSettings.swift
├─ Voice/
│  ├─ DiskAudioRecorder.swift
│  ├─ FileSpeechTranscriber.swift
│  ├─ SpeechSynthesizing.swift
│  ├─ AppleSystemSpeechSpeaker.swift
│  ├─ VoicePlayback.swift
│  ├─ VoicePipeline.swift
│  └─ VoxCPMSpeechSynthesizer.swift
└─ Shared/
   └─ Logger.swift
```

What changed in this refactor:

- moved the app entry point into `AgentApp/`
- moved UI and view state into `AppShell/`
- moved audio capture and speech backends into `Voice/`
- added a Voice pipeline that can synthesize recognized text through a VoxCPM-compatible endpoint and play it back
- moved persisted pipeline settings into `Persistence/`
- moved logging and timing helpers into `Shared/`
- kept the Xcode project working through file-system-synced folders, so the new structure is reflected without extra manual project wiring

The local runtime currently expects:

```bash
Examples/GraculaExample/.whisper-venv/bin/python
$HOME/Library/Application Support/GraculaExample/FasterWhisperModels
$HOME/Library/Application Support/GraculaExample/faster-whisper-worker.py
$HOME/Library/Application Support/GraculaExample/ParakeetModels
$HOME/Library/Application Support/GraculaExample/parakeet-worker.py
```

For local VoxCPM speech synthesis, the app runs a long-lived Python worker using the official `voxcpm` package and `openbmb/VoxCPM2`. The first run downloads the model into `~/Library/Application Support/GraculaExample/VoxCPMModels`, and later runs load the local snapshot directly instead of reaching back to Hugging Face. The default device is `cpu` because the current PyTorch MPS path is unstable for this model on this Mac. If you want to experiment anyway, set `voxcpmDevice` to `auto` or `mps`.

For remote VoxCPM speech synthesis, the app expects an OpenAI-compatible `/v1/audio/speech` server. The official VoxCPM README documents the CUDA-backed path via `vllm serve openbmb/VoxCPM2 --omni --port 8000` and an OpenAI-style audio API. Point `voxcpmServerBaseURL` at that server if you want the app to speak recognized text back out loud.

The local macOS fallback is configured for Russian by default through `appleSystemVoiceLanguageCode=ru-RU`.

If you need to override the Python runtime, set `GRACULA_WHISPER_PYTHON` in the Xcode scheme environment.

If you want the first transcription to be even faster, launch the app once and leave it open briefly so the worker can finish model warmup before your first recording.

The picker intentionally hides output-style devices such as Display Audio, HDMI, DisplayPort, AirPlay, speakers, and receivers. Those devices can appear in CoreAudio lists but are not stable microphone recording sources.
