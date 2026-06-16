# GanTrans

GanTrans is an open-source Flutter app for voice, text, and image translation.
It lets you choose the AI provider and model used for each stage of the
translation flow, including speech-to-text, chat translation/correction, and
text-to-speech playback.

## Features

- Push-to-talk and continuous voice input.
- Text translation and correction with scene-specific prompts.
- Image OCR and translation from the camera or photo library.
- Optional text-to-speech playback for translated output.
- Separate provider/model settings for chat, STT, and TTS.
- Optional custom Relay endpoint for routing requests through your own backend.

## Download

### Android

Download the latest universal APK from
[GitHub Releases](https://github.com/aaronwow/gan_trans/releases/latest).

### iOS

GanTrans is not available on the App Store yet. Build and install it locally
with Xcode:

1. Install Flutter and Xcode.
2. Run `flutter pub get`.
3. Open `ios/Runner.xcworkspace` in Xcode.
4. Select your signing team and connect your iPhone.
5. Build and run from Xcode.

## Development

Run the app locally:

```sh
flutter pub get
flutter run
```

Run checks:

```sh
flutter analyze
flutter test
```
