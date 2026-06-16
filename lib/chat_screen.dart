import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'catalog.dart';
import 'chat_conversation_controller.dart';
import 'chat_turn.dart';
import 'main.dart';
import 'provider_model_picker.dart';
import 'providers.dart';
import 'scenes_screen.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'user_messages.dart';

part 'chat_widgets.dart';

class ChatScreen extends StatefulWidget {
  final AppSettings settings;
  const ChatScreen({super.key, required this.settings});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin, RouteAware {
  final _scroll = ScrollController();
  final _textInput = TextEditingController();

  late final ChatConversationController _chat;
  late final AnimationController _pulse;
  bool _cancelArmed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _chat = ChatConversationController(
      settings: widget.settings,
      onMessage: _showSnack,
      onScrollToBottom: _scrollToBottom,
    )..addListener(_onChatChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  // ---------- Route lifecycle ----------

  // Pause the mic loop when another screen (e.g. Settings) covers us, so the
  // recorder can't desync from the lit "continuous" button while we're hidden.
  @override
  void didPushNext() {
    _chat.didPushNext();
  }

  @override
  void didPopNext() {
    _chat.didPopNext();
  }

  void _onChatChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _chat.removeListener(_onChatChanged);
    _chat.dispose();
    _pulse.dispose();
    _scroll.dispose();
    _textInput.dispose();
    super.dispose();
  }

  Future<void> _sendTypedText() async {
    final text = _textInput.text.trim();
    if (text.isNotEmpty) {
      _textInput.clear();
      _chat.sendTypedText(text);
      return;
    }

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final clipboardText = data?.text?.trim() ?? '';
      if (clipboardText.isEmpty) {
        _showSnack('剪贴板没有可发送的文字');
        return;
      }
      _chat.sendTypedText(clipboardText);
    } catch (e) {
      _showSnack('无法读取剪贴板：$e');
    }
  }

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (!widget.settings.imageInputAvailable) {
      _showSnack('图片模型未配置，请在模型路由或设置里选择支持图片输入的模型');
      return;
    }
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 88,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final format = _detectImageFormat(picked.name, bytes);
      _chat.sendImage(ChatImage(bytes: bytes, format: format));
    } catch (e) {
      if (!mounted) return;
      _showSnack(compactUserError(e, fallback: '图片读取失败'));
    }
  }

  String _detectImageFormat(String name, Uint8List bytes) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.gif')) return 'gif';
    if (lower.endsWith('.heic')) return 'heic';
    if (lower.endsWith('.heif')) return 'heif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    // Fall back to magic-byte sniffing for picker-supplied paths without ext.
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45) {
      return 'webp';
    }
    return 'jpg';
  }

  void _scrollToBottom() {
    void scroll() {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scroll();
      WidgetsBinding.instance.addPostFrameCallback((_) => scroll());
    });
  }

  void _showSnack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('已复制');
  }

  Future<void> _toggleVoiceMode() async {
    await _chat.toggleVoiceMode();
  }

  Future<void> _openVadQuickAdjust() async {
    final s = widget.settings;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (ctx, setM) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '语音检测快速调整',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '对话模式',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.continuousFullDuplex
                            ? '全双工：播放回复时继续监听。'
                            : '半双工：处理和播放回复时暂停麦克风。',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: _DuplexFilter(
                          fullDuplex: s.continuousFullDuplex,
                          onChanged: (v) async {
                            await s.setContinuousFullDuplex(v);
                            setM(() {});
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '静音切分：${s.vadPauseSeconds.toStringAsFixed(1)}s',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Slider(
                  min: 0.1,
                  max: 5,
                  divisions: 49,
                  value: s.vadPauseSeconds.clamp(0.1, 5.0),
                  label: '${s.vadPauseSeconds.toStringAsFixed(1)}s',
                  onChanged: (v) {
                    s.setVadPause(double.parse(v.toStringAsFixed(1)));
                    setM(() {});
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '语音阈值：${s.vadThresholdLevel.toStringAsFixed(1)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Slider(
                  min: 0.5,
                  max: 6,
                  divisions: 55,
                  value: s.vadThresholdLevel.clamp(0.5, 6.0),
                  label: s.vadThresholdLevel.toStringAsFixed(1),
                  onChanged: (v) {
                    s.setVadThresholdLevel(v);
                    setM(() {});
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  '低于阈值并静音 ${s.vadPauseSeconds.toStringAsFixed(1)}s 后会自动切分并发送。',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- Top control strip ----------

  Widget _topBar() {
    final s = widget.settings;
    final cs = Theme.of(context).colorScheme;
    final audioDirectActive = s.audioDirectActive;
    final langsEqual = s.translationLangA == s.translationLangB;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _ScenePill(
                  icon: Icons.theater_comedy_outlined,
                  label: s.activeScene.name,
                  onTap: _openScenes,
                ),
              ),
              const SizedBox(width: 8),
              _IconPill(
                icon: Icons.photo_library_outlined,
                tooltip: '从相册选择图片翻译',
                onTap: () => _pickAndSendImage(ImageSource.gallery),
              ),
              const SizedBox(width: 8),
              _IconPill(
                icon: Icons.photo_camera_outlined,
                tooltip: '拍照翻译',
                onTap: () => _pickAndSendImage(ImageSource.camera),
              ),
              const SizedBox(width: 8),
              _IconPill(
                icon: Icons.tune,
                tooltip: '模型与语音快调',
                onTap: _openConfigSheet,
              ),
            ],
          ),
          Divider(height: 18, color: cs.outlineVariant.withValues(alpha: 0.7)),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _LanguagePill(
                  label: '${s.translationLangA} ↔ ${s.translationLangB}',
                  enabled: !langsEqual,
                  onTap: _openTranslationLanguageDialog,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RoutingToggle(
                  icon: Icons.graphic_eq,
                  label: audioDirectActive ? '识别暂停' : '识别',
                  tooltip: '语音识别',
                  enabled: s.sttProviderId != null && !audioDirectActive,
                  interactive: !audioDirectActive,
                  onTap: () async {
                    await s.setSttEnabled(s.sttProviderId == null);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RoutingToggle(
                  icon: Icons.volume_up_outlined,
                  label: '朗读',
                  tooltip: '语音播放',
                  enabled: s.ttsProviderId != null,
                  onTap: () async {
                    await s.setTtsEnabled(s.ttsProviderId == null);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openTranslationLanguageDialog() async {
    final s = widget.settings;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setD) {
            final langsEqual = s.translationLangA == s.translationLangB;
            return AlertDialog(
              title: const Text('翻译语言'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: s.translationLangA,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '语言 A',
                      isDense: true,
                    ),
                    items: kTranslationLanguages
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      await s.setTranslationLangA(v);
                      setD(() {});
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: s.translationLangB,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '语言 B',
                      isDense: true,
                    ),
                    items: kTranslationLanguages
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      await s.setTranslationLangB(v);
                      setD(() {});
                      if (mounted) setState(() {});
                    },
                  ),
                  if (langsEqual)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: cs.error),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '请选择两个不同的语言。',
                              style: TextStyle(color: cs.error, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _translationSection(
    AppSettings s,
    ColorScheme cs,
    StateSetter setM,
    bool langsEqual,
  ) {
    return _sheetSection(
      icon: Icons.translate,
      title: '双向翻译',
      subtitle: '修正和双向翻译始终开启，选择输出语言方向。',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: s.translationLangA,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '语言 A',
                    isDense: true,
                  ),
                  items: kTranslationLanguages
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    s.setTranslationLangA(v);
                    setM(() {});
                    if (mounted) setState(() {});
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.swap_horiz,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: s.translationLangB,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '语言 B',
                    isDense: true,
                  ),
                  items: kTranslationLanguages
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    s.setTranslationLangB(v);
                    setM(() {});
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
          if (langsEqual)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: cs.error),
                  const SizedBox(width: 6),
                  Text(
                    '请选择两个不同的语言。',
                    style: TextStyle(color: cs.error, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openScenes() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScenesScreen(settings: widget.settings),
      ),
    );
  }

  Future<void> _openConfigSheet() async {
    final s = widget.settings;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.42,
          maxChildSize: 0.94,
          builder: (ctx, scrollController) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (ctx, setM) {
                final langsEqual = s.translationLangA == s.translationLangB;
                final audioDirectActive = s.audioDirectActive;
                return ListView(
                  controller: scrollController,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.tune,
                            color: cs.onPrimaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '模型路由',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '快速选择对话、图片、语音识别和语音播放路由。',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _translationSection(s, cs, setM, langsEqual),
                    const SizedBox(height: 12),
                    _sheetSection(
                      icon: Icons.graphic_eq,
                      title: '语音识别',
                      subtitle: audioDirectActive
                          ? '音频直连已接管语音输入，语音识别暂停'
                          : '麦克风输入使用的识别服务商',
                      child: Opacity(
                        opacity: audioDirectActive ? 0.54 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (audioDirectActive) ...[
                              _sheetNotice(
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
                              enabled: !audioDirectActive,
                              onProvider: (id) async {
                                await s.setSttProvider(id);
                                setM(() {});
                                if (mounted) setState(() {});
                              },
                              onModel: (id) async {
                                await s.setSttModel(id);
                                setM(() {});
                                if (mounted) setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sheetSection(
                      icon: Icons.chat_bubble_outline,
                      title: '对话',
                      subtitle: '对话模型和提示词处理',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ProviderModelPicker(
                            settings: s,
                            cap: Capability.chat,
                            providerId: s.chatProviderId,
                            modelId: s.chatModelId,
                            allowOff: false,
                            onProvider: (id) async {
                              await s.setChatProvider(id!);
                              setM(() {});
                              if (mounted) setState(() {});
                            },
                            onModel: (id) async {
                              await s.setChatModel(id);
                              setM(() {});
                              if (mounted) setState(() {});
                            },
                          ),
                          const SizedBox(height: 10),
                          _sheetSwitch(
                            title: '带上场景提示词',
                            subtitle: '每次对话请求都带上当前场景提示词。',
                            value: s.includeScenePrompt,
                            onChanged: (v) async {
                              await s.setIncludeScenePrompt(v);
                              setM(() {});
                              if (mounted) setState(() {});
                            },
                          ),
                          _sheetSwitch(
                            title: '音频直连',
                            subtitle: s.chatModelAcceptsAudio
                                ? '录音直接发送给对话模型，跳过语音识别。'
                                : '当前对话模型不支持音频输入，请换用支持音频的模型。',
                            value: s.audioDirectChat && s.chatModelAcceptsAudio,
                            onChanged: s.chatModelAcceptsAudio
                                ? (v) async {
                                    await s.setAudioDirectChat(v);
                                    setM(() {});
                                    if (mounted) setState(() {});
                                  }
                                : null,
                          ),
                          if (s.audioDirectActive)
                            _sheetSwitch(
                              title: '返回原始转录',
                              subtitle: '要求模型返回原始转录和最终输出。',
                              value: s.audioDirectIncludeTranscript,
                              onChanged: (v) async {
                                await s.setAudioDirectIncludeTranscript(v);
                                setM(() {});
                                if (mounted) setState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sheetSection(
                      icon: Icons.image_outlined,
                      title: '图片翻译',
                      subtitle: '图片文字识别和翻译使用的视觉模型',
                      child: ImageModelRoutePicker(
                        settings: s,
                        onChanged: () {
                          setM(() {});
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sheetSection(
                      icon: Icons.volume_up_outlined,
                      title: '语音播放',
                      subtitle: '助手回复使用的语音播放模型',
                      child: ProviderModelPicker(
                        settings: s,
                        cap: Capability.tts,
                        providerId: s.ttsProviderId,
                        modelId: s.ttsModelId,
                        allowOff: true,
                        onProvider: (id) async {
                          await s.setTtsProvider(id);
                          setM(() {});
                          if (mounted) setState(() {});
                        },
                        onModel: (id) async {
                          await s.setTtsModel(id);
                          setM(() {});
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettingsScreen(settings: s),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('进入完整设置'),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _sheetSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
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
                  color: cs.secondaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: cs.onSecondaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
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
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _sheetSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
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

  Widget _sheetNotice({required IconData icon, required String text}) {
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

  // ---------- Messages ----------

  List<Widget> _turnWidgets(ChatTurn t) {
    final widgets = <Widget>[_userBubble(t)];
    final hasUserText = t.userText != null && t.userText!.isNotEmpty;
    final showAssistant =
        (hasUserText || t.fusedAudio || t.imageInput) &&
        t.state != TurnState.sttError;
    if (showAssistant) widgets.add(_assistantBubble(t));
    return widgets;
  }

  Widget _userBubble(ChatTurn t) {
    final cs = Theme.of(context).colorScheme;
    final text = t.userText;
    final isError = t.state == TurnState.sttError;
    final isPending =
        t.state == TurnState.transcribing ||
        (t.fusedAudio && t.state == TurnState.sending);
    Widget content;
    if (isPending) {
      final label = t.fusedAudio ? '正在发送音频…' : '正在识别语音…';
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(cs.onPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: cs.onPrimary, height: 1.35)),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _chat.cancelTurn(t),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 16, color: cs.onPrimary),
            ),
          ),
        ],
      );
    } else if (isError) {
      final errText = t.errorExpanded
          ? expandedUserError(t.lastError, fallback: '语音识别失败')
          : compactUserError(t.lastError, fallback: '语音识别失败');
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => t.errorExpanded = !t.errorExpanded),
              child: Text(
                errText,
                style: TextStyle(color: cs.onErrorContainer, height: 1.35),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _chat.retryTurn(t),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.refresh, size: 18, color: cs.onErrorContainer),
            ),
          ),
        ],
      );
    } else if (t.fusedAudio && (text == null || text.isEmpty)) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, size: 16, color: cs.onPrimary),
          const SizedBox(width: 6),
          Text('音频', style: TextStyle(color: cs.onPrimary, height: 1.35)),
        ],
      );
    } else if (t.imageInput) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 200,
          height: 150,
          child: ColoredBox(
            color: cs.primaryContainer.withValues(alpha: 0.28),
            child: Image.memory(
              t.image!.bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    } else {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: text == null ? null : () => _copyMessage(text),
        onLongPress: text == null ? null : () => _copyMessage(text),
        child: Text(
          text ?? '',
          style: TextStyle(color: cs.onPrimary, height: 1.35),
        ),
      );
    }
    final bg = isError ? cs.errorContainer : cs.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _assistantBubble(ChatTurn t) {
    final cs = Theme.of(context).colorScheme;
    final ttsEnabled = widget.settings.ttsProviderId != null;
    final isSpeakingThis = _chat.speakingTurnId == t.id;
    final isError = t.state == TurnState.llmError;
    final isPending =
        t.state == TurnState.waitingLlm || t.state == TurnState.sending;
    final text = t.assistantText;

    Widget content;
    if (isPending) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            t.state == TurnState.waitingLlm ? '排队中…' : '思考中…',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _chat.cancelTurn(t),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    } else if (isError) {
      final errText = t.errorExpanded
          ? expandedUserError(t.lastError, fallback: '回复失败')
          : compactUserError(t.lastError, fallback: '回复失败');
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => t.errorExpanded = !t.errorExpanded),
              child: Text(
                errText,
                style: TextStyle(color: cs.onErrorContainer, height: 1.35),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _chat.retryTurn(t),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.refresh, size: 18, color: cs.onErrorContainer),
            ),
          ),
        ],
      );
    } else if (t.imageInput) {
      // For image turns we render two sections: 原文 (extracted) and 译文.
      // The model is asked to emit a stable separator; if it's missing we fall
      // back to a single block so the user still sees the raw reply.
      final original = t.normalizedTranscript ?? t.rawTranscript;
      final output = t.translatedText ?? text ?? '';
      final originalIsRich = original != null && original.trim().isNotEmpty;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (originalIsRich) ...[
            Text(
              '原文',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _copyMessage(original),
              onLongPress: () => _copyMessage(original),
              child: Text(
                original,
                style: TextStyle(color: cs.onSurface, height: 1.35),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            Text(
              '译文',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
          ],
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _copyMessage(output),
            onLongPress: () => _copyMessage(output),
            child: Text(
              output,
              style: TextStyle(color: cs.onSurface, height: 1.35),
            ),
          ),
        ],
      );
    } else {
      final textWidget = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: text == null ? null : () => _copyMessage(text),
        onLongPress: text == null ? null : () => _copyMessage(text),
        child: Text(
          text ?? '',
          style: TextStyle(color: cs.onSurface, height: 1.35),
        ),
      );
      if (ttsEnabled && text != null && text.isNotEmpty) {
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: textWidget),
            const SizedBox(width: 8),
            InkWell(
              onTap: isSpeakingThis
                  ? _chat.stopSpeaking
                  : () {
                      _chat.cancelTtsQueue();
                      _chat.speakText(text, turnId: t.id);
                    },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  isSpeakingThis
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                  size: 20,
                  color: isSpeakingThis ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      } else {
        content = textWidget;
      }
    }

    final bg = isError ? cs.errorContainer : cs.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primaryContainer,
            child: Icon(Icons.auto_awesome, size: 16, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Bottom mic ----------

  Widget _bottomBar() {
    final s = widget.settings;
    final cs = Theme.of(context).colorScheme;
    if (!s.voiceInputAvailable) return _textInputBar();
    final isContinuous = s.voiceMode == VoiceMode.continuous;
    final isHalfDuplex = isContinuous && !s.continuousFullDuplex;
    final status = _statusLabel(s.voiceMode);

    final modeButton = _ModeToggleButton(
      mode: s.voiceMode,
      onTap: _toggleVoiceMode,
    );
    final mic = Expanded(
      child: _MicBar(
        listening:
            _chat.listening ||
            (isContinuous && s.continuousFullDuplex && _chat.autoRestarting) ||
            (isHalfDuplex && _chat.continuousLoopActive),
        enabled: true,
        continuous: isContinuous,
        level: _chat.soundLevel,
        pulse: _pulse,
        showGear: isContinuous,
        onGearTap: _openVadQuickAdjust,
        onPressStart: isContinuous ? null : _chat.startListening,
        onPressEnd: isContinuous ? null : _chat.cutAndProcess,
        onCancel: isContinuous ? null : _chat.cancelHoldToTalk,
        onCancelArmedChanged: isContinuous
            ? null
            : (v) {
                if (_cancelArmed == v) return;
                setState(() => _cancelArmed = v);
              },
        onTap: isContinuous ? _chat.toggleContinuousListening : null,
      ),
    );

    final statusLine = _cancelArmed
        ? Text(
            '上滑已激活：松开即可取消发送',
            style: TextStyle(
              color: cs.error,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          )
        : Text(
            status,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          );

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isContinuous && (_chat.listening || _chat.autoRestarting))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _LevelMeter(
                  level: _chat.soundLevel,
                  threshold: s.vadThresholdLevel,
                  speaking: _chat.speakingNow,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: statusLine,
            ),
            Row(
              children: isContinuous
                  ? [mic, const SizedBox(width: 12), modeButton]
                  : [modeButton, const SizedBox(width: 12), mic],
            ),
          ],
        ),
      ),
    );
  }

  Widget _textInputBar() {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _textInput,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => _sendTypedText(),
                decoration: InputDecoration(
                  hintText: '输入文字…',
                  isDense: true,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _sendTypedText,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(14),
              ),
              child: const Icon(Icons.send, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(VoiceMode mode) {
    final s = widget.settings;
    final pending = _chat.turns
        .where(
          (t) =>
              t.state == TurnState.transcribing ||
              t.state == TurnState.waitingLlm ||
              t.state == TurnState.sending,
        )
        .length;
    final pendingSuffix = pending > 0 ? ' · $pending 个处理中' : '';
    if (mode == VoiceMode.pushToTalk) {
      final base = _chat.listening ? '松开发送' : '按住说话';
      return '$base$pendingSuffix';
    }
    // continuous mode
    if (s.continuousFullDuplex) {
      if (_chat.listening || _chat.autoRestarting) {
        final base = _chat.speakingNow ? '正在监听…' : '静音中（停顿后自动发送）';
        return '$base$pendingSuffix';
      }
      return '点击开始连续监听$pendingSuffix';
    }
    // half-duplex inside continuous
    if (!_chat.continuousLoopActive) {
      return '点击开始半双工连续监听$pendingSuffix';
    }
    if (_chat.listening) {
      final base = _chat.speakingNow ? '正在监听…' : '静音中（停顿后自动发送）';
      return '$base$pendingSuffix';
    }
    if (_chat.ttsPlaying) return '正在播放语音，麦克风暂停$pendingSuffix';
    if (_chat.pipelineBusy) return '处理中，麦克风暂停$pendingSuffix';
    return '正在恢复监听…$pendingSuffix';
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('GanTrans'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '新对话',
            onPressed: () => unawaited(_chat.clearConversation()),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '完整设置',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(settings: widget.settings),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: _chat.turns.isEmpty
                ? _EmptyState(sceneName: widget.settings.activeScene.name)
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [for (final t in _chat.turns) ..._turnWidgets(t)],
                  ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }
}
