# AI Chat Agent Guide

This document is the first file AI coding agents should read before changing
this project. Keep it accurate. If the app architecture, voice pipeline,
provider catalog, settings flow, or test strategy changes, update this file in
the same change set.

## Project Purpose

`ai_chat` is a Flutter voice translation/correction app. The core product is a
decoupled voice pipeline where users can choose different providers and models
for each stage:

- STT: convert recorded audio into text.
- Translate/correct: use a chat model and scene-specific prompts to transform
  the text.
- TTS: speak the transformed output.

Some chat models can accept audio directly. For those models, the app can skip
the separate STT step and run a fused audio-to-translation/correction request.

The app also supports an image input flow that is intentionally separate from
voice: the user attaches a photo (camera or gallery) and the chat model is
asked to OCR the picture and translate the extracted text in a single call.
Image turns never trigger STT or TTS auto-speak.

## Architecture Overview

The current architecture is intentionally split into catalog, settings,
runtime clients, prompt composition, and pipeline orchestration.

- `lib/catalog.dart`
  - Single source of truth for providers, models, capabilities, credentials,
    voices, and model metadata.
  - Use `Capability` for broad surfaces: `chat`, `stt`, `tts`.
  - Use `Modality` on `ModelSpec.inputs` to declare which non-text inputs a
    chat model accepts: `Modality.audio` for fused audio-direct, `Modality.image`
    for image input. `acceptsAudio()` and `acceptsImage()` are the supported
    runtime checks; never branch on model ID strings to infer modality.
  - Use `SttTransport` for STT transport details: `batchUpload`, `asyncJob`,
    `realtime`.
  - Use `ModelSpec.supportsDirectAudioTranslate` for chat models that can run
    the fused audio-direct translation/correction path.
  - If an OpenRouter-hosted Gemini chat model accepts audio and mirrors a
    Google Gemini model with direct audio support, keep its direct-audio
    metadata aligned with the Google catalog entry.
  - When adding a new chat model, decide its image support deliberately:
    OpenAI 4o/4.1 family, Anthropic Claude 4.x, Gemini 2.x/3.x, Grok-4 fast
    variants, and Llama-4 Maverick/Scout currently carry `Modality.image`.
    Audio-only variants (e.g. `gpt-*-audio-preview`) and pure-text models
    (DeepSeek text variants, Qwen text variants, Llama 3.3, Mistral text
    variants, Grok 3) intentionally do not.
  - Do not infer runtime behavior from model ID strings if a catalog field can
    express it.

- `lib/settings.dart`
  - Persists selected providers/models/voices and user voice pipeline settings.
  - STT/TTS off states disable the route but preserve the last provider,
    model, and voice so quick toggles can restore the user's prior selection.
  - When audio-direct chat is active, STT is runtime-paused rather than
    cleared; UI should show STT as unavailable and keep its saved selection.
  - Image input has its own optional override: `imageProviderId` /
    `imageModelId`. Null means "fall back to the chat model" (only valid when
    that model `acceptsImage()`). Use `effectiveImageProviderId/ModelId`,
    `imageInputAvailable`, and `buildImageChatRequest()` from runtime code
    instead of duplicating the fallback logic.
  - Builds runtime request objects for chat, STT, TTS, and image-chat.
  - Keeps `composedSystemPrompt()` as the settings-facing prompt entry point,
    but actual prompt rules live in `PromptComposer`.

- `lib/prompt_composer.dart`
  - Owns prompt construction for text STT output, direct audio, direct audio
    JSON transcript+output, and image OCR + translate modes.
  - The image intent (`PromptIntent.imageOcrAndTranslate`) emits two sections
    separated by the stable `kImageOcrSeparator` constant. Renderers split on
    that constant to show 原文 vs. 译文; do not change the separator without
    updating both `ImageTranslateStep`'s parser and the chat-screen bubble
    renderer.
  - Add prompt variants here and test them directly.

- `lib/voice_pipeline.dart`
  - Owns pipeline abstractions and orchestration helpers.
  - Key types: `PipelineStrategy`, `PipelineStep`, `PipelineResult`,
    `PipelineError`, `VoicePipelineRunner`.
  - `SttSession` is reserved for future streaming/batch fallback support.

- `lib/chat_conversation_controller.dart`
  - UI-facing state controller for recording, turns, continuous mode,
    half-duplex resume behavior, retry/cancel, and TTS queueing.
  - It should delegate provider calls and transformation logic to
    `VoicePipelineRunner`, not construct wire requests directly.

- `lib/providers.dart`
  - Chat wire clients for provider dialects.
  - `ChatMessage` carries optional `audio` (`ChatAudio`) and `image`
    (`ChatImage`) attachments. The OpenAI dialect serializes images as an
    `image_url` content block with a `data:<mime>;base64,...` URL; the Gemini
    dialect uses an `inline_data` part. New dialects must implement both
    encodings before exposing image-capable models.

