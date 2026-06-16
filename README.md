# gan-trans

A new Flutter project.

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

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
