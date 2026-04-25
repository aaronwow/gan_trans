import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecordingResult {
  final String path;
  final String format;

  const RecordingResult({required this.path, required this.format});
}

class VoiceRecorderController {
  static const recordFormat = 'wav';

  final AudioRecorder _recorder;
  final VoidCallback onChanged;
  final VoidCallback onAutoCut;
  final void Function(String message) onError;

  StreamSubscription<Amplitude>? _ampSub;
  Timer? _maxListenTimer;
  String? _currentRecordingPath;
  DateTime? _recordStartedAt;
  DateTime? _firstSpeechAt;
  DateTime? _lastSpeechAt;
  bool _hadSpeech = false;
  bool _disposed = false;

  bool listening = false;
  double soundLevel = 0;
  bool speakingNow = false;

  VoiceRecorderController({
    required this.onChanged,
    required this.onAutoCut,
    required this.onError,
    AudioRecorder? recorder,
  }) : _recorder = recorder ?? AudioRecorder();

  Future<void> start({
    required bool echoCancellation,
    required bool continuous,
    required int maxListenSeconds,
    required double vadThresholdLevel,
    required double vadPauseSeconds,
  }) async {
    if (listening) return;
    if (!await _recorder.hasPermission()) {
      onError('Microphone permission denied.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.$recordFormat';
    try {
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: echoCancellation,
          noiseSuppress: echoCancellation,
          autoGain: echoCancellation,
          androidConfig: AndroidRecordConfig(
            audioSource: echoCancellation
                ? AndroidAudioSource.voiceCommunication
                : AndroidAudioSource.defaultSource,
            audioManagerMode: echoCancellation
                ? AudioManagerMode.modeInCommunication
                : AudioManagerMode.modeNormal,
          ),
        ),
        path: path,
      );
    } catch (e) {
      onError('Failed to start recording: $e');
      return;
    }
    _currentRecordingPath = path;
    _recordStartedAt = DateTime.now();
    _hadSpeech = false;
    speakingNow = false;
    _firstSpeechAt = null;
    _lastSpeechAt = null;
    await _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 150))
        .listen(
          (a) => _onAmplitude(
            a,
            continuous: continuous,
            threshold: vadThresholdLevel,
            pauseSeconds: vadPauseSeconds,
          ),
        );
    _maxListenTimer?.cancel();
    if (continuous) {
      _maxListenTimer = Timer(Duration(seconds: maxListenSeconds), () {
        if (!_disposed && listening) onAutoCut();
      });
    }
    listening = true;
    onChanged();
  }

  Future<RecordingResult?> stop({
    required bool continuous,
    required double minRecordSeconds,
  }) async {
    if (!listening) return null;
    final path = await _recorder.stop();
    _maxListenTimer?.cancel();
    _maxListenTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;

    final startedAt = _recordStartedAt;
    final firstSpeech = _firstSpeechAt;
    final lastSpeech = _lastSpeechAt;
    final hadSpeech = _hadSpeech;
    _recordStartedAt = null;
    _firstSpeechAt = null;
    _lastSpeechAt = null;
    _hadSpeech = false;

    listening = false;
    soundLevel = 0;
    speakingNow = false;
    onChanged();

    final recorded = path ?? _currentRecordingPath;
    _currentRecordingPath = null;
    if (recorded == null) return null;

    final Duration elapsed;
    if (continuous) {
      elapsed = (hadSpeech && firstSpeech != null && lastSpeech != null)
          ? lastSpeech.difference(firstSpeech)
          : Duration.zero;
    } else {
      elapsed = startedAt == null
          ? Duration.zero
          : DateTime.now().difference(startedAt);
    }
    final minMs = (minRecordSeconds * 1000).round();
    if (elapsed.inMilliseconds < minMs) {
      unawaited(File(recorded).delete().catchError((_) => File(recorded)));
      return null;
    }

    return RecordingResult(path: recorded, format: recordFormat);
  }

  Future<void> cancelAndDelete() async {
    _maxListenTimer?.cancel();
    _maxListenTimer = null;
    final recorded = listening ? await _recorder.stop() : null;
    final fallback = _currentRecordingPath;
    for (final path in [recorded, fallback]) {
      if (path != null) {
        unawaited(File(path).delete().catchError((_) => File(path)));
      }
    }
    await _ampSub?.cancel();
    _ampSub = null;
    _currentRecordingPath = null;
    _recordStartedAt = null;
    _firstSpeechAt = null;
    _lastSpeechAt = null;
    _hadSpeech = false;
    listening = false;
    soundLevel = 0;
    speakingNow = false;
    onChanged();
  }

  void _onAmplitude(
    Amplitude a, {
    required bool continuous,
    required double threshold,
    required double pauseSeconds,
  }) {
    final db = a.current.isFinite ? a.current : -60.0;
    final normalized = ((db + 60) / 60).clamp(0.0, 1.0);
    final level = normalized * 10;
    final above = level >= threshold;

    soundLevel = level;
    speakingNow = above;
    onChanged();

    if (!continuous || !listening) return;

    final now = DateTime.now();
    if (above) {
      _hadSpeech = true;
      _firstSpeechAt ??= now;
      _lastSpeechAt = now;
      return;
    }
    if (!_hadSpeech) return;
    final last = _lastSpeechAt ?? _recordStartedAt ?? now;
    final silentMs = now.difference(last).inMilliseconds;
    final pauseMs = (pauseSeconds * 1000).round();
    if (silentMs >= pauseMs) onAutoCut();
  }

  Future<void> dispose() async {
    _disposed = true;
    _maxListenTimer?.cancel();
    await _ampSub?.cancel();
    await _recorder.dispose();
  }
}
