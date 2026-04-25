import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'catalog.dart';

const _openAiUrl = 'https://api.openai.com/v1/audio/transcriptions';
const _volcFlashUrl =
    'https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash';

/// Aggregates everything an STT call needs. Built by AppSettings from the
/// catalog so callers don't reach into provider-specific config.
class SttRequest {
  final ApiDialect dialect;
  final String modelId;
  final Map<CredentialField, String> creds;

  const SttRequest({
    required this.dialect,
    required this.modelId,
    required this.creds,
  });
}

class SttService {
  /// Transcribe the audio at [filePath]. Audio language is auto-detected.
  Future<String> transcribe({
    required String filePath,
    required String format,
    required SttRequest request,
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final c = client ?? http.Client();
    final owned = client == null;
    try {
      switch (request.dialect) {
        case ApiDialect.openaiTranscribe:
          return await _openAi(filePath, request, c, timeout);
        case ApiDialect.volcSttFlash:
          return await _volcFlash(filePath, format, request, c, timeout);
        default:
          throw StateError('SttService: unsupported dialect ${request.dialect}');
      }
    } finally {
      if (owned) c.close();
    }
  }

  Future<String> _openAi(String filePath, SttRequest req, http.Client client,
      Duration timeout) async {
    final apiKey = req.creds[CredentialField.apiKey] ?? '';
    if (apiKey.isEmpty) {
      throw StateError('OpenAI API key is not set.');
    }
    final r = http.MultipartRequest('POST', Uri.parse(_openAiUrl))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = req.modelId
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await client.send(r).timeout(timeout);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw HttpException('OpenAI STT failed: ${streamed.statusCode} $body');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    return (data['text'] as String? ?? '').trim();
  }

  Future<String> _volcFlash(String filePath, String format, SttRequest req,
      http.Client client, Duration timeout) async {
    final appKey = req.creds[CredentialField.appKey] ?? '';
    final accessKey = req.creds[CredentialField.accessKey] ?? '';
    if (appKey.isEmpty || accessKey.isEmpty) {
      throw StateError('Volcengine AppKey / AccessKey is not set.');
    }
    final bytes = await File(filePath).readAsBytes();
    final b64 = base64Encode(bytes);
    final reqId = const Uuid().v4();
    final payload = <String, dynamic>{
      'user': {'uid': appKey},
      'audio': {'data': b64, 'format': format},
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
        'X-Api-App-Key': appKey,
        'X-Api-Access-Key': accessKey,
        'X-Api-Resource-Id': req.modelId,
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
