import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart';

const _openAiSpeechUrl = 'https://api.openai.com/v1/audio/speech';
const _elevenlabsBaseUrl = 'https://api.elevenlabs.io/v1';
const _geminiUrl = 'https://generativelanguage.googleapis.com/v1beta';
const _doubaoTtsUrl =
    'https://openspeech.bytedance.com/api/v3/tts/unidirectional';

class TtsRequest {
  final ApiDialect dialect;
  final String baseUrl;
  final String modelId;
  final String voice;
  final Map<CredentialField, String> creds;
  final int volcSpeechRate;

  const TtsRequest({
    required this.dialect,
    this.baseUrl = '',
    required this.modelId,
    required this.voice,
    required this.creds,
    this.volcSpeechRate = 0,
  });
}

class _TtsAudio {
  final Uint8List bytes;
  final String mimeType;

  const _TtsAudio(this.bytes, this.mimeType);
}

class _TtsCacheKey {
  final String text;
  final ApiDialect dialect;
  final String baseUrl;
  final String modelId;
  final String voice;
  final int volcSpeechRate;

  const _TtsCacheKey({
    required this.text,
    required this.dialect,
    required this.baseUrl,
    required this.modelId,
    required this.voice,
    required this.volcSpeechRate,
  });

  factory _TtsCacheKey.from(String text, TtsRequest request) => _TtsCacheKey(
    text: text,
    dialect: request.dialect,
    baseUrl: request.baseUrl.replaceAll(RegExp(r'/+$'), ''),
    modelId: request.modelId,
    voice: request.voice,
    volcSpeechRate: request.volcSpeechRate,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TtsCacheKey &&
          text == other.text &&
          dialect == other.dialect &&
          baseUrl == other.baseUrl &&
          modelId == other.modelId &&
          voice == other.voice &&
          volcSpeechRate == other.volcSpeechRate;

  @override
  int get hashCode =>
      Object.hash(text, dialect, baseUrl, modelId, voice, volcSpeechRate);
}

Map<String, dynamic> xaiSpeechPayload({
  required String text,
  required String voice,
}) {
  return {
    'text': text,
    'voice_id': voice.isEmpty ? 'eve' : voice,
    'language': 'auto',
    'output_format': {'codec': 'mp3', 'sample_rate': 24000, 'bit_rate': 128000},
  };
}

bool openAiSpeechModelRequiresPcm(String modelId) {
  final normalized = modelId.toLowerCase();
  return normalized.contains('gemini') &&
      normalized.contains('tts') &&
      normalized.contains('preview');
}

class TtsService {
  static const int _maxCachedAudio = 24;

  final AudioPlayer _player = AudioPlayer();
  final Future<void> Function(Uint8List bytes, String mimeType)? _playAudio;
  final Map<_TtsCacheKey, _TtsAudio> _audioCache = {};
  final Map<_TtsCacheKey, Future<_TtsAudio>> _inFlight = {};

  final _playingController = StreamController<bool>.broadcast();
  Stream<bool> get playingStream => _playingController.stream;
  bool _playing = false;
  bool _disposed = false;
  bool get isPlaying => _playing;

  TtsService({
    @visibleForTesting
    Future<void> Function(Uint8List bytes, String mimeType)? playAudio,
  }) : _playAudio = playAudio {
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
      final audio = await _audioFor(
        text: text,
        request: request,
        client: c,
        timeout: timeout,
      );
      await _playAudioBytes(audio.bytes, audio.mimeType);
    } finally {
      if (owned) c.close();
    }
  }

  Future<void> _playAudioBytes(Uint8List bytes, String mimeType) {
    final override = _playAudio;
    if (override != null) return override(bytes, mimeType);
    return _player.play(BytesSource(bytes, mimeType: mimeType));
  }

