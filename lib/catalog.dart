/// Single source of truth for providers, models, and capabilities.
///
/// All UI (settings, config sheet) and runtime services (chat / STT / TTS)
/// read from [kCatalog]. To add a model or provider, edit only this file.
library;

enum Capability { chat, stt, tts }

/// Input modalities a model accepts. Every model accepts text. Models that
/// can accept audio alongside text (e.g. Gemini, gpt-4o-audio-preview) carry
/// [Modality.audio] — these can be used as a single fused STT+chat step.
enum Modality { text, audio, image }

/// How an STT model receives audio. This is intentionally separate from
/// [Capability.stt] so realtime models can be represented without exposing
/// them through the file-upload pipeline.
enum SttTransport { batchUpload, asyncJob, realtime }

/// Wire-format families that the runtime knows how to dispatch to.
enum ApiDialect {
  openaiChat, // POST {baseUrl}/chat/completions
  geminiChat, // POST {baseUrl}/models/{model}:generateContent?key=
  geminiSpeech, // POST {baseUrl}/models/{model}:generateContent?key= (AUDIO)
  openaiTranscribe, // POST {baseUrl}/audio/transcriptions (multipart)
  openrouterTranscribe, // POST {baseUrl}/audio/transcriptions (JSON base64)
  openaiSpeech, // POST {baseUrl}/audio/speech
  xaiSpeech, // POST {baseUrl}/tts
  elevenlabsSpeech, // POST {baseUrl}/text-to-speech/{voice_id}
  volcSttFlash, // POST openspeech /api/v3/auc/bigmodel/recognize/flash
  volcTtsDoubao, // POST openspeech /api/v3/tts/unidirectional
  // ElevenLabs Scribe batch — POST /v1/speech-to-text.
  elevenlabsScribe,
  // Soniox v4 async — REST /v1 file upload + transcription job.
  sonioxStt,
}

/// Credential fields a provider can require. The name is the persistence key
/// suffix; [label] is the UI label.
enum CredentialField {
  apiKey('API Key'),
  appKey('App Key'),
  accessKey('Access Key');

  final String label;
  const CredentialField(this.label);
}

class TtsVoice {
  final String id;
  final String label;
  final String? lang;
  final String? group;
  const TtsVoice(this.id, this.label, {this.lang, this.group});
}

class ModelSpec {
  final String id; // wire-level model id, e.g. "gpt-4o-mini"
  final String label; // display name (often == id)
  final Set<Capability> caps;
  final Set<Modality> inputs; // always contains text
  final List<TtsVoice> voices; // empty unless caps contains tts
  final SttTransport? sttTransport; // null unless caps contains stt
  final bool supportsDirectAudioTranslate;
  final String? batchFallbackModelId;

  const ModelSpec({
    required this.id,
    required this.label,
    required this.caps,
    this.inputs = const {Modality.text},
    this.voices = const [],
    this.sttTransport,
    this.supportsDirectAudioTranslate = false,
    this.batchFallbackModelId,
  });

  bool supports(Capability c) => caps.contains(c);
  bool acceptsAudio() => inputs.contains(Modality.audio);
  bool acceptsImage() => inputs.contains(Modality.image);
  bool get canTranslateAudioDirect =>
      supports(Capability.chat) &&
      acceptsAudio() &&
      supportsDirectAudioTranslate;
}

class ProviderSpec {
  final String id; // stable persistence id, e.g. "openai"
  final String name; // display name
  final String baseUrl;
  final Map<Capability, ApiDialect> dialects;
  final List<CredentialField> credentials;
  final List<ModelSpec> models;

  const ProviderSpec({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.dialects,
    required this.credentials,
    required this.models,
  });

  bool hasCapability(Capability c) =>
      dialects.containsKey(c) && models.any((m) => m.supports(c));

  Iterable<ModelSpec> modelsFor(Capability c) =>
      models.where((m) => m.supports(c));

  ModelSpec? findModel(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }
}

// ---- OpenAI ----

