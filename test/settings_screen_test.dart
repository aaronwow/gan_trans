import 'package:ai_chat/catalog.dart';
import 'package:ai_chat/settings.dart';
import 'package:ai_chat/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppSettings> loadSettings(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final settings = AppSettings();
    await settings.load();
    return settings;
  }

  testWidgets('shows OpenRouter quick start when no chat provider has a key', (
    tester,
  ) async {
    final settings = await loadSettings({});

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );

    expect(find.text('快速开始：OpenRouter'), findsOneWidget);
    expect(find.text('OpenRouter 密钥'), findsOneWidget);
  });

  testWidgets('hides quick start when a chat provider key already exists', (
    tester,
  ) async {
    final settings = await loadSettings({
      'cred__openrouter__${CredentialField.apiKey.name}': 'sk-or-test',
    });

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );

    expect(find.text('快速开始：OpenRouter'), findsNothing);
  });

  testWidgets('credential paste button saves clipboard text', (tester) async {
    final settings = await loadSettings({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'sk-or-test'};
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

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );

    await tester.tap(find.byTooltip('从剪贴板粘贴').first);
    await tester.pump();

    expect(
      settings.credential('openrouter', CredentialField.apiKey),
      'sk-or-test',
    );
  });
}
