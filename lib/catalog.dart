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

/// Wire-format families that the runtime knows how to dispatch to.
enum ApiDialect {
  openaiChat, // POST {baseUrl}/chat/completions
  geminiChat, // POST {baseUrl}/models/{model}:generateContent?key=
  openaiTranscribe, // POST {baseUrl}/audio/transcriptions (multipart)
  openaiSpeech, // POST {baseUrl}/audio/speech
  volcSttFlash, // POST openspeech /api/v3/auc/bigmodel/recognize/flash
  volcTtsDoubao, // POST openspeech /api/v3/tts/unidirectional
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

  const ModelSpec({
    required this.id,
    required this.label,
    required this.caps,
    this.inputs = const {Modality.text},
    this.voices = const [],
  });

  bool supports(Capability c) => caps.contains(c);
  bool acceptsAudio() => inputs.contains(Modality.audio);
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
    ModelSpec(id: 'gpt-4o', label: 'gpt-4o', caps: {Capability.chat}),
    ModelSpec(id: 'gpt-4o-mini', label: 'gpt-4o-mini', caps: {Capability.chat}),
    ModelSpec(id: 'gpt-4.1', label: 'gpt-4.1', caps: {Capability.chat}),
    ModelSpec(id: 'gpt-4.1-mini', label: 'gpt-4.1-mini', caps: {Capability.chat}),
    ModelSpec(
        id: 'gpt-audio',
        label: 'gpt-audio (text + audio)',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'gpt-audio-mini',
        label: 'gpt-audio-mini (text + audio)',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'gpt-4o-audio-preview',
        label: 'gpt-4o-audio-preview (text + audio)',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'gpt-4o-mini-audio-preview',
        label: 'gpt-4o-mini-audio-preview (text + audio)',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    // STT
    ModelSpec(
        id: 'gpt-4o-mini-transcribe',
        label: 'gpt-4o-mini-transcribe',
        caps: {Capability.stt}),
    ModelSpec(
        id: 'gpt-4o-transcribe',
        label: 'gpt-4o-transcribe',
        caps: {Capability.stt}),
    ModelSpec(id: 'whisper-1', label: 'whisper-1', caps: {Capability.stt}),
    // TTS
    ModelSpec(
        id: 'gpt-4o-mini-tts',
        label: 'gpt-4o-mini-tts',
        caps: {Capability.tts},
        voices: _openAiTtsVoices),
    ModelSpec(
        id: 'tts-1',
        label: 'tts-1',
        caps: {Capability.tts},
        voices: _openAiTtsVoices),
    ModelSpec(
        id: 'tts-1-hd',
        label: 'tts-1-hd',
        caps: {Capability.tts},
        voices: _openAiTtsVoices),
  ],
);

// ---- Google (Gemini direct) ----