const _openAiTtsVoices = [
  TtsVoice('alloy', 'alloy'),
  TtsVoice('ash', 'ash'),
  TtsVoice('ballad', 'ballad'),
  TtsVoice('coral', 'coral'),
  TtsVoice('echo', 'echo'),
  TtsVoice('fable', 'fable'),
  TtsVoice('nova', 'nova'),
  TtsVoice('onyx', 'onyx'),
  TtsVoice('sage', 'sage'),
  TtsVoice('shimmer', 'shimmer'),
];

const _xAiTtsVoices = [
  TtsVoice('eve', 'Eve', lang: 'multilingual'),
  TtsVoice('ara', 'Ara', lang: 'multilingual'),
  TtsVoice('rex', 'Rex', lang: 'multilingual'),
  TtsVoice('sal', 'Sal', lang: 'multilingual'),
  TtsVoice('leo', 'Leo', lang: 'multilingual'),
];

const _geminiTtsVoices = [
  TtsVoice('Zephyr', 'Zephyr - Bright'),
  TtsVoice('Puck', 'Puck - Upbeat'),
  TtsVoice('Charon', 'Charon - Informative'),
  TtsVoice('Kore', 'Kore - Firm'),
  TtsVoice('Fenrir', 'Fenrir - Excitable'),
  TtsVoice('Leda', 'Leda - Youthful'),
  TtsVoice('Orus', 'Orus - Firm'),
  TtsVoice('Aoede', 'Aoede - Breezy'),
  TtsVoice('Callirrhoe', 'Callirrhoe - Easy-going'),
  TtsVoice('Autonoe', 'Autonoe - Bright'),
];

const _openAi = ProviderSpec(
  id: 'openai',
  name: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  dialects: {
    Capability.chat: ApiDialect.openaiChat,
    Capability.stt: ApiDialect.openaiTranscribe,
    Capability.tts: ApiDialect.openaiSpeech,
  },
  credentials: [CredentialField.apiKey],
  models: [
    // Chat
    ModelSpec(
      id: 'gpt-4o',
      label: 'gpt-4o',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'gpt-4o-mini',
      label: 'gpt-4o-mini',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'gpt-4.1',
      label: 'gpt-4.1',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'gpt-4.1-mini',
      label: 'gpt-4.1-mini',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'gpt-5.4-mini',
      label: 'gpt-5.4-mini',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'gpt-5.4-nano',
      label: 'gpt-5.4-nano',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'gpt-4o-audio-preview',
      label: 'gpt-4o-audio-preview (text + audio)',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.audio, Modality.image},
      supportsDirectAudioTranslate: true,
    ),
    ModelSpec(
      id: 'gpt-4o-mini-audio-preview',
      label: 'gpt-4o-mini-audio-preview (text + audio)',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.audio, Modality.image},
      supportsDirectAudioTranslate: true,
    ),
    // STT
    ModelSpec(
      id: 'gpt-4o-mini-transcribe',
      label: 'gpt-4o-mini-transcribe',
      caps: {Capability.stt},
      sttTransport: SttTransport.batchUpload,
    ),
    ModelSpec(
      id: 'gpt-4o-transcribe',
      label: 'gpt-4o-transcribe',
      caps: {Capability.stt},
      sttTransport: SttTransport.batchUpload,
    ),
    ModelSpec(
      id: 'whisper-1',
      label: 'whisper-1',
      caps: {Capability.stt},
      sttTransport: SttTransport.batchUpload,
    ),
    // TTS
    ModelSpec(
      id: 'gpt-4o-mini-tts',
      label: 'gpt-4o-mini-tts',
      caps: {Capability.tts},
      voices: _openAiTtsVoices,
    ),
    ModelSpec(
      id: 'tts-1',
      label: 'tts-1',
      caps: {Capability.tts},
      voices: _openAiTtsVoices,
    ),
    ModelSpec(
      id: 'tts-1-hd',
      label: 'tts-1-hd',
      caps: {Capability.tts},
      voices: _openAiTtsVoices,
    ),
  ],
);

// ---- xAI ----

