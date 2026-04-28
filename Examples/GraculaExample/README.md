# Gracula Xcode Example

Open `GraculaExample.xcodeproj` in Xcode and run the `GraculaExample` scheme on `My Mac`.

The example target is a small manual macOS app for testing microphone recording and local speech recognition. It lets you choose a CoreAudio microphone/input source, then saves each message as a `.caf` audio file under:

```bash
$HOME/Library/Application Support/GraculaExample/Recordings
```

Choose an input source, then tap `Record Message` once to start recording. Tap the same button again to stop recording. The saved audio file path appears in the app as the latest file source, then a local `faster-whisper` worker transcribes the file and shows the recognized text in the UI.

The app keeps speech recognition behind a config file so you can swap models without changing the UI wiring. The default recognizer now uses a local Whisper worker, and Parakeet stays available as a config option for later comparison.

The config file lives at:

```bash
$HOME/Library/Application Support/GraculaExample/voice-pipeline.json
```

Useful fields:

- `speechRecognitionBackend`: `whisper` or `parakeet`
- `parakeetModelName`: defaults to `nvidia/parakeet-tdt-0.6b-v3`
- `whisperModelName`: defaults to `tiny`
- `whisperLanguageCode`: defaults to `ru`

Whisper is the default. Parakeet v3 auto-detects language and supports Russian, Ukrainian, and other European languages if you want to compare the models later.

The local runtime currently expects:

```bash
Examples/GraculaExample/.whisper-venv/bin/python
$HOME/Library/Application Support/GraculaExample/ParakeetModels
$HOME/Library/Application Support/GraculaExample/parakeet-worker.py
```

If you need to override the Python runtime, set `GRACULA_WHISPER_PYTHON` in the Xcode scheme environment.

If you want the first transcription to be even faster, launch the app once and leave it open briefly so the worker can finish model warmup before your first recording.

The picker intentionally hides output-style devices such as Display Audio, HDMI, DisplayPort, AirPlay, speakers, and receivers. Those devices can appear in CoreAudio lists but are not stable microphone recording sources.
