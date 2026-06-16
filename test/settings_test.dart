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

  test('relay base URL is empty on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = AppSettings();
    await settings.load();

    expect(settings.relayBaseUrl, isEmpty);
    expect(settings.relayProvider, isNull);
  });

  test('fresh install uses response limit defaults', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = AppSettings();
    await settings.load();

    expect(settings.llmTimeoutSeconds, 15);
    expect(settings.historyContextCount, 0);
  });

  test('fresh install defaults chat to OpenRouter', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = AppSettings();
    await settings.load();

    expect(settings.chatProviderId, 'openrouter');
    expect(settings.findProvider(settings.chatProviderId)?.name, 'OpenRouter');
    expect(settings.chatModelId, 'google/gemini-3.1-flash-lite');
    expect(settings.audioDirectChat, isTrue);
    expect(settings.audioDirectIncludeTranscript, isTrue);
    expect(settings.audioDirectActive, isTrue);
  });

  test('fresh install defaults TTS to OpenRouter Grok', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = AppSettings();
    await settings.load();

    expect(settings.ttsProviderId, 'openrouter');
    expect(settings.ttsModelId, 'x-ai/grok-voice-tts-1.0');
    expect(settings.ttsVoice, isNotEmpty);
  });

  test('correction and translation are always enabled', () async {
    SharedPreferences.setMockInitialValues({
      'correction_enabled': false,
      'translation_enabled': false,
    });

    final settings = AppSettings();
    await settings.load();

    expect(settings.correctionEnabled, isTrue);
    expect(settings.translationEnabled, isTrue);

    await settings.setCorrectionEnabled(false);
    await settings.setTranslationEnabled(false);

    expect(settings.correctionEnabled, isTrue);
    expect(settings.translationEnabled, isTrue);
  });
}