const _xai = ProviderSpec(
  id: 'xai',
  name: 'xAI',
  baseUrl: 'https://api.x.ai/v1',
  dialects: {Capability.tts: ApiDialect.xaiSpeech},
  credentials: [CredentialField.apiKey],
  models: [
    ModelSpec(
      id: 'grok-voice-tts-1.0',
      label: 'Grok Voice TTS 1.0',
      caps: {Capability.tts},
      voices: _xAiTtsVoices,
    ),
  ],
);

// ---- Google (Gemini direct) ----

const _google = ProviderSpec(
  id: 'google',
  name: 'Google (Gemini)',
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
  dialects: {
    Capability.chat: ApiDialect.geminiChat,
    Capability.stt: ApiDialect.geminiChat,
    Capability.tts: ApiDialect.geminiSpeech,
  },
  credentials: [CredentialField.apiKey],
  models: [
    ModelSpec(
      id: 'gemini-3-flash-preview',
      label: 'Gemini 3 Flash',
      caps: {Capability.chat, Capability.stt},
      inputs: {Modality.text, Modality.audio, Modality.image},
      sttTransport: SttTransport.batchUpload,
      supportsDirectAudioTranslate: true,
    ),
    ModelSpec(
      id: 'gemini-3.5-flash',
      label: 'Gemini 3.5 Flash',
      caps: {Capability.chat, Capability.stt},
      inputs: {Modality.text, Modality.audio, Modality.image},
      sttTransport: SttTransport.batchUpload,
      supportsDirectAudioTranslate: true,
    ),
    ModelSpec(
      id: 'gemini-3.1-flash-lite',
      label: 'Gemini 3.1 Flash Lite',
      caps: {Capability.chat, Capability.stt},
      inputs: {Modality.text, Modality.audio, Modality.image},
      sttTransport: SttTransport.batchUpload,
      supportsDirectAudioTranslate: true,
    ),
    ModelSpec(
      id: 'gemini-flash-lite-latest',
      label: 'gemini-flash-lite-latest',
      caps: {Capability.chat, Capability.stt},
      inputs: {Modality.text, Modality.audio, Modality.image},
      sttTransport: SttTransport.batchUpload,
      supportsDirectAudioTranslate: true,
    ),
    ModelSpec(
      id: 'gemini-3.1-flash-tts-preview',
      label: 'Gemini 3.1 Flash TTS Preview',
      caps: {Capability.tts},
      voices: _geminiTtsVoices,
    ),
  ],
);

// ---- OpenRouter (OpenAI-compatible) ----

