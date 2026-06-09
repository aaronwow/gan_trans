import 'package:ai_chat/chat_turn.dart';
import 'package:ai_chat/settings.dart';
import 'package:ai_chat/stt_markers.dart';
import 'package:ai_chat/stt_service.dart';
import 'package:ai_chat/tts_service.dart';
import 'package:ai_chat/voice_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (_) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (_) async => null,
  );

  test('recentContextBefore returns bounded prior outputs', () {
    final settings = AppSettings()..historyContextCount = 2;
    final tts = TtsService();
    final runner = VoicePipelineRunner(
      settings: settings,
      stt: SttService(),
      tts: tts,
    );
    addTearDown(tts.dispose);
    final turns = [
      ChatTurn(id: 1, generation: 0, audioPath: null)
        ..userText = 'first input'
        ..assistantText = 'first output',
      ChatTurn(id: 2, generation: 0, audioPath: null)
        ..userText = 'second input',
      ChatTurn(id: 3, generation: 0, audioPath: null)
        ..userText = 'third input'
        ..assistantText = 'third output',
      ChatTurn(id: 4, generation: 0, audioPath: null),
    ];

    expect(runner.recentContextBefore(turns.last, turns), [
      'second input',
      'third output',
    ]);
  });

  test('non-speech STT markers are detected only when standalone', () {
    expect(isNonSpeechSttMarker('[silence]'), isTrue);
    expect(isNonSpeechSttMarker('[breath] [noise]'), isTrue);
    expect(isNonSpeechSttMarker(' [laughter]\n'), isTrue);

    expect(isNonSpeechSttMarker(''), isFalse);
    expect(isNonSpeechSttMarker('hello [silence]'), isFalse);
    expect(isNonSpeechSttMarker('[silence] hello'), isFalse);
    expect(isNonSpeechSttMarker('hello'), isFalse);
  });
}
