import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/catalog.dart';
import 'package:ai_chat/stt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Google exposes Gemini STT and TTS models', () {
    final google = findProvider('google')!;

    expect(google.dialects[Capability.stt], ApiDialect.geminiChat);
    expect(google.dialects[Capability.tts], ApiDialect.geminiSpeech);

    final stt = google.findModel('gemini-3.1-flash-lite-preview')!;
    expect(stt.supports(Capability.chat), isTrue);
    expect(stt.supports(Capability.stt), isTrue);
    expect(stt.acceptsAudio(), isTrue);

    final tts = google.findModel('gemini-3.1-flash-tts-preview')!;
    expect(tts.supports(Capability.tts), isTrue);
    expect(tts.voices.map((v) => v.id), contains('Kore'));
  });

  test('Gemini STT prompts chat models to transcribe only', () async {
    final audio = await File(
      '${Directory.systemTemp.path}/gemini-stt.wav',
    ).writeAsBytes([1, 2, 3]);
    late Map<String, dynamic> payload;

    final client = MockClient((request) async {
      payload = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'hello world'},
                ],
              },
            },
          ],
        }),
        200,
      );
    });

    final text = await SttService().transcribe(
      filePath: audio.path,
      format: 'wav',
      request: const SttRequest(
        dialect: ApiDialect.geminiChat,
        modelId: 'gemini-3.1-flash-lite-preview',
        creds: {CredentialField.apiKey: 'key'},
      ),
      client: client,
    );

    expect(text, 'hello world');
    final parts = (payload['contents'] as List).first['parts'] as List<dynamic>;
    expect(parts.first['text'], contains('Return only the spoken words'));
    expect(parts.first['text'], contains('no answer'));
    expect(parts.last['inline_data']['mime_type'], 'audio/wav');

    await audio.delete();
  });
}