const _openRouter = ProviderSpec(
  id: 'openrouter',
  name: 'OpenRouter',
  baseUrl: 'https://openrouter.ai/api/v1',
  dialects: {
    Capability.chat: ApiDialect.openaiChat,
    Capability.stt: ApiDialect.openrouterTranscribe,
    Capability.tts: ApiDialect.openaiSpeech,
  },
  credentials: [CredentialField.apiKey],
  // Curated set of currently popular, non-thinking chat models on OpenRouter.
  // Reasoning/thinking variants (R1, o-series, grok-*-mini, qwen-*-thinking,
  // etc.) are intentionally excluded — translation latency matters more than
  // chain-of-thought quality.
  models: [
    // DeepSeek
    ModelSpec(
      id: 'deepseek/deepseek-v4-flash',
      label: 'DeepSeek V4 Flash',
      caps: {Capability.chat},
    ),
    ModelSpec(
      id: 'deepseek/deepseek-chat',
      label: 'DeepSeek V3 Chat',
      caps: {Capability.chat},
    ),
    // Anthropic
    ModelSpec(
      id: 'anthropic/claude-sonnet-4.5',
      label: 'Claude Sonnet 4.5',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    // Google
    ModelSpec(
      id: 'google/gemini-3-flash-preview',
      label: 'Gemini 3 Flash',
      caps: {Capability.chat, Capability.stt},
      inputs: {Modality.text, Modality.audio, Modality.image},
      sttTransport: SttTransport.batchUpload,
      supportsDirectAudioTranslate: true,
    ),
    ModelSpec(
      id: 'google/gemini-3.5-flash',
      label: 'Gemini 3.5 Flash',
      caps: {Capability.chat, Capability.stt},
      inputs: {Modality.text, Modality.audio, Modality.image},
      sttTransport: SttTransport.batchUpload,
      supportsDirectAudioTranslate: true,
    ),
    ModelSpec(
      id: 'google/gemini-3.1-flash-lite',
      label: 'Gemini 3.1 Flash Lite',
      caps: {Capability.chat, Capability.stt},
      inputs: {Modality.text, Modality.audio, Modality.image},
      sttTransport: SttTransport.batchUpload,
      supportsDirectAudioTranslate: true,
    ),
    ModelSpec(
      id: 'google/gemini-3.1-flash-tts-preview',
      label: 'Gemini 3.1 Flash TTS Preview',
      caps: {Capability.tts},
      voices: _geminiTtsVoices,
    ),
    // OpenAI
    ModelSpec(
      id: 'openai/gpt-5.4',
      label: 'GPT-5.4',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'openai/gpt-5.4-mini',
      label: 'GPT-5.4 Mini',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'openai/gpt-5.4-nano',
      label: 'GPT-5.4 Nano',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'openai/gpt-5-chat',
      label: 'GPT-5 Chat',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'openai/gpt-4.1',
      label: 'GPT-4.1',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'openai/gpt-4.1-mini',
      label: 'GPT-4.1 Mini',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'openai/gpt-4o',
      label: 'GPT-4o',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'openai/gpt-4o-mini',
      label: 'GPT-4o mini',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'openai/gpt-4o-audio-preview',
      label: 'GPT-4o audio preview',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.audio},
    ),
    ModelSpec(
      id: 'openai/gpt-4o-mini-transcribe',
      label: 'GPT-4o mini transcribe',
      caps: {Capability.stt},
      sttTransport: SttTransport.batchUpload,
    ),
    ModelSpec(
      id: 'openai/gpt-4o-transcribe',
      label: 'GPT-4o transcribe',
      caps: {Capability.stt},
      sttTransport: SttTransport.batchUpload,
    ),
    // xAI Grok (non-reasoning variants only)
    ModelSpec(
      id: 'x-ai/grok-4.1-fast',
      label: 'Grok 4.1 Fast',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'x-ai/grok-4-fast',
      label: 'Grok 4 Fast',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(id: 'x-ai/grok-3', label: 'Grok 3', caps: {Capability.chat}),
    ModelSpec(
      id: 'x-ai/grok-voice-tts-1.0',
      label: 'Grok Voice TTS 1.0',
      caps: {Capability.tts},
      voices: _xAiTtsVoices,
    ),
    // Meta Llama
    ModelSpec(
      id: 'meta-llama/llama-4-maverick',
      label: 'Llama 4 Maverick',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    ModelSpec(
      id: 'meta-llama/llama-4-scout',
      label: 'Llama 4 Scout',
      caps: {Capability.chat},
      inputs: {Modality.text, Modality.image},
    ),
    // Qwen (Instruct / non-thinking)
    ModelSpec(
      id: 'qwen/qwen3-235b-a22b-2507',
      label: 'Qwen3 235B A22B Instruct 2507',
      caps: {Capability.chat},
    ),
    // Mistral
    ModelSpec(
      id: 'mistralai/mistral-large-2512',
      label: 'Mistral Large 3 (2512)',
      caps: {Capability.chat},
    ),
    ModelSpec(
      id: 'mistralai/mistral-medium-3.1',
      label: 'Mistral Medium 3.1',
      caps: {Capability.chat},
    ),
  ],
);

// ---- Volcengine (豆包) — STT + TTS ----

const _doubaoVoices = [
  TtsVoice(
    'zh_female_vv_uranus_bigtts',
    'Vivi 2.0 (女)',
    lang: '中文/日文/印尼语/西语',
    group: '通用 - 多语种',
  ),
  TtsVoice(
    'zh_female_yingyujiaoxue_uranus_bigtts',
    'Tina老师 2.0 (女)',
    lang: '中文/英式英语',
    group: '通用 - 多语种',
  ),
  TtsVoice(
    'en_male_tim_uranus_bigtts',
    'Tim (Male)',
    lang: '美式英语',
    group: 'English',
  ),
  TtsVoice(
    'en_female_dacey_uranus_bigtts',
    'Dacey (Female)',
    lang: '美式英语',
    group: 'English',
  ),
  TtsVoice(
    'en_female_stokie_uranus_bigtts',
    'Stokie (Female)',
    lang: '美式英语',
    group: 'English',
  ),
  TtsVoice(
    'zh_female_xiaohe_uranus_bigtts',
    '小何 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_female_qingxinnvsheng_uranus_bigtts',
    '清新女声 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_female_cancan_uranus_bigtts',
    '知性灿灿 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_female_sajiaoxuemei_uranus_bigtts',
    '撒娇学妹 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_female_tianmeixiaoyuan_uranus_bigtts',
    '甜美小源 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_female_tianmeitaozi_uranus_bigtts',
    '甜美桃子 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_female_shuangkuaisisi_uranus_bigtts',
    '爽快思思 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_female_linjianvhai_uranus_bigtts',
    '邻家女孩 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_female_meilinvyou_uranus_bigtts',
    '魅力女友 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_female_kefunvsheng_uranus_bigtts',
    '暖阳女声 2.0 (女)',
    lang: '中文',
    group: '中文女声 - 客服',
  ),
  TtsVoice(
    'zh_female_liuchangnv_uranus_bigtts',
    '流畅女声 2.0 (女)',
    lang: '中文',
    group: '中文女声',
  ),
  TtsVoice(
    'zh_male_m191_uranus_bigtts',
    '云舟 2.0 (男)',
    lang: '中文',
    group: '中文男声',
  ),
  TtsVoice(
    'zh_male_taocheng_uranus_bigtts',
    '小天 2.0 (男)',
    lang: '中文',
    group: '中文男声',
  ),
  TtsVoice(
    'zh_male_liufei_uranus_bigtts',
    '刘飞 2.0 (男)',
    lang: '中文',
    group: '中文男声',
  ),
  TtsVoice(
    'zh_male_shaonianzixin_uranus_bigtts',
    '少年梓辛 2.0 (男)',
    lang: '中文',
    group: '中文男声',
  ),
  TtsVoice(
    'zh_male_ruyayichen_uranus_bigtts',
    '儒雅逸辰 2.0 (男)',
    lang: '中文',
    group: '中文男声',
  ),
  TtsVoice(
    'zh_male_dayi_uranus_bigtts',
    '大壹 2.0 (男)',
    lang: '中文',
    group: '中文男声',
  ),
  TtsVoice(
    'zh_female_peiqi_uranus_bigtts',
    '佩奇猪 2.0 (女)',
    lang: '中文',
    group: '特色/配音',
  ),
  TtsVoice(
    'zh_male_sunwukong_uranus_bigtts',
    '猴哥 2.0 (男)',
    lang: '中文',
    group: '特色/配音',
  ),
  TtsVoice(
    'zh_female_mizai_uranus_bigtts',
    '黑猫咪仔 2.0 (女)',
    lang: '中文',
    group: '特色/配音',
  ),
  TtsVoice(
    'zh_female_jitangnv_uranus_bigtts',
    '鸡汤女 2.0 (女)',
    lang: '中文',
    group: '特色/配音',
  ),
  TtsVoice(
    'zh_female_xiaoxue_uranus_bigtts',
    '儿童绘本 2.0 (女)',
    lang: '中文',
    group: '特色/配音',
  ),
];

const _volcengine = ProviderSpec(
  id: 'volcengine',
  name: 'Volcengine 豆包',
  baseUrl: 'https://openspeech.bytedance.com',
  dialects: {
    Capability.stt: ApiDialect.volcSttFlash,
    Capability.tts: ApiDialect.volcTtsDoubao,
  },
  credentials: [CredentialField.appKey, CredentialField.accessKey],
  models: [
    // STT (one-shot recognize resource ids)
    ModelSpec(
      id: 'volc.bigasr.auc_turbo',
      label: 'volc.bigasr.auc_turbo (急速版)',
      caps: {Capability.stt},
      sttTransport: SttTransport.batchUpload,
    ),
    // TTS (Doubao seed-tts resource ids)
    ModelSpec(
      id: 'seed-tts-2.0',
      label: 'seed-tts-2.0 (字符版)',
      caps: {Capability.tts},
      voices: _doubaoVoices,
    ),
    ModelSpec(
      id: 'seed-tts-1.0-concurr',
      label: 'seed-tts-1.0-concurr (并发版)',
      caps: {Capability.tts},
      voices: _doubaoVoices,
    ),
  ],
);

const _elevenlabsVoices = [
  // Official docs examples. Users can replace these with any voice ID once
  // custom voice configuration is added.
  TtsVoice('JBFqnCBsd6RMkjVDRZzb', 'George'),
  TtsVoice('21m00Tcm4TlvDq8ikWAM', 'Rachel'),
];

// ---- ElevenLabs (Scribe v2 + Text to Speech) ----

const _elevenlabs = ProviderSpec(
  id: 'elevenlabs',
  name: 'ElevenLabs',
  baseUrl: 'https://api.elevenlabs.io',
  dialects: {
    Capability.stt: ApiDialect.elevenlabsScribe,
    Capability.tts: ApiDialect.elevenlabsSpeech,
  },
  credentials: [CredentialField.apiKey],
  models: [
    // Batch — POST /v1/speech-to-text (multipart, model_id=scribe_v2).
    ModelSpec(
      id: 'scribe_v2',
      label: 'Scribe v2 (batch)',
      caps: {Capability.stt},
      sttTransport: SttTransport.batchUpload,
    ),
    // TTS — POST /v1/text-to-speech/{voice_id}.
    ModelSpec(
      id: 'eleven_flash_v2_5',
      label: 'Eleven Flash v2.5',
      caps: {Capability.tts},
      voices: _elevenlabsVoices,
    ),
    ModelSpec(
      id: 'eleven_flash_v2',
      label: 'Eleven Flash v2',
      caps: {Capability.tts},
      voices: _elevenlabsVoices,
    ),
    ModelSpec(
      id: 'eleven_turbo_v2_5',
      label: 'Eleven Turbo v2.5',
      caps: {Capability.tts},
      voices: _elevenlabsVoices,
    ),
    ModelSpec(
      id: 'eleven_turbo_v2',
      label: 'Eleven Turbo v2',
      caps: {Capability.tts},
      voices: _elevenlabsVoices,
    ),
    ModelSpec(
      id: 'eleven_multilingual_v2',
      label: 'Eleven Multilingual v2',
      caps: {Capability.tts},
      voices: _elevenlabsVoices,
    ),
    ModelSpec(
      id: 'eleven_v3',
      label: 'Eleven v3',
      caps: {Capability.tts},
      voices: _elevenlabsVoices,
    ),
  ],
);

// ---- Soniox (v4 async) ----

const _soniox = ProviderSpec(
  id: 'soniox',
  name: 'Soniox',
  baseUrl: 'https://api.soniox.com',
  dialects: {Capability.stt: ApiDialect.sonioxStt},
  credentials: [CredentialField.apiKey],
  models: [
    // Async — REST api.soniox.com/v1 (file upload + transcription, webhook).
    ModelSpec(
      id: 'stt-async-v4',
      label: 'Soniox v4 (async)',
      caps: {Capability.stt},
      sttTransport: SttTransport.asyncJob,
    ),
  ],
);

// ---- Catalog ----

const kCatalog = <ProviderSpec>[
  _openAi,
  _xai,
  _google,
  _openRouter,
  _volcengine,
  _elevenlabs,
  _soniox,
];

ProviderSpec? findProvider(String? id) {
  if (id == null) return null;
  for (final p in kCatalog) {
    if (p.id == id) return p;
  }
  return null;
}

Iterable<ProviderSpec> providersFor(Capability c) =>
    kCatalog.where((p) => p.hasCapability(c));