const _google = ProviderSpec(
  id: 'google',
  name: 'Google (Gemini)',
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
  dialects: {Capability.chat: ApiDialect.geminiChat},
  credentials: [CredentialField.apiKey],
  models: [
    ModelSpec(
        id: 'gemini-3-flash-preview',
        label: 'gemini-3-flash-preview',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'gemini-3.1-flash-lite-preview',
        label: 'gemini-3.1-flash-lite-preview',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'gemini-2.5-pro',
        label: 'gemini-2.5-pro',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'gemini-2.5-flash',
        label: 'gemini-2.5-flash',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'gemini-2.0-flash',
        label: 'gemini-2.0-flash',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'gemini-2.0-flash-lite',
        label: 'gemini-2.0-flash-lite',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
  ],
);

// ---- OpenRouter (OpenAI-compatible) ----

const _openRouter = ProviderSpec(
  id: 'openrouter',
  name: 'OpenRouter',
  baseUrl: 'https://openrouter.ai/api/v1',
  dialects: {Capability.chat: ApiDialect.openaiChat},
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
        caps: {Capability.chat}),
    ModelSpec(
        id: 'deepseek/deepseek-v3.2',
        label: 'DeepSeek V3.2',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'deepseek/deepseek-chat',
        label: 'DeepSeek V3 Chat',
        caps: {Capability.chat}),
    // Anthropic
    ModelSpec(
        id: 'anthropic/claude-sonnet-4.6',
        label: 'Claude Sonnet 4.6',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'anthropic/claude-sonnet-4.5',
        label: 'Claude Sonnet 4.5',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'anthropic/claude-haiku-4.5',
        label: 'Claude Haiku 4.5',
        caps: {Capability.chat}),
    // Google
    ModelSpec(
        id: 'google/gemini-3-flash-preview',
        label: 'Gemini 3 Flash Preview',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'google/gemini-3.1-flash-lite-preview',
        label: 'Gemini 3.1 Flash Lite Preview',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'google/gemini-2.5-pro',
        label: 'Gemini 2.5 Pro',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'google/gemini-2.5-flash',
        label: 'Gemini 2.5 Flash',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'google/gemini-2.0-flash-001',
        label: 'Gemini 2.0 Flash',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    // OpenAI
    ModelSpec(
        id: 'openai/gpt-5.4',
        label: 'GPT-5.4',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'openai/gpt-5.4-mini',
        label: 'GPT-5.4 Mini',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'openai/gpt-5-chat',
        label: 'GPT-5 Chat',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'openai/gpt-4.1',
        label: 'GPT-4.1',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'openai/gpt-4.1-mini',
        label: 'GPT-4.1 Mini',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'openai/gpt-4o',
        label: 'GPT-4o',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'openai/gpt-4o-mini',
        label: 'GPT-4o mini',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'openai/gpt-audio',
        label: 'GPT Audio',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'openai/gpt-audio-mini',
        label: 'GPT Audio Mini',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    ModelSpec(
        id: 'openai/gpt-4o-audio-preview',
        label: 'GPT-4o audio preview',
        caps: {Capability.chat},
        inputs: {Modality.text, Modality.audio}),
    // xAI Grok (non-reasoning variants only)
    ModelSpec(
        id: 'x-ai/grok-4.1-fast',
        label: 'Grok 4.1 Fast',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'x-ai/grok-4-fast',
        label: 'Grok 4 Fast',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'x-ai/grok-3',
        label: 'Grok 3',
        caps: {Capability.chat}),
    // Meta Llama
    ModelSpec(
        id: 'meta-llama/llama-4-maverick',
        label: 'Llama 4 Maverick',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'meta-llama/llama-4-scout',
        label: 'Llama 4 Scout',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'meta-llama/llama-3.3-70b-instruct',
        label: 'Llama 3.3 70B Instruct',
        caps: {Capability.chat}),
    // Qwen (Instruct / non-thinking)
    ModelSpec(
        id: 'qwen/qwen3-max',
        label: 'Qwen3 Max',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'qwen/qwen3-235b-a22b-2507',
        label: 'Qwen3 235B A22B Instruct 2507',
        caps: {Capability.chat}),
    // Mistral
    ModelSpec(
        id: 'mistralai/mistral-large-2512',
        label: 'Mistral Large 3 (2512)',
        caps: {Capability.chat}),
    ModelSpec(
        id: 'mistralai/mistral-medium-3.1',
        label: 'Mistral Medium 3.1',
        caps: {Capability.chat}),
  ],
);

// ---- Volcengine (豆包) — STT + TTS ----

const _doubaoVoices = [
  TtsVoice('zh_female_vv_uranus_bigtts', 'Vivi 2.0 (女)',
      lang: '中文/日文/印尼语/西语', group: '通用 - 多语种'),
  TtsVoice('zh_female_yingyujiaoxue_uranus_bigtts', 'Tina老师 2.0 (女)',
      lang: '中文/英式英语', group: '通用 - 多语种'),
  TtsVoice('en_male_tim_uranus_bigtts', 'Tim (Male)',
      lang: '美式英语', group: 'English'),
  TtsVoice('en_female_dacey_uranus_bigtts', 'Dacey (Female)',
      lang: '美式英语', group: 'English'),
  TtsVoice('en_female_stokie_uranus_bigtts', 'Stokie (Female)',
      lang: '美式英语', group: 'English'),
  TtsVoice('zh_female_xiaohe_uranus_bigtts', '小何 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_female_qingxinnvsheng_uranus_bigtts', '清新女声 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_female_cancan_uranus_bigtts', '知性灿灿 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_female_sajiaoxuemei_uranus_bigtts', '撒娇学妹 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_female_tianmeixiaoyuan_uranus_bigtts', '甜美小源 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_female_tianmeitaozi_uranus_bigtts', '甜美桃子 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_female_shuangkuaisisi_uranus_bigtts', '爽快思思 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_female_linjianvhai_uranus_bigtts', '邻家女孩 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_female_meilinvyou_uranus_bigtts', '魅力女友 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_female_kefunvsheng_uranus_bigtts', '暖阳女声 2.0 (女)',
      lang: '中文', group: '中文女声 - 客服'),
  TtsVoice('zh_female_liuchangnv_uranus_bigtts', '流畅女声 2.0 (女)',
      lang: '中文', group: '中文女声'),
  TtsVoice('zh_male_m191_uranus_bigtts', '云舟 2.0 (男)',
      lang: '中文', group: '中文男声'),
  TtsVoice('zh_male_taocheng_uranus_bigtts', '小天 2.0 (男)',
      lang: '中文', group: '中文男声'),
  TtsVoice('zh_male_liufei_uranus_bigtts', '刘飞 2.0 (男)',
      lang: '中文', group: '中文男声'),
  TtsVoice('zh_male_shaonianzixin_uranus_bigtts', '少年梓辛 2.0 (男)',
      lang: '中文', group: '中文男声'),
  TtsVoice('zh_male_ruyayichen_uranus_bigtts', '儒雅逸辰 2.0 (男)',
      lang: '中文', group: '中文男声'),
  TtsVoice('zh_male_dayi_uranus_bigtts', '大壹 2.0 (男)',
      lang: '中文', group: '中文男声'),
  TtsVoice('zh_female_peiqi_uranus_bigtts', '佩奇猪 2.0 (女)',
      lang: '中文', group: '特色/配音'),
  TtsVoice('zh_male_sunwukong_uranus_bigtts', '猴哥 2.0 (男)',
      lang: '中文', group: '特色/配音'),
  TtsVoice('zh_female_mizai_uranus_bigtts', '黑猫咪仔 2.0 (女)',
      lang: '中文', group: '特色/配音'),
  TtsVoice('zh_female_jitangnv_uranus_bigtts', '鸡汤女 2.0 (女)',
      lang: '中文', group: '特色/配音'),
  TtsVoice('zh_female_xiaoxue_uranus_bigtts', '儿童绘本 2.0 (女)',
      lang: '中文', group: '特色/配音'),
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
        caps: {Capability.stt}),
    ModelSpec(
        id: 'volc.bigasr.auc',
        label: 'volc.bigasr.auc (录音文件 1.0)',
        caps: {Capability.stt}),
    ModelSpec(
        id: 'volc.seedasr.auc',
        label: 'volc.seedasr.auc (录音文件 2.0)',
        caps: {Capability.stt}),
    // TTS (Doubao seed-tts resource ids)
    ModelSpec(
        id: 'seed-tts-2.0',
        label: 'seed-tts-2.0 (字符版)',
        caps: {Capability.tts},
        voices: _doubaoVoices),
    ModelSpec(
        id: 'seed-tts-1.0',
        label: 'seed-tts-1.0 (字符版)',
        caps: {Capability.tts},
        voices: _doubaoVoices),
    ModelSpec(
        id: 'seed-tts-1.0-concurr',
        label: 'seed-tts-1.0-concurr (并发版)',
        caps: {Capability.tts},
        voices: _doubaoVoices),
  ],
);

// ---- Catalog ----

const kCatalog = <ProviderSpec>[
  _openAi,
  _google,
  _openRouter,
  _volcengine,
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
