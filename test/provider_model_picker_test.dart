import 'package:ai_chat/catalog.dart';
import 'package:ai_chat/provider_model_picker.dart';
import 'package:ai_chat/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows missing credential notice for selected provider', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    await settings.load();
    await settings.setChatProvider('openai');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProviderModelPicker(
            settings: settings,
            cap: Capability.chat,
            providerId: settings.chatProviderId,
            modelId: settings.chatModelId,
            allowOff: false,
            onProvider: (_) {},
            onModel: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('缺少 OpenAI 凭证'), findsOneWidget);
  });
}
