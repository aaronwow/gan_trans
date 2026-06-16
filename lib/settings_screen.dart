import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'provider_model_picker.dart';
import 'relay_catalog.dart';
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
  late final TextEditingController _relayBaseUrlCtrl;
  bool _relayFetching = false;
  bool _showAdditionalProviders = false;
  late final bool _showProviderQuickStart;

  @override
  void initState() {
    super.initState();
    _showProviderQuickStart = !widget.settings.hasAnyChatProviderCredentials;
    _relayBaseUrlCtrl = TextEditingController(
      text: widget.settings.relayBaseUrl,
    );
  }

  TextEditingController _credCtrl(String providerId, CredentialField f) {
    final key = '${providerId}__${f.name}';
    return _credCtrls.putIfAbsent(
      key,
      () => TextEditingController(
        text: widget.settings.credential(providerId, f),
      ),
    );
  }

  Future<void> _pasteCredential(String providerId, CredentialField f) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('剪贴板没有可粘贴的内容')));
      return;
    }
    final ctrl = _credCtrl(providerId, f);
    ctrl.text = text;
    ctrl.selection = TextSelection.collapsed(offset: text.length);
    await widget.settings.setCredential(providerId, f, text);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已从剪贴板粘贴并保存')));
  }

  Widget _credentialField({
    required String providerId,
    required CredentialField field,
    required String labelText,
    String? hintText,
  }) {
    final s = widget.settings;
    return TextField(
      controller: _credCtrl(providerId, field),
      obscureText: true,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        isDense: true,
        prefixIcon: const Icon(Icons.lock_outline, size: 18),
        suffixIcon: IconButton(
          tooltip: '从剪贴板粘贴',
          icon: const Icon(Icons.content_paste_outlined, size: 18),
          onPressed: () => _pasteCredential(providerId, field),
        ),
      ),
      onChanged: (v) async {
        await s.setCredential(providerId, field, v);
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _saveRelaySettings({bool showSnack = true}) async {
    final s = widget.settings;
    await s.setRelayBaseUrl(_relayBaseUrlCtrl.text);
    _relayBaseUrlCtrl.text = s.relayBaseUrl;
    await s.setCredential(
      kRelayProviderId,
      CredentialField.apiKey,
      _credCtrl(kRelayProviderId, CredentialField.apiKey).text,
    );
    if (!mounted) return;
    setState(() {});
    if (showSnack) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Relay 设置已保存')));
    }
  }

  @override
  void dispose() {
    _relayBaseUrlCtrl.dispose();
    for (final c in _credCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _heroHeader(),
          const SizedBox(height: 16),
          _settingsSection(
            icon: Icons.key_outlined,
            title: '服务商',
            subtitle: '各服务商的凭证会复用于对话、语音识别和语音播放。',
            children: [_providerSettingsList()],
          ),
          const SizedBox(height: 14),
          _settingsSection(
            icon: Icons.chat_bubble_outline,
            title: '对话',
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
                title: '带上场景提示词',
                subtitle: '每次对话请求都带上当前场景提示词。',
                value: s.includeScenePrompt,
                onChanged: (v) {
                  s.setIncludeScenePrompt(v);
                  setState(() {});
                },
              ),
              _settingsSwitch(
                title: '音频直连',
                subtitle: s.chatModelAcceptsAudio
                    ? '录音直接发送给对话模型，跳过语音识别。'
                    : '当前对话模型不支持音频输入，请换用支持音频的模型。',
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
                  title: '返回原始转录',
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
            icon: Icons.image_outlined,
            title: '图片翻译',
            subtitle: '图片文字识别和翻译使用的视觉模型。',
            children: [
              ImageModelRoutePicker(
                settings: s,
                onChanged: () {
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          _settingsSection(
            icon: Icons.graphic_eq,
            title: '语音识别',
            subtitle: s.audioDirectActive
                ? '音频直连已接管语音输入，语音识别暂停。'
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
                        text: '音频直连已开启：语音会直接发送给对话模型，关闭音频直连后才能调整语音识别。',
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
            title: '语音播放',
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
                  title: '自动朗读助手回复',
                  subtitle: '每次回复生成后自动播放语音。',
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
            title: '麦克风',
            subtitle: '录音滤波和语音活动检测。',
            children: [
              _settingsSwitch(
                title: '回声消除',
                subtitle: '降低全双工播放时扬声器回到麦克风的回声。',
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
            title: '响应限制',
            subtitle: '语音链路使用的超时和上下文窗口。',
            children: [
              _settingsSlider(
                title: '语音识别超时',
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
                title: '纠错和翻译超时',
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
                title: '语音播放超时',
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
                title: '翻译参考历史条数',
                valueText: s.historyContextCount == 0
                    ? '关闭'
                    : '${s.historyContextCount}',
                slider: Slider(
                  value: s.historyContextCount.toDouble().clamp(0, 10),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: s.historyContextCount == 0
                      ? '关闭'
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
                  '管理服务商、模型路由、语音和超时。',
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

  Widget _providerSettingsList() {
    final primary = kCatalog.firstWhere((p) => p.id == 'openrouter');
    final secondary = kCatalog.where((p) => p.id != primary.id).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showProviderQuickStart) _openRouterQuickStartCard(primary),
        if (!_showProviderQuickStart) _providerCard(primary),
        _additionalProvidersToggle(),
        if (_showAdditionalProviders) ...[
          const SizedBox(height: 10),
          _relayProviderCard(),
          const SizedBox(height: 10),
          for (final p in secondary) _providerCard(p),
        ],
      ],
    );
  }

  Widget _openRouterQuickStartCard(ProviderSpec p) {
    final s = widget.settings;
    final cs = Theme.of(context).colorScheme;
    final model =
        p.findModel(s.chatModelId) ?? p.modelsFor(Capability.chat).first;
    final isDefaultChat = s.chatProviderId == p.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.rocket_launch_outlined, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '快速开始：OpenRouter',
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '粘贴 API 密钥后会立即保存，默认对话模型已选为 ${model.label}。',
                        style: TextStyle(
                          color: cs.onPrimaryContainer.withValues(alpha: 0.75),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _credentialField(
              providerId: p.id,
              field: CredentialField.apiKey,
              labelText: 'OpenRouter 密钥',
              hintText: 'sk-or-...',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '也可以展开下方配置 AI Chat Relay、OpenAI、Gemini 等服务商。',
                    style: TextStyle(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.72),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
                if (!isDefaultChat) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await s.setChatProvider(p.id);
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('设为默认'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _additionalProvidersToggle() {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          _showAdditionalProviders = !_showAdditionalProviders;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              _showAdditionalProviders
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI Chat Relay 和其他服务商',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _relayProviderCard() {
    final s = widget.settings;
    final relay = s.relayProvider;
    final cs = Theme.of(context).colorScheme;
    final chatCount = relay?.modelsFor(Capability.chat).length ?? 0;
    final sttCount = relay?.modelsFor(Capability.stt).length ?? 0;
    final ttsCount = relay?.modelsFor(Capability.tts).length ?? 0;
    final status = relay == null
        ? '未抓取模型'
        : '已抓取 ${relay.models.length} 个模型 · 对话 $chatCount · 语音识别 $sttCount · 语音播放 $ttsCount';
    final fetchedAt = s.relayCatalogFetchedAt;
    final relayBaseUrlReady = _relayBaseUrlCtrl.text.trim().isNotEmpty;
    final relayApiKeyReady = _credCtrl(
      kRelayProviderId,
      CredentialField.apiKey,
    ).text.trim().isNotEmpty;
    final canFetchRelay = relayBaseUrlReady && relayApiKeyReady;
    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
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
                    'AI Chat Relay',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: '接口格式说明',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.help_outline, size: 18),
                  onPressed: _showRelayModelsHelp,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: relay == null ? cs.surface : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    relay == null ? '未加载' : '可用',
                    style: TextStyle(
                      color: relay == null
                          ? cs.onSurfaceVariant
                          : cs.onPrimaryContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _relayBaseUrlCtrl,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Relay 模型接口地址',
                hintText: kRelayBaseUrlExample,
                isDense: true,
                prefixIcon: Icon(Icons.link_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 8),
            _credentialField(
              providerId: kRelayProviderId,
              field: CredentialField.apiKey,
              labelText: 'Relay 密钥',
              hintText: 'sk-relay_...',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    fetchedAt == null
                        ? status
                        : '$status\n更新于 ${TimeOfDay.fromDateTime(fetchedAt).format(context)}',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _relayFetching
                      ? null
                      : () => _saveRelaySettings(showSnack: true),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: canFetchRelay
                      ? '抓取模型'
                      : '需要先填写 Relay 模型接口地址和 Relay 密钥',
                  child: FilledButton.icon(
                    onPressed: _relayFetching || !canFetchRelay
                        ? null
                        : () async {
                            setState(() => _relayFetching = true);
                            try {
                              await _saveRelaySettings(showSnack: false);
                              await s.refreshRelayCatalog();
                              if (!mounted) return;
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已抓取 ${s.relayProvider?.models.length ?? 0} 个 Relay 模型',
                                  ),
                                ),
                              );
                            } catch (e) {
                              s.relayCatalogError = e.toString();
                              if (!mounted) return;
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('抓取 Relay 模型失败：$e')),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _relayFetching = false);
                              }
                            }
                          },
                    icon: _relayFetching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_sync_outlined),
                    label: Text(_relayFetching ? '抓取中' : '抓取模型'),
                  ),
                ),
              ],
            ),
            if (s.relayCatalogError != null) ...[
              const SizedBox(height: 8),
              Text(
                s.relayCatalogError!,
                style: TextStyle(color: cs.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showRelayModelsHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Relay 模型接口'),
        content: const SingleChildScrollView(
          child: Text(
            '推荐填写完整接口，例如：\n'
            'https://relay.example.com/v1/models\n\n'
            '接口应返回兼容 OpenAI 的模型列表：\n'
            '{ "object": "list", "data": [ { "id": "model-id", "object": "model", "owned_by": "provider" } ] }\n\n'
            '如果要让应用识别语音、图片、语音播放等能力，可在 data[] 的每个模型对象里附加扩展字段：public_id、provider_id、display_name、capabilities、input_modalities、voices、stt_transport、supports_direct_audio_translate。\n\n'
            '没有 capabilities 字段时，应用会把模型按仅对话处理。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _providerCard(ProviderSpec p) {
    final s = widget.settings;
    final caps = <String>[
      if (p.hasCapability(Capability.chat)) '对话',
      if (p.hasCapability(Capability.stt)) '语音识别',
      if (p.hasCapability(Capability.tts)) '语音播放',
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
                      '缺少密钥',
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
              _credentialField(
                providerId: p.id,
                field: f,
                labelText: _credentialFieldLabel(f),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  String _credentialFieldLabel(CredentialField field) {
    switch (field) {
      case CredentialField.apiKey:
        return 'API 密钥';
      case CredentialField.appKey:
        return '应用密钥';
      case CredentialField.accessKey:
        return '访问密钥';
    }
  }

  Widget _ttsVoicePicker() {
    final s = widget.settings;
    final provider = s.findProvider(s.ttsProviderId);
    final model = provider?.findModel(s.ttsModelId);
    final voices = model?.voices ?? const <TtsVoice>[];
    if (voices.isEmpty) return const SizedBox.shrink();
    final value = voices.any((v) => v.id == s.ttsVoice)
        ? s.ttsVoice
        : voices.first.id;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '声音', isDense: true),
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
      title: '语速',
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
