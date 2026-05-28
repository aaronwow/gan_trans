import 'package:ai_chat/chat_screen.dart';
import 'package:ai_chat/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppSettings> loadSettings() async {
    SharedPreferences.setMockInitialValues({
      'stt_provider_id': '',
      'tts_provider_id': '',
    });
    final settings = AppSettings();
    await settings.load();
    return settings;
  }

  testWidgets('top controls expose tooltips', (tester) async {
    final settings = await loadSettings();

    await tester.pumpWidget(MaterialApp(home: ChatScreen(settings: settings)));

    expect(find.byTooltip('图片翻译'), findsOneWidget);
    expect(find.byTooltip('模型与语音快调'), findsOneWidget);
    expect(find.byTooltip('清空对话'), findsOneWidget);
  });

  testWidgets('language dialog warns when both languages are the same', (
    tester,
  ) async {
    final settings = await loadSettings();
    await settings.setTranslationLangA('中文');
    await settings.setTranslationLangB('中文');

    await tester.pumpWidget(MaterialApp(home: ChatScreen(settings: settings)));

    await tester.tap(find.text('中文 ↔ 中文'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('请选择两个不同的语言。'), findsOneWidget);
  });

  testWidgets('empty text send uses clipboard text', (tester) async {
    final settings = await loadSettings();

    await tester.pumpWidget(MaterialApp(home: ChatScreen(settings: settings)));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': '从剪贴板发送'};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('从剪贴板发送'), findsOneWidget);
  });
}
