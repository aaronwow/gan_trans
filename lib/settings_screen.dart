import 'package:flutter/material.dart';

import 'catalog.dart';
import 'provider_model_picker.dart';
import 'settings.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Per (providerId, fieldName) text controllers, lazily created.
  final Map<String, TextEditingController> _credCtrls = {};

  TextEditingController _credCtrl(String providerId, CredentialField f) {
    final key = '${providerId}__${f.name}';
    return _credCtrls.putIfAbsent(
      key,
      () => TextEditingController(
        text: widget.settings.credential(providerId, f),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _credCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _heroHeader(),
          const SizedBox(height: 16),
          _settingsSection(
            icon: Icons.key_outlined,
            title: 'Providers',
            subtitle: '各 provider 的凭证会复用于 Chat、STT 和 TTS。',
            children: [for (final p in kCatalog) _providerCard(p)],
          ),
          const SizedBox(height: 14),
          _settingsSection(
            icon: Icons.chat_bubble_outline,
            title: 'Chat',
            subtitle: '选择对话模型和上下文策略。',
            children: [
              ProviderModelPicker(
                settings: s,
                cap: Capability.chat,
                providerId: s.chatProviderId,
                modelId: s.chatModelId,
                allowOff: false,
                onProvider: (id) async {
                  if (id == null) return;
                  await s.setChatProvider(id);
                  if (mounted) setState(() {});
                },
                onModel: (id) async {
                  await s.setChatModel(id);
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 10),
              _settingsSwitch(
                title: 'Include scene prompt',
                subtitle: '每次 Chat 请求都带上当前场景提示词。',
                value: s.includeScenePrompt,
                onChanged: (v) {
                  s.setIncludeScenePrompt(v);
                  setState(() {});
                },
              ),
              _settingsSwitch(
                title: 'Audio direct',
                subtitle: s.chatModelAcceptsAudio
                    ? '录音直接发送给 Chat，跳过 STT。'
                    : '当前 Chat 模型不支持音频输入，请换用支持音频的模型。',
                value: s.audioDirectChat && s.chatModelAcceptsAudio,
                onChanged: s.chatModelAcceptsAudio
                    ? (v) {
                        s.setAudioDirectChat(v);
                        setState(() {});
                      }
                    : null,
              ),
              if (s.audioDirectActive)
                _settingsSwitch(
                  title: 'Return original transcript',
                  subtitle: '要求模型返回原始转录和最终输出。',
                  value: s.audioDirectIncludeTranscript,
                  onChanged: (v) {
                    s.setAudioDirectIncludeTranscript(v);
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          _settingsSection(
            icon: Icons.graphic_eq,
            title: 'Speech-to-Text',
            subtitle: s.audioDirectActive
                ? 'Audio direct 已接管语音输入，STT 暂停。'
                : '麦克风输入使用的识别模型。',
            children: [
              Opacity(
                opacity: s.audioDirectActive ? 0.54 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.audioDirectActive) ...[
                      _settingsNotice(
                        icon: Icons.info_outline,
                        text:
                            'Audio direct 已开启：语音会直接发送给 Chat，关闭 Audio direct 后才能调整 STT。',
                      ),
                      const SizedBox(height: 10),
                    ],
                    ProviderModelPicker(
                      settings: s,
                      cap: Capability.stt,
                      providerId: s.sttProviderId,
                      modelId: s.sttModelId,
                      allowOff: true,
                      enabled: !s.audioDirectActive,
                      onProvider: (id) async {
                        await s.setSttProvider(id);
                        if (mounted) setState(() {});
                      },
                      onModel: (id) async {
                        await s.setSttModel(id);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _settingsSection(
            icon: Icons.volume_up_outlined,
            title: 'Text-to-Speech',
            subtitle: '语音播放模型和自动播放行为。',
            children: [
              ProviderModelPicker(
                settings: s,
                cap: Capability.tts,
                providerId: s.ttsProviderId,
                modelId: s.ttsModelId,
                allowOff: true,
                onProvider: (id) async {
                  await s.setTtsProvider(id);
                  if (mounted) setState(() {});
                },
                onModel: (id) async {
                  await s.setTtsModel(id);
                  if (mounted) setState(() {});
                },
              ),
              if (s.ttsProviderId != null) ...[
                const SizedBox(height: 12),
                _ttsVoicePicker(),
                const SizedBox(height: 10),
                _settingsSwitch(
                  title: 'Auto-speak assistant replies',
                  subtitle: '每次回复生成后自动播放 TTS。',
                  value: s.ttsAutoSpeak,
                  onChanged: (v) {
                    s.setTtsAutoSpeak(v);
                    setState(() {});
                  },
                ),
                if (s.ttsProviderId == 'volcengine') _doubaoSpeechRate(),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _settingsSection(
            icon: Icons.mic_none,
            title: 'Microphone',
            subtitle: '录音滤波和语音活动检测。',
            children: [
              _settingsSwitch(
                title: 'Acoustic echo cancellation',
                subtitle: '降低 Full-duplex 播放时扬声器回到麦克风的回声。',
                value: s.aecEnabled,
                onChanged: (v) {
                  s.setAecEnabled(v);
                  setState(() {});
                },
              ),
              _settingsSlider(
                title: '静音多久后自动切分',
                valueText: '${s.vadPauseSeconds.toStringAsFixed(1)}s',
                slider: Slider(
                  value: s.vadPauseSeconds.clamp(0.1, 10.0),
                  min: 0.1,
                  max: 10,
                  divisions: 99,
                  label: '${s.vadPauseSeconds.toStringAsFixed(1)}s',
                  onChanged: (v) {
                    s.setVadPause(double.parse(v.toStringAsFixed(1)));
                    setState(() {});
                  },
                ),
              ),
              _settingsSlider(
                title: '最长监听时间',
                valueText: '${s.vadListenSeconds}s',
                slider: Slider(
                  value: s.vadListenSeconds.toDouble(),
                  min: 10,
                  max: 300,
                  divisions: 29,
                  label: '${s.vadListenSeconds}s',
                  onChanged: (v) {
                    s.setVadListen(v.round());
                    setState(() {});
                  },
                ),
              ),
              _settingsSlider(
                title: '忽略过短录音',
                valueText: '${s.minRecordSeconds.toStringAsFixed(1)}s',
                slider: Slider(
                  value: s.minRecordSeconds.clamp(0.1, 5.0),
                  min: 0.1,
                  max: 5.0,
                  divisions: 49,
                  label: '${s.minRecordSeconds.toStringAsFixed(1)}s',
                  onChanged: (v) {
                    s.setMinRecordSeconds(double.parse(v.toStringAsFixed(1)));
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _settingsSection(
            icon: Icons.timer_outlined,
            title: 'Response Limits',
            subtitle: '语音链路使用的超时和上下文窗口。',
            children: [
              _settingsSlider(
                title: 'STT timeout',
                valueText: '${s.sttTimeoutSeconds}s',
                slider: Slider(
                  value: s.sttTimeoutSeconds.toDouble().clamp(1, 60),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  label: '${s.sttTimeoutSeconds}s',
                  onChanged: (v) {
                    s.setSttTimeout(v.round());
                    setState(() {});
                  },
                ),
              ),
              _settingsSlider(
                title: 'Correction / Translation timeout',
                valueText: '${s.llmTimeoutSeconds}s',
                slider: Slider(
                  value: s.llmTimeoutSeconds.toDouble().clamp(1, 60),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  label: '${s.llmTimeoutSeconds}s',
                  onChanged: (v) {
                    s.setLlmTimeout(v.round());
                    setState(() {});
                  },
                ),
              ),
              _settingsSlider(
                title: 'TTS timeout',
                valueText: '${s.ttsTimeoutSeconds}s',
                slider: Slider(
                  value: s.ttsTimeoutSeconds.toDouble().clamp(1, 60),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  label: '${s.ttsTimeoutSeconds}s',
                  onChanged: (v) {
                    s.setTtsTimeout(v.round());
                    setState(() {});
                  },
                ),
              ),
              _settingsSlider(
                title: 'History context for translation',
                valueText: s.historyContextCount == 0
                    ? 'off'
                    : '${s.historyContextCount}',
                slider: Slider(
                  value: s.historyContextCount.toDouble().clamp(0, 10),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: s.historyContextCount == 0
                      ? 'off'
                      : '${s.historyContextCount}',
                  onChanged: (v) {
                    s.setHistoryContextCount(v.round());
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.settings_outlined, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '控制中心',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '管理 provider、模型路由、语音和超时。',
                  style: TextStyle(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.72),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _settingsSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _settingsNotice({required IconData icon, required String text}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: cs.onTertiaryContainer, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSlider({
    required String title,
    required String valueText,
    required Widget slider,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          slider,
        ],
      ),
    );
  }

  Widget _providerCard(ProviderSpec p) {
    final s = widget.settings;
    final caps = <String>[
      if (p.hasCapability(Capability.chat)) 'Chat',
      if (p.hasCapability(Capability.stt)) 'STT',
      if (p.hasCapability(Capability.tts)) 'TTS',
    ].join(' · ');
    final cs = Theme.of(context).colorScheme;
    final hasKey = s.hasCredentials(p.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!hasKey) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'no API key',
                      style: TextStyle(
                        color: cs.onErrorContainer,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    caps,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final f in p.credentials) ...[
              TextField(
                controller: _credCtrl(p.id, f),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: f.label,
                  isDense: true,
                  prefixIcon: const Icon(Icons.lock_outline, size: 18),
                ),
                onChanged: (v) {
                  s.setCredential(p.id, f, v);
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ttsVoicePicker() {
    final s = widget.settings;
    final provider = findProvider(s.ttsProviderId);
    final model = provider?.findModel(s.ttsModelId);
    final voices = model?.voices ?? const <TtsVoice>[];
    if (voices.isEmpty) return const SizedBox.shrink();
    final value = voices.any((v) => v.id == s.ttsVoice)
        ? s.ttsVoice
        : voices.first.id;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Voice', isDense: true),
      items: voices
          .map(
            (v) => DropdownMenuItem(
              value: v.id,
              child: Text(
                v.lang == null ? v.label : '${v.label} — ${v.lang}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        s.setTtsVoice(v);
        setState(() {});
      },
    );
  }

  Widget _doubaoSpeechRate() {
    final s = widget.settings;
    return _settingsSlider(
      title: 'Speech rate',
      valueText:
          '${s.ttsVolcSpeechRate > 0 ? '+' : ''}${s.ttsVolcSpeechRate} / ${(1 + s.ttsVolcSpeechRate / 100).toStringAsFixed(2)}x',
      slider: Slider(
        value: s.ttsVolcSpeechRate.toDouble(),
        min: -50,
        max: 100,
        divisions: 30,
        label: '${s.ttsVolcSpeechRate}',
        onChanged: (v) {
          s.setTtsVolcSpeechRate(v.round());
          setState(() {});
        },
      ),
    );
  }
}
