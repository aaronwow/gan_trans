import 'dart:convert';
import 'package:http/http.dart' as http;

enum ProviderKind { openai, gemini }

class AiProvider {
  final ProviderKind kind;
  final String name;
  final String baseUrl;
  final List<String> suggestedModels;

  const AiProvider({
    required this.kind,
    required this.name,
    required this.baseUrl,
    required this.suggestedModels,
  });
}

const kProviders = <AiProvider>[
  AiProvider(
    kind: ProviderKind.openai,
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    suggestedModels: [
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4-turbo',
      'gpt-3.5-turbo',
      'o1',
      'o1-mini',
    ],
  ),
  AiProvider(
    kind: ProviderKind.gemini,
    name: 'Gemini (Google)',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    suggestedModels: [
      'gemini-3-flash-preview',
      'gemini-flash-latest',
      'gemini-2.5-pro',
      'gemini-2.5-flash',
      'gemini-2.0-flash',
      'gemini-2.0-flash-lite',
      'gemini-1.5-pro',
      'gemini-1.5-flash',
    ],
  ),
];

AiProvider providerOf(ProviderKind k) =>
    kProviders.firstWhere((p) => p.kind == k);

class ChatMessage {
  final String role;
  final String content;
  ChatMessage(this.role, this.content);

  Map<String, dynamic> toOpenAiJson() => {'role': role, 'content': content};
}

class ChatClient {
  final AiProvider provider;
  final String apiKey;
  final String model;
  final http.Client? client;
  final Duration timeout;

  ChatClient({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.client,
    this.timeout = const Duration(seconds: 10),
  });

  Future<String> send(List<ChatMessage> history) async {
    final c = client ?? http.Client();
    final owned = client == null;
    try {
      switch (provider.kind) {
        case ProviderKind.openai:
          return await _sendOpenAi(history, c);
        case ProviderKind.gemini:
          return await _sendGemini(history, c);
      }
    } finally {
      if (owned) c.close();
    }
  }

  Future<String> _sendOpenAi(List<ChatMessage> history, http.Client c) async {
    final payload = {
      'model': model,
      'messages': history.map((m) => m.toOpenAiJson()).toList(),
    };
    final body = jsonEncode(payload);
    final resp = await c.post(
      Uri.parse('${provider.baseUrl}/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    ).timeout(timeout);
    if (resp.statusCode >= 400) {
      throw Exception('OpenAI ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return data['choices'][0]['message']['content'] as String;
  }

  Future<String> _sendGemini(List<ChatMessage> history, http.Client c) async {
    final contents = history
        .where((m) => m.role != 'system')
        .map((m) => {
              'role': m.role == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': m.content}
              ],
            })
        .toList();
    final systemMsg = history.where((m) => m.role == 'system').toList();
    final body = <String, dynamic>{'contents': contents};
    if (systemMsg.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemMsg.map((m) => m.content).join('\n')}
        ]
      };
    }
    final encoded = jsonEncode(body);
    final resp = await c.post(
      Uri.parse('${provider.baseUrl}/models/$model:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: encoded,
    ).timeout(timeout);
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
