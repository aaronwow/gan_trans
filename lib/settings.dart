import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers.dart';
import 'scenes.dart';
import 'stt_service.dart';
import 'tts_service.dart';

enum VoiceMode { pushToTalk, continuous }

const kTranslationLanguages = <String>[
  '中文',
  '英语',
  '印尼语',
  '日语',
  '韩语',
  '西班牙语',
  '法语',
  '德语',
  '意大利语',
  '葡萄牙语',
  '俄语',
  '阿拉伯语',
  '泰语',
  '越南语',
];


class AppSettings extends ChangeNotifier {
  static const _kOpenAiKey = 'openai_api_key';
  static const _kGeminiKey = 'gemini_api_key';
  static const _kProvider = 'selected_provider';
  static const _kModel = 'selected_model';
  static const _kVoiceMode = 'voice_mode';
  static const _kTtsMode = 'tts_mode';
  static const _kTtsAutoSpeak = 'tts_auto_speak';
  static const _kTtsOpenAiModel = 'tts_openai_model';
  static const _kTtsOpenAiVoice = 'tts_openai_voice';
  static const _kTtsVolcSpeaker = 'tts_volc_speaker';
  static const _kTtsVolcSpeechRate = 'tts_volc_speech_rate';
  static const _kTtsVolcResourceId = 'tts_volc_resource_id';
  static const _kScenes = 'scenes_v1';
  static const _kActiveScene = 'active_scene';
  static const _kCorrectionEnabled = 'correction_enabled';
  static const _kTranslationEnabled = 'translation_enabled';
  static const _kTranslationLangA = 'translation_lang_a';
  static const _kTranslationLangB = 'translation_lang_b';
  static const _kTranslationProvider = 'translation_provider';
  static const _kTranslationModel = 'translation_model';
  static const _kSttProvider = 'stt_provider';
  static const _kSttOpenAiModel = 'stt_openai_model';
  static const _kVolcAppKey = 'volc_app_key';
  static const _kVolcAccessKey = 'volc_access_key';
  static const _kVolcResourceId = 'volc_resource_id';
  static const _kVadPause = 'vad_pause_seconds';
  static const _kVadListen = 'vad_listen_seconds';
  static const _kVadThreshold = 'vad_threshold_level';
  static const _kMinRecordSeconds = 'min_record_seconds';
  static const _kSttTimeout = 'stt_timeout_seconds';
  static const _kLlmTimeout = 'llm_timeout_seconds';
  static const _kTtsTimeout = 'tts_timeout_seconds';
  static const _kHistoryContextCount = 'history_context_count';

  String openAiKey = '';
  String geminiKey = '';
  ProviderKind provider = ProviderKind.openai;
  String model = 'gpt-4o-mini';
  VoiceMode voiceMode = VoiceMode.pushToTalk;
  TtsMode ttsMode = TtsMode.off;
  bool ttsAutoSpeak = true;
  String ttsOpenAiModel = 'gpt-4o-mini-tts';
  String ttsOpenAiVoice = 'alloy';
  String ttsVolcSpeaker = 'zh_female_vv_uranus_bigtts';
  int ttsVolcSpeechRate = 0;
  String ttsVolcResourceId = kDoubaoTtsResourceId;

  List<Scene> scenes = [];
  String activeSceneId = kDefaultSceneId;
  bool correctionEnabled = false;
  bool translationEnabled = false;
  String translationLangA = '中文';
  String translationLangB = '印尼语';
  ProviderKind translationProvider = ProviderKind.gemini;
  String translationModel = 'gemini-3-flash-preview';
  SttProvider sttProvider = SttProvider.openai;
  String sttOpenAiModel = 'gpt-4o-mini-transcribe';
  String volcAppKey = '';
  String volcAccessKey = '';
  String volcResourceId = kVolcFlashResourceId;
  double vadPauseSeconds = 2.0;
  int vadListenSeconds = 60;
  double vadThresholdLevel = 2.0;
  double minRecordSeconds = 0.5;
  int sttTimeoutSeconds = 10;
  int llmTimeoutSeconds = 10;
  int ttsTimeoutSeconds = 10;
  int historyContextCount = 3;

