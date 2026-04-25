import 'package:flutter/material.dart';

import 'catalog.dart';
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
            subtitle:
                'Credentials are reused across Chat, STT, and TTS for each provider.',
            children: [for (final p in kCatalog) _providerCard(p)],
          ),
          const SizedBox(height: 14),
          _settingsSection(
            icon: Icons.chat_bubble_outline,
            title: 'Chat',
            subtitle: 'Choose the assistant model and context behavior.',
            children: [
              _capabilityPicker(
                cap: Capability.chat,
                providerId: s.chatProviderId,
                modelId: s.chatModelId,
                onProvider: (id) => s.setChatProvider(id!),
                onModel: (id) => s.setChatModel(id),
                allowOff: false,
              ),
              const SizedBox(height: 10),
              _settingsSwitch(
                title: 'Include scene prompt',
                subtitle:
                    'Inject the active scene prompt into the chat system prompt.',
                value: s.includeScenePrompt,
                onChanged: (v) {
                  s.setIncludeScenePrompt(v);
                  setState(() {});
                },
              ),
              _settingsSwitch(
                title: 'Audio direct',
                subtitle: s.chatModelAcceptsAudio
                    ? 'Send recordings straight to chat and skip STT for that turn.'
                    : 'Current chat model has no audio input. Pick Gemini or an audio-capable OpenAI model.',
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
                  subtitle:
                      'Ask for JSON with the raw transcript and corrected output.',
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
            subtitle: 'Recognition model for microphone input.',
            children: [
              _capabilityPicker(
                cap: Capability.stt,
                providerId: s.sttProviderId,
                modelId: s.sttModelId,
                onProvider: (id) => s.setSttProvider(id),
                onModel: (id) => s.setSttModel(id),
                allowOff: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _settingsSection(
            icon: Icons.volume_up_outlined,
            title: 'Text-to-Speech',
            subtitle: 'Voice model and playback behavior.',
            children: [
              _capabilityPicker(
                cap: Capability.tts,
                providerId: s.ttsProviderId,
                modelId: s.ttsModelId,
                onProvider: (id) => s.setTtsProvider(id),
                onModel: (id) => s.setTtsModel(id),
                allowOff: true,
              ),
              if (s.ttsProviderId != null) ...[
                const SizedBox(height: 12),
                _ttsVoicePicker(),
                const SizedBox(height: 10),
                _settingsSwitch(
                  title: 'Auto-speak assistant replies',
                  subtitle:
                      'Play generated audio automatically after each reply.',
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
            subtitle: 'Recording filters and voice activity detection.',
            children: [
              _settingsSwitch(
                title: 'Acoustic echo cancellation',
                subtitle:
                    'Suppress speaker-to-mic feedback during full-duplex playback.',
                value: s.aecEnabled,
                onChanged: (v) {
                  s.setAecEnabled(v);
                  setState(() {});
                },
              ),
              _settingsSlider(
                title: 'Pause before auto-stop',
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
                title: 'Max listen duration',
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
                title: 'Ignore recordings shorter than',
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
            subtitle: 'Timeouts and context window used around voice turns.',
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
                  'Control center',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage providers, model routing, voice, and timeouts.',
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
                onChanged: (v) => s.setCredential(p.id, f, v),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _capabilityPicker({
    required Capability cap,
    required String? providerId,
    required String modelId,
    required ValueChanged<String?> onProvider,
    required ValueChanged<String> onModel,
    required bool allowOff,
  }) {
    final providers = providersFor(cap).toList();
    final selectedProvider = findProvider(providerId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: providerId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Provider',
            isDense: true,
          ),
          items: [
            if (allowOff)
              const DropdownMenuItem<String?>(value: null, child: Text('Off')),
            for (final p in providers)
              DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) {
            onProvider(v);
            setState(() {});
          },
        ),
        if (selectedProvider != null) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (_) {
              final models = selectedProvider.modelsFor(cap).toList();
              final value = models.any((m) => m.id == modelId)
                  ? modelId
                  : (models.isEmpty ? null : models.first.id);
              return DropdownButtonFormField<String>(
                initialValue: value,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  isDense: true,
                ),
                items: models
                    .map(
                      (m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  onModel(v);
                  setState(() {});
                },
              );
            },
          ),
        ],
      ],
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
