import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'prompt_composer.dart';
import 'relay_catalog.dart';
import 'scenes.dart';
import 'stt_service.dart';
import 'tts_service.dart';

/// Voice modes:
/// - [pushToTalk]: hold a button to record, release to send.
/// - [continuous]: VAD-driven loop. The duplex behaviour inside this mode is
///   controlled by [AppSettings.continuousFullDuplex] — half-duplex by
///   default (mic mutes during processing + playback).
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
  '老挝语',
];

class AppSettings extends ChangeNotifier {
  // ---- New unified keys ----
  // Per-provider credentials: cred__<providerId>__<fieldName>
  static String _credKey(String providerId, CredentialField f) =>
      'cred__${providerId}__${f.name}';

  static const _kRelayBaseUrl = 'relay_base_url';
  static const _kRelayCatalogJson = 'relay_catalog_json';
  static const _kRelayCatalogFetchedAt = 'relay_catalog_fetched_at';

  static const _kChatProvider = 'chat_provider_id';
  static const _kChatModel = 'chat_model_id';
  static const _kSttProviderId = 'stt_provider_id'; // empty / null = off
  static const _kSttModelId = 'stt_model_id';
  static const _kLastSttProviderId = 'last_stt_provider_id';
  static const _kTtsProviderId = 'tts_provider_id'; // empty / null = off
  static const _kTtsModelId = 'tts_model_id';
  static const _kLastTtsProviderId = 'last_tts_provider_id';
  static const _kTtsVoice = 'tts_voice';
  // Image translation routing. Null/empty means: fall back to the chat model
  // (only valid when that model itself accepts image input).
  static const _kImageProviderId = 'image_provider_id';
  static const _kImageModelId = 'image_model_id';
  static const _kTtsAutoSpeak = 'tts_auto_speak';
  static const _kTtsVolcSpeechRate = 'tts_volc_speech_rate';

  // Other (unchanged)
  static const _kVoiceMode = 'voice_mode';
  static const _kScenes = 'scenes_v1';
  static const _kActiveScene = 'active_scene';
  static const _kCorrectionEnabled = 'correction_enabled';
  static const _kTranslationEnabled = 'translation_enabled';
  static const _kTranslationLangA = 'translation_lang_a';
  static const _kTranslationLangB = 'translation_lang_b';
  static const _kVadPause = 'vad_pause_seconds';
  static const _kVadListen = 'vad_listen_seconds';
  static const _kVadThreshold = 'vad_threshold_level';
  static const _kMinRecordSeconds = 'min_record_seconds';
  static const _kSttTimeout = 'stt_timeout_seconds';
  static const _kLlmTimeout = 'llm_timeout_seconds';
  static const _kTtsTimeout = 'tts_timeout_seconds';
  static const _kHistoryContextCount = 'history_context_count';
  static const _kAecEnabled = 'aec_enabled';
  static const _kContinuousFullDuplex = 'continuous_full_duplex';
  static const _kAudioDirectChat = 'audio_direct_chat';
  static const _kAudioDirectIncludeTranscript =
      'audio_direct_include_transcript';
  static const _kIncludeScenePrompt = 'include_scene_prompt';

  // Legacy keys (read-only, used for one-time migration on first load).
  static const _legacyOpenAiKey = 'openai_api_key';
  static const _legacyGeminiKey = 'gemini_api_key';
  static const _legacyVolcAppKey = 'volc_app_key';
  static const _legacyVolcAccessKey = 'volc_access_key';
  static const _legacyVolcResourceId = 'volc_resource_id';
  static const _legacyProvider = 'selected_provider';
  static const _legacyModel = 'selected_model';
  static const _legacyTtsMode = 'tts_mode';
  static const _legacyTtsOpenAiModel = 'tts_openai_model';
  static const _legacyTtsOpenAiVoice = 'tts_openai_voice';
  static const _legacyTtsVolcSpeaker = 'tts_volc_speaker';
  static const _legacyTtsVolcResourceId = 'tts_volc_resource_id';
  static const _legacySttProvider = 'stt_provider';
  static const _legacySttOpenAiModel = 'stt_openai_model';

  // ---- Per-provider credentials ----
  /// providerId → (CredentialField → value)
  final Map<String, Map<CredentialField, String>> _credentials = {};

  ProviderSpec? _relayProvider;
  String relayBaseUrl = '';
  String? relayCatalogError;
  DateTime? relayCatalogFetchedAt;

  ProviderSpec? get relayProvider => _relayProvider;

