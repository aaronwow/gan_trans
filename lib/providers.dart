import 'dart:convert';
import 'package:http/http.dart' as http;

import 'catalog.dart';

/// Optional audio attachment on a [ChatMessage] (user role only). The runtime
/// re-encodes this into the dialect-specific request shape (Gemini's
/// `inline_data` part, OpenAI's `input_audio` content block).
class ChatAudio {
  final List<int> bytes;
  final String format; // 'wav' | 'mp3' | 'aac' | etc.
  const ChatAudio({required this.bytes, required this.format});

  String get mimeType {
    switch (format.toLowerCase()) {
      case 'mp3':
        return 'audio/mp3';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      case 'aiff':
        return 'audio/aiff';
      case 'wav':
      default:
        return 'audio/wav';
    }
  }
}

class ChatMessage {
  final String role;
  final String content;
  final ChatAudio? audio; // attached audio; only meaningful on 'user' messages
  ChatMessage(this.role, this.content, {this.audio});
}

/// Dispatches a chat request to the wire format described by [dialect].
class ChatClient {
  final ApiDialect dialect;
  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client? client;
  final Duration timeout;

  ChatClient({
    required this.dialect,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.client,
    this.timeout = const Duration(seconds: 10),
  });

  Future<String> send(List<ChatMessage> history) async {
    final c = client ?? http.Client();
    final owned = client == null;
    try {
      switch (dialect) {
        case ApiDialect.openaiChat:
          return await _sendOpenAi(history, c);
        case ApiDialect.geminiChat:
          return await _sendGemini(history, c);
        default:
          throw StateError('ChatClient: unsupported dialect $dialect');
      }
    } finally {
      if (owned) c.close();
    }
  }

  Future<String> _sendOpenAi(List<ChatMessage> history, http.Client c) async {
    final messages = history.map((m) {
      if (m.audio == null) {
        return {'role': m.role, 'content': m.content};
      }
      // Multipart user message: text + input_audio.
      return {
        'role': m.role,
        'content': [
          if (m.content.isNotEmpty) {'type': 'text', 'text': m.content},
          {
            'type': 'input_audio',
            'input_audio': {
              'data': base64Encode(m.audio!.bytes),
              'format': m.audio!.format,
            },
          },
        ],
      };
    }).toList();
    final payload = {'model': model, 'messages': messages};
    final resp = await c
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    final bodyStr = utf8.decode(resp.bodyBytes);
    if (resp.statusCode >= 400) {
      throw Exception('Chat ${resp.statusCode}: $bodyStr');
    }
    final data = jsonDecode(bodyStr) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Chat: empty choices: $bodyStr');
    }
    final msg = choices.first['message'] as Map<String, dynamic>;
    // gpt-4o-audio-preview returns a string in 'content', or in some configs
    // an 'audio' object; we only consume text here.
    final c1 = msg['content'];
    if (c1 is String) return c1;
    if (c1 is List) {
      final parts = c1.whereType<Map>().map((e) => e['text'] ?? '').join();
      if (parts.isNotEmpty) return parts;
    }
    final audioField = msg['audio'];
    if (audioField is Map && audioField['transcript'] is String) {
      return audioField['transcript'] as String;
    }
    throw Exception('Chat: empty response: ${resp.body}');
  }

  Future<String> _sendGemini(List<ChatMessage> history, http.Client c) async {
    final contents = history.where((m) => m.role != 'system').map((m) {
      final parts = <Map<String, dynamic>>[];
      if (m.content.isNotEmpty) parts.add({'text': m.content});
      if (m.audio != null) {
        parts.add({
          'inline_data': {
            'mime_type': m.audio!.mimeType,
            'data': base64Encode(m.audio!.bytes),
          },
        });
      }
      return {
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': parts,
      };
    }).toList();
    final systemMsg = history.where((m) => m.role == 'system').toList();
    final body = <String, dynamic>{'contents': contents};
    if (systemMsg.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemMsg.map((m) => m.content).join('\n')}
        ]
      };
    }
    final resp = await c
        .post(
          Uri.parse('$baseUrl/models/$model:generateContent?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final bodyStr = utf8.decode(resp.bodyBytes);
    if (resp.statusCode >= 400) {
      throw Exception('Gemini ${resp.statusCode}: $bodyStr');
    }
    final data = jsonDecode(bodyStr) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    final promptFeedback = data['promptFeedback'];
    if (candidates == null || candidates.isEmpty) {
      // Prompt-level block (e.g. safety on the input audio) carries no
      // candidates — the reason lives in promptFeedback.blockReason.
      if (promptFeedback is Map && promptFeedback['blockReason'] != null) {
        throw Exception(
            'Gemini blocked the prompt: ${promptFeedback['blockReason']} '
            '(safetyRatings=${promptFeedback['safetyRatings']})');
      }
      throw Exception('Gemini: empty response: $bodyStr');
    }
    final cand = candidates.first as Map<String, dynamic>;
    final content = cand['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) {
      // No parts — usually means finishReason is SAFETY / RECITATION /
      // PROHIBITED_CONTENT / MAX_TOKENS / OTHER. Surface it explicitly so the
      // UI shows a real error instead of a Null cast crash.
      final reason = cand['finishReason'];
      throw Exception(
          'Gemini returned no content (finishReason=$reason, '
          'safetyRatings=${cand['safetyRatings']}, '
          'promptFeedback=$promptFeedback)');
    }
    return parts.map((p) => p['text'] ?? '').join();
  }
}
