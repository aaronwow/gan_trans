import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/catalog.dart';
import 'package:ai_chat/stt_service.dart';
import 'package:ai_chat/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Google exposes the current Gemini STT-capable models', () {
    final google = findProvider('google')!;

    expect(google.dialects[Capability.stt], ApiDialect.geminiChat);
    expect(google.dialects[Capability.tts], isNull);

    for (final modelId in [
      'gemini-3-flash-preview',
      'gemini-3.5-flash',
      'gemini-3.1-flash-lite',
      'gemini-flash-lite-latest',
    ]) {
      final model = google.findModel(modelId)!;
      expect(model.supports(Capability.chat), isTrue, reason: modelId);
      expect(model.supports(Capability.stt), isTrue, reason: modelId);
      expect(model.acceptsAudio(), isTrue, reason: modelId);
      expect(model.canTranslateAudioDirect, isTrue, reason: modelId);
      expect(model.sttTransport, SttTransport.batchUpload, reason: modelId);
    }
  });

  test('OpenRouter Gemini chat models expose direct audio translation', () {
    final openrouter = findProvider('openrouter')!;

    for (final modelId in [
      'google/gemini-3-flash-preview',
      'google/gemini-3.5-flash',
      'google/gemini-3.1-flash-lite',
    ]) {
      final model = openrouter.findModel(modelId)!;
      expect(model.supports(Capability.chat), isTrue, reason: modelId);
      expect(model.acceptsAudio(), isTrue, reason: modelId);
      expect(model.canTranslateAudioDirect, isTrue, reason: modelId);
    }
  });

  test('xAI Grok Voice TTS is available directly and via OpenRouter', () {
    final xai = findProvider('xai')!;
    expect(xai.dialects[Capability.tts], ApiDialect.xaiSpeech);
    final direct = xai.findModel('grok-voice-tts-1.0')!;
    expect(direct.supports(Capability.tts), isTrue);
    expect(direct.voices.map((v) => v.id), containsAll(['eve', 'ara', 'rex']));

    final openrouter = findProvider('openrouter')!;
    expect(openrouter.dialects[Capability.tts], ApiDialect.openaiSpeech);
    final routed = openrouter.findModel('x-ai/grok-voice-tts-1.0')!;
    expect(routed.supports(Capability.tts), isTrue);
    expect(routed.voices.map((v) => v.id), containsAll(['eve', 'sal', 'leo']));
  });

  test('xAI TTS uses the official text and voice_id payload', () {
    final payload = xaiSpeechPayload(text: 'hello', voice: 'ara');

    expect(payload['text'], 'hello');
    expect(payload['voice_id'], 'ara');
    expect(payload['language'], 'auto');
    expect(payload['output_format']['codec'], 'mp3');
    expect(xaiSpeechPayload(text: 'hello', voice: '')['voice_id'], 'eve');
  });

  test('ElevenLabs exposes batch STT and TTS models only', () {
    final elevenlabs = findProvider('elevenlabs')!;

    expect(elevenlabs.dialects[Capability.stt], ApiDialect.elevenlabsScribe);
    expect(elevenlabs.dialects[Capability.tts], ApiDialect.elevenlabsSpeech);

    expect(elevenlabs.findModel('scribe_v2')!.supports(Capability.stt), isTrue);
    expect(
      elevenlabs.findModel('scribe_v2')!.sttTransport,
      SttTransport.batchUpload,
    );
    expect(elevenlabs.findModel('scribe_v2_realtime'), isNull);

    for (final modelId in [
      'eleven_flash_v2_5',
      'eleven_flash_v2',
      'eleven_turbo_v2_5',
      'eleven_turbo_v2',
      'eleven_multilingual_v2',
      'eleven_v3',
    ]) {
      final model = elevenlabs.findModel(modelId)!;
      expect(model.supports(Capability.tts), isTrue);
      expect(model.voices.map((v) => v.id), contains('JBFqnCBsd6RMkjVDRZzb'));
    }
  });

  test(
    'Realtime-only STT providers are hidden until streaming is implemented',
    () {
      final soniox = findProvider('soniox')!;

      expect(
        soniox.findModel('stt-async-v4')!.supports(Capability.stt),
        isTrue,
      );
      expect(
        soniox.findModel('stt-async-v4')!.sttTransport,
        SttTransport.asyncJob,
      );
      expect(soniox.findModel('stt-rt-v4'), isNull);
      expect(findProvider('speechmatics'), isNull);
    },
  );

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
        modelId: 'gemini-3.1-flash-lite',
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
