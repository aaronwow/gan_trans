import 'package:ai_chat/settings.dart';
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
}