  List<ProviderSpec> get catalog => [...kCatalog, ?_relayProvider];

  ProviderSpec? findProvider(String? id) {
    if (id == null) return null;
    if (id == kRelayProviderId) return _relayProvider;
    for (final p in kCatalog) {
      if (p.id == id) return p;
    }
    return null;
  }

  Iterable<ProviderSpec> providersFor(Capability c) =>
      catalog.where((p) => p.hasCapability(c));

  Map<CredentialField, String> credentialsFor(String providerId) =>
      _credentials[providerId] ?? const {};

  String credential(String providerId, CredentialField f) =>
      _credentials[providerId]?[f] ?? '';

  /// True when every credential field declared by the provider has a non-empty
  /// value. Pickers gate selection on this so users can't accidentally route
  /// to a provider that's guaranteed to fail at the wire.
  bool hasCredentials(String providerId) {
    final p = findProvider(providerId);
    if (p == null) return false;
    if (p.credentials.isEmpty) return true;
    return p.credentials.every(
      (f) => credential(providerId, f).trim().isNotEmpty,
    );
  }

  // ---- Selected provider/model per capability ----
  String? chatProviderId;
  String chatModelId = '';
  String? sttProviderId; // null = off
  String? _lastSttProviderId;
  String sttModelId = '';
  String? ttsProviderId; // null = off
  String? _lastTtsProviderId;
  String ttsModelId = '';
  String ttsVoice = '';
  bool ttsAutoSpeak = true;
  int ttsVolcSpeechRate = 0;

  /// Optional override for image input requests. When null, image messages go
  /// to the chat model (which must itself accept images).
  String? imageProviderId;
  String imageModelId = '';

  // ---- Other settings ----
  VoiceMode voiceMode = VoiceMode.pushToTalk;
  List<Scene> scenes = [];
  String activeSceneId = kDefaultSceneId;
  bool correctionEnabled = true;
  bool translationEnabled = true;
  String translationLangA = '中文';
  String translationLangB = '印尼语';
  double vadPauseSeconds = 2.0;
  int vadListenSeconds = 60;
  double vadThresholdLevel = 2.0;
  double minRecordSeconds = 0.5;
  int sttTimeoutSeconds = 10;
  int llmTimeoutSeconds = 10;
  int ttsTimeoutSeconds = 10;
  int historyContextCount = 3;
  bool aecEnabled = true;

  /// Inside continuous mode: when true the mic stays open during TTS playback
  /// (full-duplex). Default is false → half-duplex.
  bool continuousFullDuplex = false;

  /// When true and the selected chat model accepts audio input, skip STT and
  /// send the recording straight to the chat model. The chat model returns
  /// the corrected/translated text in one round-trip.
  bool audioDirectChat = false;

  /// In audio-direct mode: ask the model to return JSON with both the original
  /// audio transcript and the corrected/translated output. The transcript
  /// renders in the user bubble (like a normal STT result); the output goes
  /// to the assistant bubble. Off → assistant bubble carries the output and
  /// the user bubble shows a generic mic placeholder.
  bool audioDirectIncludeTranscript = false;

  /// When true (default), the active scene's prompt is injected into the chat
  /// system prompt. Affects both text-mode and audio-direct chat. STT and TTS
  /// are unaffected (scene prompt has no place there).
  bool includeScenePrompt = true;

  Scene get activeScene => scenes.firstWhere(
    (s) => s.id == activeSceneId,
    orElse: () => scenes.first,
  );

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();

