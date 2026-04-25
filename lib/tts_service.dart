import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart';

const _openAiSpeechUrl = 'https://api.openai.com/v1/audio/speech';
const _doubaoTtsUrl =
    'https://openspeech.bytedance.com/api/v3/tts/unidirectional';

class TtsRequest {
  final ApiDialect dialect;
  final String modelId;
  final String voice;
  final Map<CredentialField, String> creds;
  final int volcSpeechRate;

  const TtsRequest({
    required this.dialect,
    required this.modelId,
    required this.voice,
    required this.creds,
    this.volcSpeechRate = 0,
  });
}

class TtsService {
  final AudioPlayer _player = AudioPlayer();

  final _playingController = StreamController<bool>.broadcast();
  Stream<bool> get playingStream => _playingController.stream;
  bool _playing = false;
  bool get isPlaying => _playing;

  TtsService() {
    _player.onPlayerStateChanged.listen((st) {
      if (st == PlayerState.playing) {
        _setPlaying(true);
      } else if (st == PlayerState.stopped ||
          st == PlayerState.completed ||
          st == PlayerState.paused) {
        _setPlaying(false);
      }
    });
  }

  void _setPlaying(bool v) {
    if (_playing == v) return;
    _playing = v;
    _playingController.add(v);
  }

  Future<void> stop() async {
    await _player.stop();
    _setPlaying(false);
  }

  Future<void> waitForIdle() async {
    if (!_playing) return;
    await _playingController.stream.firstWhere((p) => !p);
  }

  Future<void> speak({
    required String text,
    required TtsRequest request,
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (text.trim().isEmpty) return;
    await stop();
    final c = client ?? http.Client();
    final owned = client == null;
    try {
      switch (request.dialect) {
        case ApiDialect.openaiSpeech:
          await _speakOpenAi(text, request, c, timeout);
          return;
        case ApiDialect.volcTtsDoubao:
          await _speakDoubao(text, request, c, timeout);
          return;
        default:
          throw StateError('TtsService: unsupported dialect ${request.dialect}');
      }
    } finally {
      if (owned) c.close();
    }
  }

  Future<void> _speakOpenAi(String text, TtsRequest req, http.Client client,
      Duration timeout) async {
    final apiKey = req.creds[CredentialField.apiKey] ?? '';
    if (apiKey.isEmpty) {
      throw Exception('OpenAI API key is empty — set it in Settings.');
    }
    final resp = await client.post(
      Uri.parse(_openAiSpeechUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': req.modelId,
        'voice': req.voice,
        'input': text,
        'response_format': 'mp3',
      }),
    ).timeout(timeout);
    if (resp.statusCode >= 400) {
      throw Exception('OpenAI TTS ${resp.statusCode}: ${resp.body}');
    }
    await _player.play(
      BytesSource(Uint8List.fromList(resp.bodyBytes), mimeType: 'audio/mpeg'),
    );
  }

  Future<void> _speakDoubao(String text, TtsRequest req, http.Client client,
      Duration timeout) async {
    final appKey = req.creds[CredentialField.appKey] ?? '';
    final accessKey = req.creds[CredentialField.accessKey] ?? '';
    if (appKey.isEmpty || accessKey.isEmpty) {
      throw Exception(
          'Volcengine AppKey/AccessKey missing — set them in Settings.');
    }
    final payload = <String, dynamic>{
      'user': {'uid': appKey},
      'req_params': {
        'text': text,
        'speaker': req.voice,
        'audio_params': {
          'format': 'mp3',
          'sample_rate': 24000,
          'speech_rate': req.volcSpeechRate,
        },
        'additions': '{"disable_markdown_filter":true}',
      },
    };
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    debugPrint(
        '[TTS → Doubao] POST $_doubaoTtsUrl speaker=${req.voice} rate=${req.volcSpeechRate}');
    final resp = await client.post(
      Uri.parse(_doubaoTtsUrl),
      headers: {
        'Content-Type': 'application/json',
        'Connection': 'keep-alive',
        'X-Api-App-Id': appKey,
        'X-Api-Access-Key': accessKey,
        'X-Api-Resource-Id': req.modelId,
        'X-Api-Request-Id': requestId,
      },
      body: jsonEncode(payload),
    ).timeout(timeout);
    if (resp.statusCode >= 400) {
      throw Exception('Doubao TTS ${resp.statusCode}: ${resp.body}');
    }
    final chunks = <int>[];
    for (final line in LineSplitter.split(resp.body)) {
      if (line.trim().isEmpty) continue;
      final Map<String, dynamic> obj;
      try {
        obj = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final code = obj['code'] as int? ?? 0;
      if (code == 20000000) break;
      if (code != 0) {
        throw Exception('Doubao TTS error code=$code ${obj['message'] ?? ''}');
      }
      final data = obj['data'] as String?;
      if (data != null && data.isNotEmpty) {
        chunks.addAll(base64.decode(data));
      }
    }
    if (chunks.isEmpty) {
      throw Exception('Doubao TTS: no audio data returned');
    }
    await _player.play(
      BytesSource(Uint8List.fromList(chunks), mimeType: 'audio/mpeg'),
    );
  }

  void dispose() {
    _playingController.close();
    _player.dispose();
  }
}
