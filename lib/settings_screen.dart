import 'package:flutter/material.dart';
import 'providers.dart';
import 'settings.dart';
import 'stt_service.dart';
import 'tts_service.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _openAi;
  late final TextEditingController _gemini;
  late final TextEditingController _volcAppKey;
  late final TextEditingController _volcAccessKey;

  @override
  void initState() {
    super.initState();
    _openAi = TextEditingController(text: widget.settings.openAiKey);
    _gemini = TextEditingController(text: widget.settings.geminiKey);
    _volcAppKey = TextEditingController(text: widget.settings.volcAppKey);
    _volcAccessKey =
        TextEditingController(text: widget.settings.volcAccessKey);
  }

  @override
  void dispose() {
    _openAi.dispose();
    _gemini.dispose();
    _volcAppKey.dispose();
    _volcAccessKey.dispose();
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
          const Text('API Keys', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            controller: _openAi,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'OpenAI API Key',
              border: OutlineInputBorder(),
            ),
            onChanged: s.setOpenAiKey,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gemini,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Gemini API Key',
              border: OutlineInputBorder(),
            ),
            onChanged: s.setGeminiKey,
          ),
          const SizedBox(height: 24),
          const Text('Correction + Translation Model',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'Used when the "修正+翻译" toggle is on in the chat top bar.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ProviderKind>(
            value: s.translationProvider,
            decoration: const InputDecoration(
              labelText: 'Provider',
              border: OutlineInputBorder(),
            ),
            items: kProviders
                .map((p) => DropdownMenuItem(value: p.kind, child: Text(p.name)))
                .toList(),
            onChanged: (v) {
              s.setTranslationProvider(v!);
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final models = providerOf(s.translationProvider).suggestedModels;
            final value = models.contains(s.translationModel)
                ? s.translationModel
                : models.first;
            return DropdownButtonFormField<String>(
              value: value,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
              ),
              items: models
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                s.setTranslationModel(v);
                setState(() {});
              },
            );
          }),
          const SizedBox(height: 24),
          const Text('Text-to-Speech', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          DropdownButtonFormField<TtsMode>(
            value: s.ttsMode,
            decoration: const InputDecoration(
              labelText: 'TTS Mode',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: TtsMode.off, child: Text('Off')),
              DropdownMenuItem(
                  value: TtsMode.openai, child: Text('OpenAI (gpt-4o-mini-tts)')),
              DropdownMenuItem(
                  value: TtsMode.volcDoubao,
                  child: Text('Volcengine 豆包 (seed-tts-2.0)')),
            ],
            onChanged: (v) { s.setTtsMode(v!); setState(() {}); },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-speak assistant replies'),
            value: s.ttsAutoSpeak,
            onChanged: s.ttsMode == TtsMode.off
                ? null
                : (v) { s.setTtsAutoSpeak(v); setState(() {}); },
          ),
          if (s.ttsMode == TtsMode.openai) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: kOpenAiTtsModels.contains(s.ttsOpenAiModel)
                  ? s.ttsOpenAiModel
                  : kOpenAiTtsModels.first,
              decoration: const InputDecoration(
                labelText: 'OpenAI TTS Model',
                border: OutlineInputBorder(),
              ),
              items: kOpenAiTtsModels
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) { s.setTtsOpenAiModel(v!); setState(() {}); },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: kOpenAiTtsVoices.contains(s.ttsOpenAiVoice)
                  ? s.ttsOpenAiVoice
                  : kOpenAiTtsVoices.first,
              decoration: const InputDecoration(
                labelText: 'OpenAI TTS Voice',
                border: OutlineInputBorder(),
              ),
              items: kOpenAiTtsVoices
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) { s.setTtsOpenAiVoice(v!); setState(() {}); },
            ),
          ],
          if (s.ttsMode == TtsMode.volcDoubao) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: kDoubaoVoices.any((e) => e.value == s.ttsVolcSpeaker)
                  ? s.ttsVolcSpeaker
                  : kDoubaoVoices.first.value,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Doubao Voice',
                border: OutlineInputBorder(),
              ),
              items: kDoubaoVoices
                  .map((v) => DropdownMenuItem(
                        value: v.value,
                        child: Text('${v.label} — ${v.lang}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                s.setTtsVolcSpeaker(v!);
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            ListTile(
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
            ),
            const SizedBox(height: 8),
            Text(
              'Uses the Volcengine AppKey/AccessKey configured in the STT section.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text('OpenAI STT model',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: kOpenAiSttModels.contains(s.sttOpenAiModel)
                ? s.sttOpenAiModel
                : kOpenAiSttModels.first,
            decoration: const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
            ),
            items: kOpenAiSttModels
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) { s.setSttOpenAiModel(v!); setState(() {}); },
          ),
          const SizedBox(height: 8),
          Text(
            'Used when STT is set to OpenAI. API key comes from the OpenAI key above.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          const Text('Volcengine 豆包 (STT + TTS)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Credentials are shared between 豆包 STT and 豆包 TTS.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            obscureText: true,
            controller: _volcAppKey,
            decoration: const InputDecoration(
              labelText: 'AppKey (X-Api-App-Key)',
              border: OutlineInputBorder(),
            ),
            onChanged: s.setVolcAppKey,
          ),
          const SizedBox(height: 12),
          TextField(
            obscureText: true,
            controller: _volcAccessKey,
            decoration: const InputDecoration(
              labelText: 'AccessKey (X-Api-Access-Key)',
              border: OutlineInputBorder(),
            ),
            onChanged: s.setVolcAccessKey,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: kVolcSttResourceIds.any((o) => o.value == s.volcResourceId)
                ? s.volcResourceId
                : kVolcSttResourceIds.first.value,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'STT Resource ID',
              border: OutlineInputBorder(),
            ),
            items: kVolcSttResourceIds
                .map((o) => DropdownMenuItem(
                      value: o.value,
                      child: Text(o.label, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              s.setVolcResourceId(v);
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: kDoubaoTtsResourceIds.any((o) => o.value == s.ttsVolcResourceId)
                ? s.ttsVolcResourceId
                : kDoubaoTtsResourceIds.first.value,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'TTS Resource ID',
              border: OutlineInputBorder(),
            ),
            items: kDoubaoTtsResourceIds
                .map((o) => DropdownMenuItem(
                      value: o.value,
                      child: Text(o.label, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              s.setTtsVolcResourceId(v);
              setState(() {});
            },
          ),
          const SizedBox(height: 24),
          const Text('Microphone',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
          const SizedBox(height: 24),
          const Text('Voice Activity Detection (VAD)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
              onChanged: (v) { s.setVadListen(v.round()); setState(() {}); },
            ),
            trailing: Text('${s.vadListenSeconds}s'),
          ),
          const SizedBox(height: 16),
          const Text('Timeouts',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
}