  Future<_TtsAudio> _audioFor({
    required String text,
    required TtsRequest request,
    required http.Client client,
    required Duration timeout,
  }) async {
    final key = _TtsCacheKey.from(text, request);
    final cached = _audioCache[key];
    if (cached != null) return cached;

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _fetchAudio(text, request, client, timeout);
    _inFlight[key] = future;
    try {
      final audio = await future;
      _rememberAudio(key, audio);
      return audio;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<_TtsAudio> _fetchAudio(
    String text,
    TtsRequest request,
    http.Client client,
    Duration timeout,
  ) async {
    switch (request.dialect) {
      case ApiDialect.geminiSpeech:
        return _fetchGeminiAudio(text, request, client, timeout);
      case ApiDialect.openaiSpeech:
        return _fetchOpenAiAudio(text, request, client, timeout);
      case ApiDialect.xaiSpeech:
        return _fetchXAiAudio(text, request, client, timeout);
      case ApiDialect.elevenlabsSpeech:
        return _fetchElevenLabsAudio(text, request, client, timeout);
      case ApiDialect.volcTtsDoubao:
        return _fetchDoubaoAudio(text, request, client, timeout);
      default:
        throw StateError('TtsService: unsupported dialect ${request.dialect}');
    }
  }

  void _rememberAudio(_TtsCacheKey key, _TtsAudio audio) {
    if (_disposed) return;
    _audioCache.remove(key);
    _audioCache[key] = audio;
    while (_audioCache.length > _maxCachedAudio) {
      _audioCache.remove(_audioCache.keys.first);
    }
  }

  Future<_TtsAudio> _fetchOpenAiAudio(
    String text,
    TtsRequest req,
    http.Client client,
    Duration timeout,
  ) async {
    final apiKey = req.creds[CredentialField.apiKey] ?? '';
    if (apiKey.isEmpty) {
      throw Exception('API key is empty — set it in Settings.');
    }
    final endpoint = req.baseUrl.trim().isEmpty
        ? _openAiSpeechUrl
        : '${req.baseUrl.replaceAll(RegExp(r'/+$'), '')}/audio/speech';
    final requiresPcm = openAiSpeechModelRequiresPcm(req.modelId);
    final resp = await client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': req.modelId,
            'voice': req.voice,
            'input': text,
            'response_format': requiresPcm ? 'pcm' : 'mp3',
          }),
        )
        .timeout(timeout);
    if (resp.statusCode >= 400) {
      throw Exception('OpenAI TTS ${resp.statusCode}: ${resp.body}');
    }
    final contentType = resp.headers['content-type'] ?? '';
    if (requiresPcm && !contentType.toLowerCase().contains('wav')) {
      return _TtsAudio(
        _wavFromPcm16(resp.bodyBytes, sampleRate: 24000, channels: 1),
        'audio/wav',
      );
    }
    return _TtsAudio(
      Uint8List.fromList(resp.bodyBytes),
      contentType.isEmpty ? 'audio/mpeg' : contentType,
    );
  }

  Future<_TtsAudio> _fetchXAiAudio(
    String text,
    TtsRequest req,
    http.Client client,
    Duration timeout,
  ) async {
    final apiKey = req.creds[CredentialField.apiKey] ?? '';
    if (apiKey.isEmpty) {
      throw Exception('xAI API key is empty — set it in Settings.');
    }
    final endpoint = '${req.baseUrl.replaceAll(RegExp(r'/+$'), '')}/tts';
    final resp = await client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(xaiSpeechPayload(text: text, voice: req.voice)),
        )
        .timeout(timeout);
    if (resp.statusCode >= 400) {
      throw Exception('xAI TTS ${resp.statusCode}: ${resp.body}');
    }
    return _TtsAudio(
      Uint8List.fromList(resp.bodyBytes),
      resp.headers['content-type'] ?? 'audio/mpeg',
    );
  }

  Future<_TtsAudio> _fetchElevenLabsAudio(
    String text,
    TtsRequest req,
    http.Client client,
    Duration timeout,
  ) async {
    final apiKey = req.creds[CredentialField.apiKey] ?? '';
    if (apiKey.isEmpty) {
      throw Exception('ElevenLabs API key is empty — set it in Settings.');
    }
    if (req.voice.isEmpty) {
      throw Exception(
        'ElevenLabs voice is empty — choose a voice in Settings.',
      );
    }
    final resp = await client
        .post(
          Uri.parse(
            '$_elevenlabsBaseUrl/text-to-speech/${req.voice}'
            '?output_format=mp3_44100_128',
          ),
          headers: {'Content-Type': 'application/json', 'xi-api-key': apiKey},
          body: jsonEncode({'text': text, 'model_id': req.modelId}),
        )
        .timeout(timeout);
    if (resp.statusCode >= 400) {
      throw Exception('ElevenLabs TTS ${resp.statusCode}: ${resp.body}');
    }
    return _TtsAudio(Uint8List.fromList(resp.bodyBytes), 'audio/mpeg');
  }

  Future<_TtsAudio> _fetchGeminiAudio(
    String text,
    TtsRequest req,
    http.Client client,
    Duration timeout,
  ) async {
    final apiKey = req.creds[CredentialField.apiKey] ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Google API key is empty — set it in Settings.');
    }
    final voice = req.voice.isEmpty ? 'Kore' : req.voice;
    final payload = <String, dynamic>{
      'contents': [
        {
          'parts': [
            {
              'text':
                  'Read the following text aloud exactly as written:\n$text',
            },
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': voice},
          },
        },
      },
      'model': req.modelId,
    };

    final resp = await client
        .post(
          Uri.parse(
            '$_geminiUrl/models/${req.modelId}:generateContent?key=$apiKey',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    final bodyStr = utf8.decode(resp.bodyBytes);
    if (resp.statusCode >= 400) {
      throw Exception('Gemini TTS ${resp.statusCode}: $bodyStr');
    }
    final data = jsonDecode(bodyStr) as Map<String, dynamic>;
    final audioB64 = _extractGeminiAudio(data);
    if (audioB64 == null || audioB64.isEmpty) {
      throw Exception('Gemini TTS: no audio data returned: $bodyStr');
    }
    final pcm = base64Decode(audioB64);
    final wav = _wavFromPcm16(pcm, sampleRate: 24000, channels: 1);
    return _TtsAudio(wav, 'audio/wav');
  }

  Future<_TtsAudio> _fetchDoubaoAudio(
    String text,
    TtsRequest req,
    http.Client client,
    Duration timeout,
  ) async {
    final appKey = req.creds[CredentialField.appKey] ?? '';
    final accessKey = req.creds[CredentialField.accessKey] ?? '';
    if (appKey.isEmpty || accessKey.isEmpty) {
      throw Exception(
        'Volcengine AppKey/AccessKey missing — set them in Settings.',
      );
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
      '[TTS → Doubao] POST $_doubaoTtsUrl speaker=${req.voice} rate=${req.volcSpeechRate}',
    );
    final resp = await client
        .post(
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
        )
        .timeout(timeout);
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
    return _TtsAudio(Uint8List.fromList(chunks), 'audio/mpeg');
  }

  String? _extractGeminiAudio(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final cand = candidates.first as Map<String, dynamic>;
    final content = cand['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) return null;
    for (final part in parts.whereType<Map>()) {
      final inline = part['inlineData'] ?? part['inline_data'];
      if (inline is Map && inline['data'] is String) {
        return inline['data'] as String;
      }
    }
    return null;
  }

  Uint8List _wavFromPcm16(
    List<int> pcm, {
    required int sampleRate,
    required int channels,
  }) {
    const sampleWidth = 2;
    final byteRate = sampleRate * channels * sampleWidth;
    final blockAlign = channels * sampleWidth;
    final out = Uint8List(44 + pcm.length);
    final data = ByteData.view(out.buffer);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        out[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + pcm.length, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, sampleWidth * 8, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, pcm.length, Endian.little);
    out.setRange(44, out.length, pcm);
    return out;
  }

  void dispose() {
    _disposed = true;
    _audioCache.clear();
    _inFlight.clear();
    _playingController.close();
    _player.dispose();
  }
}
