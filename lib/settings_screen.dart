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
      () => TextEditingController(text: widget.settings.credential(providerId, f)),
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
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Providers'),
          const SizedBox(height: 4),
          Text(
            'Each provider lists the credentials it requires. The same key is reused across Chat, STT, and TTS.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          for (final p in kCatalog) _providerCard(p),

          const SizedBox(height: 16),
          _sectionTitle('Chat'),
          const SizedBox(height: 8),
          _capabilityPicker(
            cap: Capability.chat,
            providerId: s.chatProviderId,
            modelId: s.chatModelId,
            onProvider: (id) => s.setChatProvider(id!),
            onModel: (id) => s.setChatModel(id),
            allowOff: false,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include scene prompt'),
            subtitle: const Text(
              'Inject the active scene\'s prompt into the chat system prompt. '
              'Has no effect on STT or TTS.',
            ),
            value: s.includeScenePrompt,
            onChanged: (v) {
              s.setIncludeScenePrompt(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Audio direct (skip STT)'),
            subtitle: Text(
              s.chatModelAcceptsAudio
                  ? 'Send the recording straight to the chat model. Replaces STT for this turn.'
                  : 'The current chat model does not accept audio input. Pick a model that does (e.g. Gemini, gpt-4o-audio-preview).',
              style: s.chatModelAcceptsAudio
                  ? null
                  : TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            value: s.audioDirectChat && s.chatModelAcceptsAudio,
            onChanged: s.chatModelAcceptsAudio
                ? (v) {
                    s.setAudioDirectChat(v);
                    setState(() {});
                  }
                : null,
          ),
          if (s.audioDirectActive)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Return original transcript (JSON)'),
                subtitle: const Text(
                  'Ask the model to return JSON with both the raw transcript '
                  'and the corrected/translated output. Transcript shows in '
                  'the user bubble.',
                ),
                value: s.audioDirectIncludeTranscript,
                onChanged: (v) {
                  s.setAudioDirectIncludeTranscript(v);
                  setState(() {});
                },
              ),
            ),

          const SizedBox(height: 16),
          _sectionTitle('Speech-to-Text'),
          const SizedBox(height: 8),
          _capabilityPicker(
            cap: Capability.stt,
            providerId: s.sttProviderId,
            modelId: s.sttModelId,
            onProvider: (id) => s.setSttProvider(id),
            onModel: (id) => s.setSttModel(id),
            allowOff: true,
          ),

          const SizedBox(height: 16),
          _sectionTitle('Text-to-Speech'),
          const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-speak assistant replies'),
              value: s.ttsAutoSpeak,
              onChanged: (v) {
                s.setTtsAutoSpeak(v);
                setState(() {});
              },
            ),
            if (s.ttsProviderId == 'volcengine') _doubaoSpeechRate(),
          ],

          const SizedBox(height: 24),
          _sectionTitle('Microphone'),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Acoustic echo cancellation'),
            subtitle: const Text(
              'Suppresses speaker → mic feedback during full-duplex playback. '
              'Uses iOS VoiceProcessingIO / Android AcousticEchoCanceler.',
            ),
            value: s.aecEnabled,
            onChanged: (v) {
              s.setAecEnabled(v);
              setState(() {});
            },
          ),

          const SizedBox(height: 16),
          _sectionTitle('Voice Activity Detection (VAD)'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pause before auto-stop'),
            subtitle: Slider(
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
            trailing: Text('${s.vadPauseSeconds.toStringAsFixed(1)}s'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Max listen duration'),
            subtitle: Slider(
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
            trailing: Text('${s.vadListenSeconds}s'),
          ),

          const SizedBox(height: 16),
          _sectionTitle('Timeouts'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('STT timeout'),
            subtitle: Slider(
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
            trailing: Text('${s.sttTimeoutSeconds}s'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Correction / Translation timeout'),
            subtitle: Slider(
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
            trailing: Text('${s.llmTimeoutSeconds}s'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('TTS timeout'),
            subtitle: Slider(
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
            trailing: Text('${s.ttsTimeoutSeconds}s'),
          ),

          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('History context for translation'),
            subtitle: Slider(
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
            trailing: Text(
              s.historyContextCount == 0 ? 'off' : '${s.historyContextCount}',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ignore recordings shorter than'),
            subtitle: Slider(
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
            trailing: Text('${s.minRecordSeconds.toStringAsFixed(1)}s'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) =>
      Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));

  Widget _providerCard(ProviderSpec p) {
    final s = widget.settings;
    final caps = <String>[
      if (p.hasCapability(Capability.chat)) 'Chat',
      if (p.hasCapability(Capability.stt)) 'STT',
      if (p.hasCapability(Capability.tts)) 'TTS',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text(caps,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            for (final f in p.credentials) ...[
              TextField(
                controller: _credCtrl(p.id, f),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: f.label,
                  border: const OutlineInputBorder(),
                  isDense: true,
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
            border: OutlineInputBorder(),
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
          Builder(builder: (_) {
            final models = selectedProvider.modelsFor(cap).toList();
            final value = models.any((m) => m.id == modelId)
                ? modelId
                : (models.isEmpty ? null : models.first.id);
            return DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: models
                  .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.label, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                onModel(v);
                setState(() {});
              },
            );
          }),
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
    final value = voices.any((v) => v.id == s.ttsVoice) ? s.ttsVoice : voices.first.id;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Voice',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: voices
          .map((v) => DropdownMenuItem(
                value: v.id,
                child: Text(
                  v.lang == null ? v.label : '${v.label} — ${v.lang}',
                  overflow: TextOverflow.ellipsis,
                ),
              ))
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Speech rate: ${s.ttsVolcSpeechRate > 0 ? '+' : ''}${s.ttsVolcSpeechRate} '
        '(${(1 + s.ttsVolcSpeechRate / 100).toStringAsFixed(2)}x)',
      ),
      subtitle: Slider(
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
