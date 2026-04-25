import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

enum SttProvider { openai, volcFlash, off }

/// OpenAI audio transcription endpoint. Accepts multipart upload.
const _openAiUrl = 'https://api.openai.com/v1/audio/transcriptions';

/// Volcengine "极速版录音文件识别" (Flash) — one-shot recognize endpoint.
/// Ported from auc-web/backend/main.go:handleFlash.
const _volcFlashUrl =
    'https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash';

/// Default Volcengine resource id for the Flash/turbo ASR service.
const kVolcFlashResourceId = 'volc.bigasr.auc_turbo';

/// Volcengine 录音文件识别 (one-shot recognize) resource id options.
/// Mirrors the options exposed in auc-web/frontend/src/App.tsx.
const kVolcSttResourceIds = <({String value, String label})>[
  (value: 'volc.bigasr.auc_turbo', label: 'volc.bigasr.auc_turbo (豆包急速版)'),
  (value: 'volc.bigasr.auc', label: 'volc.bigasr.auc (豆包录音文件识别 1.0)'),
  (value: 'volc.seedasr.auc', label: 'volc.seedasr.auc (豆包录音文件识别 2.0)'),
];

/// Recommended OpenAI STT models (whisper + gpt-4o family).
const kOpenAiSttModels = <String>[
  'gpt-4o-mini-transcribe',
  'gpt-4o-transcribe',
  'whisper-1',
];

class SttConfig {
  final SttProvider provider;
  // OpenAI
  final String openAiKey;
  final String openAiModel;
  // Volcengine
  final String volcAppKey;
  final String volcAccessKey;
  final String volcResourceId;

  const SttConfig({
    required this.provider,
    this.openAiKey = '',
    this.openAiModel = 'gpt-4o-mini-transcribe',
    this.volcAppKey = '',
    this.volcAccessKey = '',
    this.volcResourceId = kVolcFlashResourceId,
  });
}

class SttService {
  /// Transcribe the audio at [filePath]. The audio language is auto-detected
  /// by the model — no locale is passed. Pass [client] to enable cancellation
  /// (close the client to abort the in-flight request).
  Future<String> transcribe({
    required String filePath,
    required String format,
    required SttConfig config,
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final c = client ?? http.Client();
    final owned = client == null;
    try {
      switch (config.provider) {
        case SttProvider.off:
          throw StateError('STT is off.');
        case SttProvider.openai:
          return await _openAi(filePath, format, config, c, timeout);
        case SttProvider.volcFlash:
          return await _volcFlash(filePath, format, config, c, timeout);
      }
    } finally {
      if (owned) c.close();
    }
  }

  Future<String> _openAi(String filePath, String format, SttConfig config,
      http.Client client, Duration timeout) async {
    if (config.openAiKey.isEmpty) {
      throw StateError('OpenAI API key is not set.');
    }
    final req = http.MultipartRequest('POST', Uri.parse(_openAiUrl))
      ..headers['Authorization'] = 'Bearer ${config.openAiKey}'
      ..fields['model'] = config.openAiModel
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await client.send(req).timeout(timeout);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw HttpException(
          'OpenAI STT failed: ${streamed.statusCode} $body');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    return (data['text'] as String? ?? '').trim();
  }

  Future<String> _volcFlash(String filePath, String format, SttConfig config,
      http.Client client, Duration timeout) async {
    if (config.volcAppKey.isEmpty || config.volcAccessKey.isEmpty) {
      throw StateError('Volcengine AppKey / AccessKey is not set.');
    }
    final bytes = await File(filePath).readAsBytes();
    final b64 = base64Encode(bytes);
    final reqId = const Uuid().v4();
    final payload = <String, dynamic>{
      'user': {'uid': config.volcAppKey},
      'audio': {
        'data': b64,
        'format': format,
      },
      'request': {
        'model_name': 'bigmodel',
        'enable_itn': true,
        'enable_punc': true,
        'show_utterances': true,
      },
    };

    final resp = await client.post(
      Uri.parse(_volcFlashUrl),
      headers: {
        'Content-Type': 'application/json',
        'X-Api-App-Key': config.volcAppKey,
        'X-Api-Access-Key': config.volcAccessKey,
        'X-Api-Resource-Id':
            config.volcResourceId.isEmpty ? kVolcFlashResourceId : config.volcResourceId,
        'X-Api-Request-Id': reqId,
        'X-Api-Sequence': '-1',
      },
      body: jsonEncode(payload),
    ).timeout(timeout);

    final status = resp.headers['x-api-status-code'] ?? '';
    final message = resp.headers['x-api-message'] ?? '';
    if (status != '20000000') {
      throw HttpException(
          'Volcengine Flash STT failed: code=$status message=$message body=${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>?;
    final text = (result?['text'] as String?) ?? '';
    return text.trim();
  }
}