    relayBaseUrl = normalizeRelayBaseUrl(p.getString(_kRelayBaseUrl) ?? '');
    final relayJson = p.getString(_kRelayCatalogJson);
    if (relayBaseUrl.isEmpty) {
      relayCatalogFetchedAt = null;
    } else {
      final fetchedAtMillis = p.getInt(_kRelayCatalogFetchedAt);
      relayCatalogFetchedAt = fetchedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis);
    }
    if (relayBaseUrl.isNotEmpty &&
        relayJson != null &&
        relayJson.trim().isNotEmpty) {
      try {
        _relayProvider = relayProviderFromJson(
          relayBaseUrl,
          jsonDecode(relayJson),
        );
        relayCatalogError = null;
      } catch (e) {
        _relayProvider = null;
        relayCatalogError = 'Cached relay catalog is invalid: $e';
      }
    }

    // Load credentials for every catalog provider, falling back to legacy keys.
    for (final provider in kCatalog) {
      final m = <CredentialField, String>{};
      for (final f in provider.credentials) {
        final newVal = p.getString(_credKey(provider.id, f));
        m[f] = newVal ?? _legacyCredential(p, provider.id, f);
      }
      _credentials[provider.id] = m;
    }
    _credentials[kRelayProviderId] = {
      CredentialField.apiKey:
          p.getString(_credKey(kRelayProviderId, CredentialField.apiKey)) ?? '',
    };

    // Chat provider/model — fall back to legacy enum (0=openai, 1=gemini).
    chatProviderId =
        p.getString(_kChatProvider) ?? _legacyChatProviderId(p) ?? 'google';
    chatModelId =
        p.getString(_kChatModel) ??
        p.getString(_legacyModel) ??
        _firstModelId(chatProviderId!, Capability.chat) ??
        '';
    _ensureValid(Capability.chat);

    // STT provider/model — legacy enum 0=openai, 1=volcFlash, 2=off.
    if (p.containsKey(_kSttProviderId)) {
      final v = p.getString(_kSttProviderId);
      sttProviderId = (v == null || v.isEmpty) ? null : v;
    } else {
      sttProviderId = _legacySttProviderId(p);
    }
    final lastStt = p.getString(_kLastSttProviderId);
    _lastSttProviderId = (lastStt == null || lastStt.isEmpty)
        ? sttProviderId
        : lastStt;
    sttModelId = p.getString(_kSttModelId) ?? '';
    if (sttProviderId != null) {
      sttModelId =
          (sttModelId.isEmpty ? null : sttModelId) ??
          _legacySttModelId(p, sttProviderId!) ??
          _firstModelId(sttProviderId!, Capability.stt) ??
          '';
    }
    _ensureValid(Capability.stt);

    // TTS provider/model — legacy enum 0=off, 1=openai, 2=volcDoubao.
    if (p.containsKey(_kTtsProviderId)) {
      final v = p.getString(_kTtsProviderId);
      ttsProviderId = (v == null || v.isEmpty) ? null : v;
    } else {
      ttsProviderId = _legacyTtsProviderId(p);
    }
    final lastTts = p.getString(_kLastTtsProviderId);
    _lastTtsProviderId = (lastTts == null || lastTts.isEmpty)
        ? ttsProviderId
        : lastTts;
    ttsModelId = p.getString(_kTtsModelId) ?? '';
    ttsVoice = p.getString(_kTtsVoice) ?? '';
    if (ttsProviderId != null) {
      ttsModelId =
          (ttsModelId.isEmpty ? null : ttsModelId) ??
          _legacyTtsModelId(p, ttsProviderId!) ??
          _firstModelId(ttsProviderId!, Capability.tts) ??
          '';
      ttsVoice =
          (ttsVoice.isEmpty ? null : ttsVoice) ??
          _legacyTtsVoiceValue(p, ttsProviderId!) ??
          _firstVoice(ttsProviderId!, ttsModelId) ??
          '';
    }
    _ensureValid(Capability.tts);

    ttsAutoSpeak = p.getBool(_kTtsAutoSpeak) ?? true;
    ttsVolcSpeechRate = p.getInt(_kTtsVolcSpeechRate) ?? 0;

    final imgPid = p.getString(_kImageProviderId);
    imageProviderId = (imgPid == null || imgPid.isEmpty) ? null : imgPid;
    imageModelId = p.getString(_kImageModelId) ?? '';
    _ensureImageValid();

    voiceMode = _voiceModeFromIndex(p.getInt(_kVoiceMode));

    final rawScenes = p.getString(_kScenes);
    scenes = _decodeScenesOrDefault(rawScenes);
    if (scenes.isEmpty) scenes = defaultScenes();
    activeSceneId = p.getString(_kActiveScene) ?? scenes.first.id;
    if (!scenes.any((s) => s.id == activeSceneId)) {
      activeSceneId = scenes.first.id;
    }

    correctionEnabled = true;
    translationEnabled = true;
    await p.setBool(_kCorrectionEnabled, true);
    await p.setBool(_kTranslationEnabled, true);
    translationLangA = p.getString(_kTranslationLangA) ?? '中文';
    translationLangB = p.getString(_kTranslationLangB) ?? '印尼语';
    if (translationLangA == translationLangB) {
      translationLangB = _firstDifferentLanguage(translationLangA);
      await p.setString(_kTranslationLangB, translationLangB);
    }

    final vp = p.get(_kVadPause);
    vadPauseSeconds = vp is double ? vp : (vp is int ? vp.toDouble() : 2.0);
    vadListenSeconds = p.getInt(_kVadListen) ?? 60;
    vadThresholdLevel = p.getDouble(_kVadThreshold) ?? 2.0;
    minRecordSeconds = p.getDouble(_kMinRecordSeconds) ?? 0.5;
    sttTimeoutSeconds = p.getInt(_kSttTimeout) ?? 10;
    llmTimeoutSeconds = p.getInt(_kLlmTimeout) ?? 10;
    ttsTimeoutSeconds = p.getInt(_kTtsTimeout) ?? 10;
    historyContextCount = p.getInt(_kHistoryContextCount) ?? 3;
    aecEnabled = p.getBool(_kAecEnabled) ?? true;
    continuousFullDuplex = p.getBool(_kContinuousFullDuplex) ?? false;
    audioDirectChat = p.getBool(_kAudioDirectChat) ?? false;
    audioDirectIncludeTranscript =
        p.getBool(_kAudioDirectIncludeTranscript) ?? false;
    includeScenePrompt = p.getBool(_kIncludeScenePrompt) ?? true;

    notifyListeners();
  }

  // ---- Legacy migration helpers ----

  VoiceMode _voiceModeFromIndex(int? index) {
    if (index == null || index < 0 || index >= VoiceMode.values.length) {
      return VoiceMode.pushToTalk;
    }
    return VoiceMode.values[index];
  }

  List<Scene> _decodeScenesOrDefault(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaultScenes();
    try {
      final decoded = decodeScenes(raw);
      return decoded.isEmpty ? defaultScenes() : decoded;
    } catch (_) {
      return defaultScenes();
    }
  }

  String _legacyCredential(
    SharedPreferences p,
    String providerId,
    CredentialField f,
  ) {
    switch (providerId) {
      case 'openai':
        if (f == CredentialField.apiKey) {
          return p.getString(_legacyOpenAiKey) ?? '';
        }
        break;
      case 'google':
        if (f == CredentialField.apiKey) {
          return p.getString(_legacyGeminiKey) ?? '';
        }
        break;
      case 'volcengine':
        if (f == CredentialField.appKey) {
          return p.getString(_legacyVolcAppKey) ?? '';
        }
        if (f == CredentialField.accessKey) {
          return p.getString(_legacyVolcAccessKey) ?? '';
        }
        break;
    }
    return '';
  }

  String? _legacyChatProviderId(SharedPreferences p) {
    final idx = p.getInt(_legacyProvider);
    if (idx == null) return null;
    return idx == 1 ? 'google' : 'openai';
  }

  String? _legacySttProviderId(SharedPreferences p) {
    final idx = p.getInt(_legacySttProvider);
    if (idx == null) return 'openai';
    switch (idx) {
      case 0:
        return 'openai';
      case 1:
        return 'volcengine';
      case 2:
        return null; // off
    }
    return 'openai';
  }

  String? _legacySttModelId(SharedPreferences p, String providerId) {
    if (providerId == 'openai') return p.getString(_legacySttOpenAiModel);
    if (providerId == 'volcengine') return p.getString(_legacyVolcResourceId);
    return null;
  }

  String? _legacyTtsProviderId(SharedPreferences p) {
    final idx = p.getInt(_legacyTtsMode);
    if (idx == null) return null;
    switch (idx) {
      case 0:
        return null; // off
      case 1:
        return 'openai';
      case 2:
        return 'volcengine';
    }
    return null;
  }

  String? _legacyTtsModelId(SharedPreferences p, String providerId) {
    if (providerId == 'openai') return p.getString(_legacyTtsOpenAiModel);
    if (providerId == 'volcengine') {
      return p.getString(_legacyTtsVolcResourceId);
    }
    return null;
  }

  String? _legacyTtsVoiceValue(SharedPreferences p, String providerId) {
    if (providerId == 'openai') return p.getString(_legacyTtsOpenAiVoice);
    if (providerId == 'volcengine') return p.getString(_legacyTtsVolcSpeaker);
    return null;
  }

  String? _firstModelId(String providerId, Capability c) {
    final p = findProvider(providerId);
    if (p == null) return null;
    final m = p.modelsFor(c);
    return m.isEmpty ? null : m.first.id;
  }

  String? _firstVoice(String providerId, String modelId) {
    final p = findProvider(providerId);
    final m = p?.findModel(modelId);
    if (m == null || m.voices.isEmpty) return null;
    return m.voices.first.id;
  }

  String? _firstProviderId(Capability c) {
    final p = providersFor(c);
    return p.isEmpty ? null : p.first.id;
  }

  String? _validProviderId(String? providerId, Capability c) {
    if (providerId == null || providerId.isEmpty) return null;
    final provider = findProvider(providerId);
    if (provider == null || !provider.hasCapability(c)) return null;
    return providerId;
  }

  /// Snap a selection back to a valid model in the catalog. If the persisted
  /// model id is no longer in the catalog (e.g. removed in an update), pick
  /// the first available one.
  void _ensureValid(Capability c) {
    String? pid;
    String mid = '';
    switch (c) {
      case Capability.chat:
        pid = chatProviderId;
        mid = chatModelId;
        break;
      case Capability.stt:
        pid = sttProviderId;
        mid = sttModelId;
        break;
      case Capability.tts:
        pid = ttsProviderId;
        mid = ttsModelId;
        break;
    }
    if (pid == null) return;
    final provider = findProvider(pid);
    if (provider == null || !provider.hasCapability(c)) {
      // Provider missing or no longer offers this capability.
      switch (c) {
        case Capability.chat:
          chatProviderId = providersFor(c).isEmpty
              ? null
              : providersFor(c).first.id;
          chatModelId = chatProviderId == null
              ? ''
              : (_firstModelId(chatProviderId!, c) ?? '');
          break;
        case Capability.stt:
          sttProviderId = null;
          sttModelId = '';
          break;
        case Capability.tts:
          ttsProviderId = null;
          ttsModelId = '';
          ttsVoice = '';
          break;
      }
      return;
    }
    final m = provider.findModel(mid);
    if (m == null || !m.supports(c)) {
      final fallback = _firstModelId(pid, c) ?? '';
      switch (c) {
        case Capability.chat:
          chatModelId = fallback;
          break;
        case Capability.stt:
          sttModelId = fallback;
          break;
        case Capability.tts:
          ttsModelId = fallback;
          ttsVoice = _firstVoice(pid, fallback) ?? '';
          break;
      }
      return;
    }
    if (c == Capability.tts && m.voices.isNotEmpty) {
      if (!m.voices.any((v) => v.id == ttsVoice)) {
        ttsVoice = m.voices.first.id;
      }
    }
  }

  void _ensureImageValid() {
    final pid = imageProviderId;
    if (pid == null) return;
    final provider = findProvider(pid);
    final model = provider?.findModel(imageModelId);
    if (model == null ||
        !model.supports(Capability.chat) ||
        !model.acceptsImage()) {
      final fallback = _firstImageModelId(pid);
      if (fallback == null) {
        imageProviderId = null;
        imageModelId = '';
      } else {
        imageModelId = fallback;
      }
    }
  }

  String? _firstImageModelId(String providerId) {
    final p = findProvider(providerId);
    if (p == null) return null;
    for (final m in p.modelsFor(Capability.chat)) {
      if (m.acceptsImage()) return m.id;
    }
    return null;
  }

  // ---- Setters ----

  Future<void> setRelayBaseUrl(String value) async {
    relayBaseUrl = normalizeRelayBaseUrl(value);
    final p = await _prefs;
    if (relayBaseUrl.isEmpty) {
      _relayProvider = null;
      relayCatalogError = null;
      relayCatalogFetchedAt = null;
      await p.setString(_kRelayBaseUrl, relayBaseUrl);
      await p.remove(_kRelayCatalogJson);
      await p.remove(_kRelayCatalogFetchedAt);
      _ensureValid(Capability.chat);
      _ensureValid(Capability.stt);
      _ensureValid(Capability.tts);
      _ensureImageValid();
      notifyListeners();
      return;
    }
    if (_relayProvider != null) {
      _relayProvider = ProviderSpec(
        id: _relayProvider!.id,
        name: _relayProvider!.name,
        baseUrl: relayBaseUrl,
        dialects: _relayProvider!.dialects,
        credentials: _relayProvider!.credentials,
        models: _relayProvider!.models,
      );
    }
    await p.setString(_kRelayBaseUrl, relayBaseUrl);
    notifyListeners();
  }

  Future<void> refreshRelayCatalog() async {
    if (relayBaseUrl.trim().isEmpty) {
      throw ArgumentError('Relay Base URL is required');
    }
    final p = await _prefs;
    final raw = await fetchRelayCatalogJson(
      relayBaseUrl,
      apiKey: credential(kRelayProviderId, CredentialField.apiKey),
    );
    _relayProvider = relayProviderFromJson(relayBaseUrl, jsonDecode(raw));
    relayCatalogError = null;
    relayCatalogFetchedAt = DateTime.now();
    await p.setString(_kRelayCatalogJson, raw);
    await p.setInt(
      _kRelayCatalogFetchedAt,
      relayCatalogFetchedAt!.millisecondsSinceEpoch,
    );
    _ensureValid(Capability.chat);
    _ensureValid(Capability.stt);
    _ensureValid(Capability.tts);
    _ensureImageValid();
    notifyListeners();
  }

  Future<void> setCredential(
    String providerId,
    CredentialField field,
    String value,
  ) async {
    _credentials.putIfAbsent(providerId, () => {})[field] = value;
    await (await _prefs).setString(_credKey(providerId, field), value);
    notifyListeners();
  }

  Future<void> setChatProvider(String providerId) async {
    chatProviderId = providerId;
    final mid = _firstModelId(providerId, Capability.chat) ?? '';
    chatModelId = mid;
    final p = await _prefs;
    await p.setString(_kChatProvider, providerId);
    await p.setString(_kChatModel, mid);
    notifyListeners();
  }

  Future<void> setChatModel(String modelId) async {
    chatModelId = modelId;
    await (await _prefs).setString(_kChatModel, modelId);
    notifyListeners();
  }

  Future<void> setImageProvider(String? providerId) async {
    imageProviderId = providerId;
    final p = await _prefs;
    await p.setString(_kImageProviderId, providerId ?? '');
    if (providerId != null) {
      imageModelId = _firstImageModelId(providerId) ?? '';
      await p.setString(_kImageModelId, imageModelId);
    } else {
      imageModelId = '';
      await p.setString(_kImageModelId, '');
    }
    notifyListeners();
  }

  Future<void> setImageModel(String modelId) async {
    imageModelId = modelId;
    await (await _prefs).setString(_kImageModelId, modelId);
    notifyListeners();
  }

  /// Providers that have at least one chat model accepting images.
  Iterable<ProviderSpec> imageProviders() => catalog.where(
    (p) =>
        p.dialects.containsKey(Capability.chat) &&
        p.modelsFor(Capability.chat).any((m) => m.acceptsImage()),
  );

  /// Effective provider for an image request: explicit override if set,
  /// otherwise the chat provider (only valid when its model accepts images).
  String? get effectiveImageProviderId => imageProviderId ?? chatProviderId;
  String get effectiveImageModelId =>
      imageProviderId != null ? imageModelId : chatModelId;

  bool get imageInputAvailable {
    final pid = effectiveImageProviderId;
    if (pid == null) return false;
    final m = findProvider(pid)?.findModel(effectiveImageModelId);
    return m?.acceptsImage() ?? false;
  }

  /// Like [buildChatRequest] but routed through [effectiveImageProviderId].
  ChatRequest? buildImageChatRequest() {
    final pid = effectiveImageProviderId;
    if (pid == null) return null;
    final provider = findProvider(pid);
    if (provider == null) return null;
    final dialect = provider.dialects[Capability.chat];
    if (dialect == null) return null;
    final apiKey = credential(pid, CredentialField.apiKey);
    return ChatRequest(
      providerName: provider.name,
      dialect: dialect,
      baseUrl: provider.baseUrl,
      apiKey: apiKey,
      modelId: effectiveImageModelId,
    );
  }

  Future<void> setSttProvider(String? providerId) async {
    sttProviderId = providerId;
    final p = await _prefs;
    await p.setString(_kSttProviderId, providerId ?? '');
    if (providerId != null) {
      _lastSttProviderId = providerId;
      await p.setString(_kLastSttProviderId, providerId);
      final provider = findProvider(providerId);
      final currentModel = provider?.findModel(sttModelId);
      if (currentModel == null || !currentModel.supports(Capability.stt)) {
        sttModelId = _firstModelId(providerId, Capability.stt) ?? '';
      }
      await p.setString(_kSttModelId, sttModelId);
    }
    notifyListeners();
  }

  Future<void> setSttEnabled(bool enabled) async {
    if (!enabled) {
      await setSttProvider(null);
      return;
    }
    final providerId =
        _validProviderId(_lastSttProviderId, Capability.stt) ??
        _firstProviderId(Capability.stt);
    if (providerId == null) return;
    await setSttProvider(providerId);
  }

  Future<void> setSttModel(String modelId) async {
    sttModelId = modelId;
    await (await _prefs).setString(_kSttModelId, modelId);
    notifyListeners();
  }

  Future<void> setTtsProvider(String? providerId) async {
    ttsProviderId = providerId;
    final p = await _prefs;
    await p.setString(_kTtsProviderId, providerId ?? '');
    if (providerId != null) {
      _lastTtsProviderId = providerId;
      await p.setString(_kLastTtsProviderId, providerId);
      final provider = findProvider(providerId);
      final currentModel = provider?.findModel(ttsModelId);
      if (currentModel == null || !currentModel.supports(Capability.tts)) {
        ttsModelId = _firstModelId(providerId, Capability.tts) ?? '';
        ttsVoice = _firstVoice(providerId, ttsModelId) ?? '';
      } else if (currentModel.voices.isNotEmpty &&
          !currentModel.voices.any((v) => v.id == ttsVoice)) {
        ttsVoice = currentModel.voices.first.id;
      }
      await p.setString(_kTtsModelId, ttsModelId);
      await p.setString(_kTtsVoice, ttsVoice);
    }
    notifyListeners();
  }

  Future<void> setTtsEnabled(bool enabled) async {
    if (!enabled) {
      await setTtsProvider(null);
      return;
    }
    final providerId =
        _validProviderId(_lastTtsProviderId, Capability.tts) ??
        _firstProviderId(Capability.tts);
    if (providerId == null) return;
    await setTtsProvider(providerId);
  }

  Future<void> setTtsModel(String modelId) async {
    ttsModelId = modelId;
    final p = await _prefs;
    await p.setString(_kTtsModelId, modelId);
    // Reset voice to first voice of new model if the current one isn't valid.
    if (ttsProviderId != null) {
      final m = findProvider(ttsProviderId!)?.findModel(modelId);
      if (m != null &&
          m.voices.isNotEmpty &&
          !m.voices.any((v) => v.id == ttsVoice)) {
        ttsVoice = m.voices.first.id;
        await p.setString(_kTtsVoice, ttsVoice);
      }
    }
    notifyListeners();
  }

  Future<void> setTtsVoice(String voice) async {
    ttsVoice = voice;
    await (await _prefs).setString(_kTtsVoice, voice);
    notifyListeners();
  }

  Future<void> setTtsAutoSpeak(bool v) async {
    ttsAutoSpeak = v;
    await (await _prefs).setBool(_kTtsAutoSpeak, v);
    notifyListeners();
  }

  Future<void> setTtsVolcSpeechRate(int v) async {
    ttsVolcSpeechRate = v;
    await (await _prefs).setInt(_kTtsVolcSpeechRate, v);
    notifyListeners();
  }

  Future<void> setVoiceMode(VoiceMode v) async {
    voiceMode = v;
    await (await _prefs).setInt(_kVoiceMode, v.index);
    notifyListeners();
  }

  Future<void> setAecEnabled(bool v) async {
    aecEnabled = v;
    await (await _prefs).setBool(_kAecEnabled, v);
    notifyListeners();
  }

  Future<void> setContinuousFullDuplex(bool v) async {
    continuousFullDuplex = v;
    await (await _prefs).setBool(_kContinuousFullDuplex, v);
    notifyListeners();
  }

  Future<void> setAudioDirectChat(bool v) async {
    audioDirectChat = v;
    await (await _prefs).setBool(_kAudioDirectChat, v);
    notifyListeners();
  }

  Future<void> setAudioDirectIncludeTranscript(bool v) async {
    audioDirectIncludeTranscript = v;
    await (await _prefs).setBool(_kAudioDirectIncludeTranscript, v);
    notifyListeners();
  }

  Future<void> setIncludeScenePrompt(bool v) async {
    includeScenePrompt = v;
    await (await _prefs).setBool(_kIncludeScenePrompt, v);
    notifyListeners();
  }

  /// True iff the selected chat model can handle the direct audio translation
  /// strategy, not merely attach arbitrary audio.
  bool get chatModelAcceptsAudio {
    final pid = chatProviderId;
    if (pid == null) return false;
    final m = findProvider(pid)?.findModel(chatModelId);
    return m?.canTranslateAudioDirect ?? false;
  }

  /// True iff audio-direct mode is both enabled and supported by the current
  /// chat model. Use this — not [audioDirectChat] alone — to gate runtime
  /// behaviour, so the toggle going stale (e.g. user switched to a non-audio
  /// model) doesn't break the pipeline.
  bool get audioDirectActive => audioDirectChat && chatModelAcceptsAudio;

  /// True iff voice input has somewhere to go: a configured STT provider, or
  /// the audio-direct path. When false, the mic is hidden in favour of the
  /// text input bar.
  bool get voiceInputAvailable => sttProviderId != null || audioDirectActive;

  Future<void> setMinRecordSeconds(double v) async {
    final clamped = v < 0.1 ? 0.1 : v;
    minRecordSeconds = clamped;
    await (await _prefs).setDouble(_kMinRecordSeconds, clamped);
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

  Future<void> setCorrectionEnabled(bool _) async {
    correctionEnabled = true;
    await (await _prefs).setBool(_kCorrectionEnabled, true);
    notifyListeners();
  }

  Future<void> setTranslationEnabled(bool _) async {
    translationEnabled = true;
    await (await _prefs).setBool(_kTranslationEnabled, true);
    notifyListeners();
  }

  Future<void> setTranslationLangA(String v) async {
    translationLangA = v;
    if (translationLangA == translationLangB) {
      translationLangB = _firstDifferentLanguage(translationLangA);
    }
    final p = await _prefs;
    await p.setString(_kTranslationLangA, translationLangA);
    await p.setString(_kTranslationLangB, translationLangB);
    notifyListeners();
  }

  Future<void> setTranslationLangB(String v) async {
    translationLangB = v;
    if (translationLangA == translationLangB) {
      translationLangA = _firstDifferentLanguage(translationLangB);
    }
    final p = await _prefs;
    await p.setString(_kTranslationLangA, translationLangA);
    await p.setString(_kTranslationLangB, translationLangB);
    notifyListeners();
  }

  String _firstDifferentLanguage(String language) {
    return kTranslationLanguages.firstWhere(
      (candidate) => candidate != language,
      orElse: () => language == '中文' ? '英语' : '中文',
    );
  }

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

  // ---- Runtime requests built from current selection ----

  /// Returns null if [chatProviderId] is missing, has no chat dialect, or has
  /// no API key set.
  ChatRequest? buildChatRequest({Duration? timeout}) {
    final pid = chatProviderId;
    if (pid == null) return null;
    final provider = findProvider(pid);
    if (provider == null) return null;
    final dialect = provider.dialects[Capability.chat];
    if (dialect == null) return null;
    final apiKey = credential(pid, CredentialField.apiKey);
    return ChatRequest(
      providerName: provider.name,
      dialect: dialect,
      baseUrl: provider.baseUrl,
      apiKey: apiKey,
      modelId: chatModelId,
    );
  }

  SttRequest? buildSttRequest() {
    final pid = sttProviderId;
    if (pid == null) return null;
    final provider = findProvider(pid);
    if (provider == null) return null;
    final dialect = provider.dialects[Capability.stt];
    if (dialect == null) return null;
    return SttRequest(
      dialect: dialect,
      baseUrl: provider.baseUrl,
      modelId: sttModelId,
      creds: credentialsFor(pid),
    );
  }

  TtsRequest? buildTtsRequest() {
    final pid = ttsProviderId;
    if (pid == null) return null;
    final provider = findProvider(pid);
    if (provider == null) return null;
    final dialect = provider.dialects[Capability.tts];
    if (dialect == null) return null;
    return TtsRequest(
      dialect: dialect,
      baseUrl: provider.baseUrl,
      modelId: ttsModelId,
      voice: ttsVoice,
      creds: credentialsFor(pid),
      volcSpeechRate: ttsVolcSpeechRate,
    );
  }

  /// Mirrors auc-web/frontend/src/components/utils.ts:buildPipelineGeminiPrompt.
  /// In audio-direct mode the model receives audio directly, so the leading
  /// "用户输入的文字是STT转换的结果" framing is dropped, timecodes are suppressed,
  /// and an optional JSON output schema is added. Scene prompt is included
  /// only when [includeScenePrompt] is true.
  String composedSystemPrompt() {
    final fused = audioDirectActive;
    return PromptComposer.compose(
      PromptOptions(
        intent: fused && audioDirectIncludeTranscript
            ? PromptIntent.directAudioJsonTranscriptAndOutput
            : (fused
                  ? PromptIntent.directAudioTranslateOrCorrect
                  : PromptIntent.textTranslateOrCorrect),
        translationEnabled: true,
        translationLangA: translationLangA,
        translationLangB: translationLangB,
        scenePrompt: activeScene.prompt,
        includeScenePrompt: includeScenePrompt,
      ),
    );
  }
}

/// Built by [AppSettings.buildChatRequest] — bundles everything the chat
/// runtime needs without exposing settings internals.
class ChatRequest {
  final String providerName;
  final ApiDialect dialect;
  final String baseUrl;
  final String apiKey;
  final String modelId;

  const ChatRequest({
    required this.providerName,
    required this.dialect,
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
  });
}
