import 'dart:convert';

import 'package:ai_chat/catalog.dart';
import 'package:ai_chat/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (_) async => null,
    );
  });

  test('replays cached audio for the same TTS request', () async {
    var calls = 0;
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      calls++;
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response.bytes([1, 2, 3], 200);
    });
    final tts = TtsService(playAudio: (_, _) async {});
    addTearDown(tts.dispose);

    const req = TtsRequest(
      dialect: ApiDialect.openaiSpeech,
      baseUrl: 'https://relay.example.com/v1',
      modelId: 'tts-1',
      voice: 'alloy',
      creds: {CredentialField.apiKey: 'test-key'},
    );

    await tts.speak(text: 'hello', request: req, client: client);
    await tts.speak(text: 'hello', request: req, client: client);

    expect(calls, 1);
    expect(bodies.single['model'], 'tts-1');
  });

  test('switching TTS model bypasses the cached audio', () async {
    var calls = 0;
    final models = <String>[];
    final client = MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      models.add(body['model'] as String);
      return http.Response.bytes([4, 5, 6], 200);
    });
    final tts = TtsService(playAudio: (_, _) async {});
    addTearDown(tts.dispose);

    const baseReq = TtsRequest(
      dialect: ApiDialect.openaiSpeech,
      baseUrl: 'https://relay.example.com/v1',
      modelId: 'tts-1',
      voice: 'alloy',
      creds: {CredentialField.apiKey: 'test-key'},
    );
    const switchedReq = TtsRequest(
      dialect: ApiDialect.openaiSpeech,
      baseUrl: 'https://relay.example.com/v1',
      modelId: 'tts-1-hd',
      voice: 'alloy',
      creds: {CredentialField.apiKey: 'test-key'},
    );

    await tts.speak(text: 'hello', request: baseReq, client: client);
    await tts.speak(text: 'hello', request: switchedReq, client: client);

    expect(calls, 2);
    expect(models, ['tts-1', 'tts-1-hd']);
  });

  test('Gemini TTS over OpenAI speech requests PCM and plays WAV', () async {
    late Map<String, dynamic> body;
    Uint8List? played;
    String? mimeType;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response.bytes([1, 0, 2, 0], 200);
    });
    final tts = TtsService(
      playAudio: (bytes, mime) async {
        played = bytes;
        mimeType = mime;
      },
    );
    addTearDown(tts.dispose);

    const req = TtsRequest(
      dialect: ApiDialect.openaiSpeech,
      baseUrl: 'https://openrouter.ai/api/v1',
      modelId: 'google/gemini-3.1-flash-tts-preview',
      voice: 'Kore',
      creds: {CredentialField.apiKey: 'test-key'},
    );

    await tts.speak(text: 'hello', request: req, client: client);

    expect(body['response_format'], 'pcm');
    expect(mimeType, 'audio/wav');
    expect(played, isNotNull);
    expect(String.fromCharCodes(played!.take(4)), 'RIFF');
    expect(played!.length, 48);
  });
}
