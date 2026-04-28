# Gracula Xcode Example

Open `GraculaExample.xcodeproj` in Xcode and run the `GraculaExample` scheme on `My Mac`.

The example target links the local Swift package at `../..` and wires the same app shell, application core, local LLM adapter, safe tools, audit log, and Apple text-to-speech adapter used by the SwiftPM executable.

Manual commands to try:

```text
remember finish milestone 9
https://apple.com
open app Notes
read /Users/jazzblood/Documents/Gracula/test.txt
```

If `GRACULA_LLM_ENDPOINT` is not set in the scheme environment, the example uses the built-in demo planner. To use a local OpenAI/Ollama-compatible planner, add these environment variables to the Xcode scheme:

```text
GRACULA_LLM_ENDPOINT=http://localhost:11434/v1/chat/completions
GRACULA_LLM_MODEL=your-local-model
```
