import 'package:ai_chat/settings.dart';
import 'package:ai_chat/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'load falls back when persisted voice mode or scenes are invalid',
    () async {
      SharedPreferences.setMockInitialValues({
        'voice_mode': 999,
        'scenes_v1': 'not json',
      });

      final settings = AppSettings();
      await settings.load();

      expect(settings.voiceMode, VoiceMode.pushToTalk);
      expect(settings.scenes, isNotEmpty);
      expect(settings.activeSceneId, settings.scenes.first.id);
    },
  );

  test('STT and TTS toggles restore the previous provider and model', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = AppSettings();
    await settings.load();

    final sttProvider = providersFor(Capability.stt).first;
    final sttModel = sttProvider.modelsFor(Capability.stt).last.id;
    final ttsProvider = providersFor(Capability.tts).first;
    final ttsModel = ttsProvider.modelsFor(Capability.tts).last.id;

    await settings.setSttProvider(sttProvider.id);
    await settings.setSttModel(sttModel);
    await settings.setTtsProvider(ttsProvider.id);
    await settings.setTtsModel(ttsModel);

    await settings.setSttEnabled(false);
    await settings.setTtsEnabled(false);

    expect(settings.sttProviderId, isNull);
    expect(settings.sttModelId, sttModel);
    expect(settings.ttsProviderId, isNull);
    expect(settings.ttsModelId, ttsModel);

    await settings.setSttEnabled(true);
    await settings.setTtsEnabled(true);

    expect(settings.sttProviderId, sttProvider.id);
    expect(settings.sttModelId, sttModel);
    expect(settings.ttsProviderId, ttsProvider.id);
    expect(settings.ttsModelId, ttsModel);
  });

  test(
    'correction is enabled by default for existing routing behavior',
    () async {
      SharedPreferences.setMockInitialValues({});

      final settings = AppSettings();
      await settings.load();

      expect(settings.correctionEnabled, isTrue);
    },
  );
}
