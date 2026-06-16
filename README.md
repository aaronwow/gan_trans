# gan-trans

GanTrans is a Flutter app for voice, text, and image translation. It is built
around a configurable AI pipeline: record or type input, send it to a selected
model for correction/translation, and optionally play the translated result
with text-to-speech.

## Features

- Voice input with push-to-talk and continuous listening modes.
- Text correction and translation with scene-specific prompts.
- Image OCR and translation from camera or photo library.
- Optional TTS playback for translated output.
- Configurable providers and models for chat, STT, and TTS.
- Optional custom Relay endpoint for routing requests through your own backend.

## Android Release APK

GitHub Actions builds and publishes a universal Android APK to GitHub Releases.

Create a release from a tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Or run the `Android Release APK` workflow manually from GitHub Actions. If the
manual run does not provide a tag, it uses the version from `pubspec.yaml`
(`version: 1.0.0+1` becomes release tag `v1.0.0`).

The published APK asset is named like:

```text
gan-trans-v1.0.0-universal.apk
```
