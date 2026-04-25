import 'package:ai_chat/chat_turn.dart';
import 'package:ai_chat/settings.dart';
import 'package:ai_chat/stt_service.dart';
import 'package:ai_chat/tts_service.dart';
import 'package:ai_chat/voice_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recentContextBefore returns bounded prior outputs', () {
    final settings = AppSettings()..historyContextCount = 2;
    final runner = VoicePipelineRunner(
      settings: settings,
      stt: SttService(),
      tts: TtsService(),
    );
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
}
