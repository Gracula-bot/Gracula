---
name: gracula-voice-pipeline
description: Use when implementing Gracula voice features: microphone capture, Apple Speech transcription, text-to-speech, VoicePipeline actor, transcript state, and permission prompts.
---

# Gracula Voice Pipeline

Use this skill for STT, TTS, microphone capture, and voice orchestration.

## Required Reading

Read `agent.md` sections 3, 5, 6, 8, 10, 12, and 16.

## Workflow

1. Add voice protocols before adapters:
   - `AudioCapturing`
   - `SpeechRecognizing`
   - `SpeechSynthesizing`
2. Implement `AppleSpeechSynthesizer` with `AVSpeechSynthesizer`.
3. Add stop speaking support.
4. Add microphone permission flow only when the feature is used.
5. Implement audio capture with `AVAudioEngine`.
6. Implement Apple Speech adapter.
7. Emit `TranscriptEvent.partial` and `TranscriptEvent.final`.
8. Implement `VoicePipeline` as an actor.
9. Process final transcripts first.
10. Keep manual text input available as a fallback.

## Guardrails

- Keep `Voice` behind protocols.
- Do not put voice adapter code in `Application` or `Domain`.
- Do not request permissions at launch unless the corresponding feature is used.
- Do not block the main actor during capture, transcription, or speech.

## Validation

- UI shows partial transcript.
- Final transcript reaches `AgentOrchestrator`.
- Agent can speak the result.
- TTS can be stopped.
- UI remains responsive.