- `lib/stt_service.dart`
  - File/async STT wire clients.
  - Current runtime path is post-recording transcription, not realtime
    streaming.

- `lib/tts_service.dart`
  - TTS wire clients and local audio playback.

- `lib/chat_turn.dart`
  - Per-turn UI and pipeline state.
  - Preserve intermediate fields such as `rawTranscript`,
    `normalizedTranscript`, `translatedText`, `displayText`, `ttsText`, and
    `providerTrace`; they are useful for debugging and future UI surfaces.
  - Image turns set `image` (a `ChatImage`) and report `imageInput == true`.
    For image turns, `normalizedTranscript`/`rawTranscript` carry the OCR'd
    source text and `translatedText` carries the translation — both render in
    the assistant bubble as separate 原文/译文 sections.

## Voice Pipeline Strategies

The app currently supports these strategies:

- `sttThenTranslateThenTts`
  - Record audio.
  - Run selected STT provider.
  - Run selected chat provider for translation/correction.
  - Optionally run selected TTS provider.

- `audioDirectTranslateThenTts`
  - Record audio.
  - Send audio directly to selected chat model.
  - Optionally parse JSON with `transcript` and `output`.
  - Optionally run selected TTS provider.

- `textOnlyTranslateThenTts`
  - User types text.
  - Run selected chat provider for translation/correction.
  - Optionally run selected TTS provider.

- `imageOcrAndTranslate`
  - User attaches an image (camera or gallery).
  - Send the image directly to the chat model resolved from
    `effectiveImageProviderId/ModelId` with the
    `PromptIntent.imageOcrAndTranslate` system prompt.
  - Single round-trip: the reply is split on `kImageOcrSeparator` into
    extracted source text and translated/corrected output.
  - Never engages STT or TTS, even when those routes are configured.

When adding a new flow, model it as a strategy or step in
`lib/voice_pipeline.dart` instead of adding another special case to the
controller.

## Provider And Model Rules

- Add providers and models in `lib/catalog.dart` first.
- Add runtime support in the matching service before exposing a model in the UI.
- Realtime STT models should not be exposed through the current file-upload STT
  path unless a `SttSession` implementation exists.
- If a realtime model has a batch fallback, represent that relationship with
  catalog metadata rather than model ID checks.
- TTS models must include at least one usable `TtsVoice` or a separate UI path
  for custom voice IDs.
- Provider credentials should be declared in the provider spec and checked via
  settings/runtime request builders.

## Prompt Rules

- Scene prompts are user-authored domain hints and should be composed through
  `PromptComposer`.
- Text-mode prompts should tell the chat model that the input came from STT.
- Direct-audio prompts should not frame input as already-transcribed text.
- Direct-audio JSON prompts must ask for both `transcript` and `output`, and
  should forbid Markdown and timestamps.
- The image OCR + translate prompt must instruct the model to emit verbatim
  extracted text first, then the literal `kImageOcrSeparator` line, then the
  translated/corrected output. Update the parser in `ImageTranslateStep` and
  the renderer in `chat_screen.dart` together with any change to the
  separator or section contract.
- Add or update prompt tests when changing prompt wording or output contracts.

## Testing

Run these before handing off changes:

```sh
flutter analyze
flutter test
git diff --check
```

Relevant tests:

- `test/gemini_audio_models_test.dart`
  - Catalog exposure and model capability checks.
- `test/prompt_composer_test.dart`
  - Prompt construction behavior.
- `test/voice_pipeline_test.dart`
  - Pipeline helper behavior.
- `test/settings_test.dart`
  - Settings loading and fallback behavior.
- `test/tts_queue_test.dart`
  - TTS queue cancellation behavior.

## Development Notes

- Prefer adding typed metadata to `ModelSpec` over branching on provider or
  model strings.
- Keep provider-specific wire format details inside service/client classes.
- Keep user-visible turn lifecycle and UI state inside
  `ChatConversationController`.
- Keep transformation, provider selection, and step-level errors inside
  `VoicePipelineRunner` and pipeline steps.
- Preserve retry behavior: STT errors should keep the audio file when possible;
  successful STT/direct-audio paths delete the recorded file.
- Avoid unrelated refactors in provider additions.

## Maintenance Requirement

This file is part of the architecture. Whenever future work changes:

- voice pipeline steps or strategies,
- model capability metadata (including `Modality` membership and
  image/audio support),
- settings or provider selection behavior (chat, STT, TTS, or image),
- prompt composition contracts (including the image OCR separator),
- wire-format encodings for non-text content (audio, image, future modalities),
- realtime/batch fallback behavior,
- platform permissions (camera, microphone, photo library) or new native
  dependencies,
- important test commands or test coverage,

update `AGENTS.md` in the same commit. Outdated agent guidance causes future AI
edits to target the wrong abstractions.
