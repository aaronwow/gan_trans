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
    if (resp.statusCode >= 400) {
      throw Exception('Chat ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final msg = data['choices'][0]['message'] as Map<String, dynamic>;
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
    if (resp.statusCode >= 400) {
      throw Exception('Gemini ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini: empty response: ${resp.body}');
    }
    final parts = candidates.first['content']['parts'] as List;
    return parts.map((p) => p['text'] ?? '').join();
  }
}