  Scene get activeScene =>
      scenes.firstWhere((s) => s.id == activeSceneId, orElse: () => scenes.first);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    openAiKey = p.getString(_kOpenAiKey) ?? '';
    geminiKey = p.getString(_kGeminiKey) ?? '';
    provider = ProviderKind.values[p.getInt(_kProvider) ?? 0];
    model = p.getString(_kModel) ?? 'gpt-4o-mini';
    voiceMode = VoiceMode.values[p.getInt(_kVoiceMode) ?? 0];
    final ttsIdx = p.getInt(_kTtsMode) ?? 0;
    ttsMode = ttsIdx >= 0 && ttsIdx < TtsMode.values.length
        ? TtsMode.values[ttsIdx]
        : TtsMode.off;
    ttsAutoSpeak = p.getBool(_kTtsAutoSpeak) ?? true;
    ttsOpenAiModel = p.getString(_kTtsOpenAiModel) ?? 'gpt-4o-mini-tts';
    ttsOpenAiVoice = p.getString(_kTtsOpenAiVoice) ?? 'alloy';
    ttsVolcSpeaker =
        p.getString(_kTtsVolcSpeaker) ?? 'zh_female_vv_uranus_bigtts';
    ttsVolcSpeechRate = p.getInt(_kTtsVolcSpeechRate) ?? 0;
    ttsVolcResourceId =
        p.getString(_kTtsVolcResourceId) ?? kDoubaoTtsResourceId;

    final rawScenes = p.getString(_kScenes);
    scenes = rawScenes != null ? decodeScenes(rawScenes) : defaultScenes();
    if (scenes.isEmpty) scenes = defaultScenes();
    activeSceneId = p.getString(_kActiveScene) ?? scenes.first.id;
    if (!scenes.any((s) => s.id == activeSceneId)) {
      activeSceneId = scenes.first.id;
    }
    correctionEnabled = p.getBool(_kCorrectionEnabled) ?? false;
    translationEnabled = p.getBool(_kTranslationEnabled) ?? false;
    translationLangA = p.getString(_kTranslationLangA) ?? '中文';
    translationLangB = p.getString(_kTranslationLangB) ?? '印尼语';
    final tpIdx = p.getInt(_kTranslationProvider) ?? ProviderKind.gemini.index;
    translationProvider = tpIdx >= 0 && tpIdx < ProviderKind.values.length
        ? ProviderKind.values[tpIdx]
        : ProviderKind.gemini;
    translationModel =
        p.getString(_kTranslationModel) ?? 'gemini-3-flash-preview';
    sttProvider = SttProvider.values[p.getInt(_kSttProvider) ?? 0];
    sttOpenAiModel =
        p.getString(_kSttOpenAiModel) ?? 'gpt-4o-mini-transcribe';
    volcAppKey = p.getString(_kVolcAppKey) ?? '';
    volcAccessKey = p.getString(_kVolcAccessKey) ?? '';
    volcResourceId = p.getString(_kVolcResourceId) ?? kVolcFlashResourceId;
    // Migrate from legacy int key.
    final vp = p.get(_kVadPause);
    vadPauseSeconds = vp is double ? vp : (vp is int ? vp.toDouble() : 2.0);
    vadListenSeconds = p.getInt(_kVadListen) ?? 60;
    vadThresholdLevel = p.getDouble(_kVadThreshold) ?? 2.0;
    minRecordSeconds = p.getDouble(_kMinRecordSeconds) ?? 0.5;
    sttTimeoutSeconds = p.getInt(_kSttTimeout) ?? 10;
    llmTimeoutSeconds = p.getInt(_kLlmTimeout) ?? 10;
    ttsTimeoutSeconds = p.getInt(_kTtsTimeout) ?? 10;
    historyContextCount = p.getInt(_kHistoryContextCount) ?? 3;
    notifyListeners();
  }

  Future<void> setMinRecordSeconds(double v) async {
    final clamped = v < 0.1 ? 0.1 : v;
    minRecordSeconds = clamped;
    await (await _prefs).setDouble(_kMinRecordSeconds, clamped);
    notifyListeners();
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> setOpenAiKey(String v) async {
    openAiKey = v;
    await (await _prefs).setString(_kOpenAiKey, v);
    notifyListeners();
  }

  Future<void> setGeminiKey(String v) async {
    geminiKey = v;
    await (await _prefs).setString(_kGeminiKey, v);
    notifyListeners();
  }

  Future<void> setProvider(ProviderKind v) async {
    provider = v;
    await (await _prefs).setInt(_kProvider, v.index);
    notifyListeners();
  }

  Future<void> setModel(String v) async {
    model = v;
    await (await _prefs).setString(_kModel, v);
    notifyListeners();
  }

  Future<void> setVoiceMode(VoiceMode v) async {
    voiceMode = v;
    await (await _prefs).setInt(_kVoiceMode, v.index);
    notifyListeners();
  }

  String apiKeyForCurrentProvider() =>
      provider == ProviderKind.openai ? openAiKey : geminiKey;

  Future<void> setTtsMode(TtsMode v) async {
    ttsMode = v;
    await (await _prefs).setInt(_kTtsMode, v.index);
    notifyListeners();
  }

  Future<void> setTtsAutoSpeak(bool v) async {
    ttsAutoSpeak = v;
    await (await _prefs).setBool(_kTtsAutoSpeak, v);
    notifyListeners();
  }

  Future<void> setTtsOpenAiModel(String v) async {
    ttsOpenAiModel = v;
    await (await _prefs).setString(_kTtsOpenAiModel, v);
    notifyListeners();
  }

  Future<void> setTtsOpenAiVoice(String v) async {
    ttsOpenAiVoice = v;
    await (await _prefs).setString(_kTtsOpenAiVoice, v);
    notifyListeners();
  }

  Future<void> setTtsVolcSpeaker(String v) async {
    ttsVolcSpeaker = v;
    await (await _prefs).setString(_kTtsVolcSpeaker, v);
    notifyListeners();
  }

  Future<void> setTtsVolcSpeechRate(int v) async {
    ttsVolcSpeechRate = v;
    await (await _prefs).setInt(_kTtsVolcSpeechRate, v);
    notifyListeners();
  }

  Future<void> setTtsVolcResourceId(String v) async {
    ttsVolcResourceId = v;
    await (await _prefs).setString(_kTtsVolcResourceId, v);
    notifyListeners();
  }

  Future<void> setActiveScene(String id) async {
    activeSceneId = id;
    await (await _prefs).setString(_kActiveScene, id);
    notifyListeners();
  }

  Future<void> saveScenes() async {
    await (await _prefs).setString(_kScenes, encodeScenes(scenes));
    notifyListeners();
  }

  Future<void> addScene(Scene s) async {
    scenes.add(s);
    await saveScenes();
  }

  Future<void> updateScene(Scene s) async {
    final i = scenes.indexWhere((e) => e.id == s.id);
    if (i >= 0) scenes[i] = s;
    await saveScenes();
  }

  Future<void> removeScene(String id) async {
    if (scenes.length <= 1) return;
    scenes.removeWhere((s) => s.id == id);
    if (activeSceneId == id) activeSceneId = scenes.first.id;
    await saveScenes();
    await (await _prefs).setString(_kActiveScene, activeSceneId);
  }

  Future<void> setCorrectionEnabled(bool v) async {
    correctionEnabled = v;
    await (await _prefs).setBool(_kCorrectionEnabled, v);
    notifyListeners();
  }

  Future<void> setTranslationEnabled(bool v) async {
    translationEnabled = v;
    await (await _prefs).setBool(_kTranslationEnabled, v);
    notifyListeners();
  }

  Future<void> setTranslationLangA(String v) async {
    translationLangA = v;
    await (await _prefs).setString(_kTranslationLangA, v);
    notifyListeners();
  }

  Future<void> setTranslationLangB(String v) async {
    translationLangB = v;
    await (await _prefs).setString(_kTranslationLangB, v);
    notifyListeners();
  }

  Future<void> setTranslationProvider(ProviderKind v) async {
    translationProvider = v;
    await (await _prefs).setInt(_kTranslationProvider, v.index);
    notifyListeners();
  }

  Future<void> setTranslationModel(String v) async {
    translationModel = v;
    await (await _prefs).setString(_kTranslationModel, v);
    notifyListeners();
  }

  String translationApiKey() =>
      translationProvider == ProviderKind.openai ? openAiKey : geminiKey;

  Future<void> setSttProvider(SttProvider v) async {
    sttProvider = v;
    await (await _prefs).setInt(_kSttProvider, v.index);
    notifyListeners();
  }

  Future<void> setSttOpenAiModel(String v) async {
    sttOpenAiModel = v;
    await (await _prefs).setString(_kSttOpenAiModel, v);
    notifyListeners();
  }

  Future<void> setVolcAppKey(String v) async {
    volcAppKey = v;
    await (await _prefs).setString(_kVolcAppKey, v);
    notifyListeners();
  }

  Future<void> setVolcAccessKey(String v) async {
    volcAccessKey = v;
    await (await _prefs).setString(_kVolcAccessKey, v);
    notifyListeners();
  }

  Future<void> setVolcResourceId(String v) async {
    volcResourceId = v;
    await (await _prefs).setString(_kVolcResourceId, v);
    notifyListeners();
  }

  SttConfig sttConfig() => SttConfig(
        provider: sttProvider,
        openAiKey: openAiKey,
        openAiModel: sttOpenAiModel,
        volcAppKey: volcAppKey,
        volcAccessKey: volcAccessKey,
        volcResourceId: volcResourceId,
      );

  Future<void> setVadPause(double v) async {
    final clamped = v < 0.1 ? 0.1 : v;
    vadPauseSeconds = clamped;
    await (await _prefs).setDouble(_kVadPause, clamped);
    notifyListeners();
  }

  Future<void> setVadListen(int v) async {
    vadListenSeconds = v;
    await (await _prefs).setInt(_kVadListen, v);
    notifyListeners();
  }

  Future<void> setSttTimeout(int v) async {
    sttTimeoutSeconds = v.clamp(1, 120);
    await (await _prefs).setInt(_kSttTimeout, sttTimeoutSeconds);
    notifyListeners();
  }

  Future<void> setLlmTimeout(int v) async {
    llmTimeoutSeconds = v.clamp(1, 120);
    await (await _prefs).setInt(_kLlmTimeout, llmTimeoutSeconds);
    notifyListeners();
  }

  Future<void> setTtsTimeout(int v) async {
    ttsTimeoutSeconds = v.clamp(1, 120);
    await (await _prefs).setInt(_kTtsTimeout, ttsTimeoutSeconds);
    notifyListeners();
  }

  Future<void> setHistoryContextCount(int v) async {
    historyContextCount = v.clamp(0, 10);
    await (await _prefs).setInt(_kHistoryContextCount, historyContextCount);
    notifyListeners();
  }

  Future<void> setVadThresholdLevel(double v) async {
    final clamped = v.clamp(0.0, 10.0);
    vadThresholdLevel = clamped;
    await (await _prefs).setDouble(_kVadThreshold, clamped);
    notifyListeners();
  }

  /// Mirrors auc-web/frontend/src/components/utils.ts:buildPipelineGeminiPrompt.
  /// The user input is always STT output; the model corrects it with the
  /// scene context and, when translation is enabled, translates between the
  /// two configured languages.
  String composedSystemPrompt() {
    final a = translationLangA.trim().isEmpty ? '中文' : translationLangA.trim();
    final b = translationLangB.trim().isEmpty ? '印尼语' : translationLangB.trim();
    final sceneText = activeScene.prompt.trim();
    final scene = sceneText.isEmpty ? '' : '$sceneText。';
    if (translationEnabled) {
      return '用户输入的文字是STT转换的结果，$scene如果输入是$a，翻译成$b；如果输入是$b，翻译成$a。只输出修正翻译后的文字。';
    }
    return '用户输入的文字是STT转换的结果，$scene只输出修正后的文字。';
  }
}
