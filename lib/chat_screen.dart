import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'catalog.dart';
import 'chat_conversation_controller.dart';
import 'chat_turn.dart';
import 'main.dart';
import 'providers.dart';
import 'scenes_screen.dart';
import 'settings.dart';
import 'settings_screen.dart';

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

  void _sendTypedText() {
    final text = _textInput.text.trim();
    if (text.isEmpty) return;
    _textInput.clear();
    _chat.sendTypedText(text);
  }

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickAndSendImage(ImageSource source) async {
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
      _showSnack('Image error: $e');
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

  Future<void> _openImageSheet() async {
    final s = widget.settings;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final imageProviders = s.imageProviders().toList();
            final effectivePid = s.effectiveImageProviderId;
            final effectiveMid = s.effectiveImageModelId;
            final overrideOn = s.imageProviderId != null;
            final canSend = s.imageInputAvailable;
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.image_outlined, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          '图片翻译',
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '提取图片中的文字并按 ${s.translationLangA} ↔ ${s.translationLangB} 翻译。',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('使用模型', style: Theme.of(ctx).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('指定单独的图片模型'),
                      subtitle: Text(
                        overrideOn
                            ? '已开启（不使用对话模型）'
                            : '关闭：跟随当前对话模型 (${s.chatModelId.isEmpty ? "未设置" : s.chatModelId})',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      value: overrideOn,
                      onChanged: (v) async {
                        if (v) {
                          // Default to first image-capable provider if any.
                          final firstPid = imageProviders.isEmpty
                              ? null
                              : imageProviders.first.id;
                          if (firstPid == null) {
                            setSheet(() {});
                            return;
                          }
                          await s.setImageProvider(firstPid);
                        } else {
                          await s.setImageProvider(null);
                        }
                        setSheet(() {});
                        if (mounted) setState(() {});
                      },
                    ),
                    if (overrideOn) ...[
                      DropdownButtonFormField<String>(
                        initialValue: s.imageProviderId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '提供商',
                          isDense: true,
                        ),
                        items: imageProviders
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          if (v == null) return;
                          await s.setImageProvider(v);
                          setSheet(() {});
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(height: 10),
                      Builder(
                        builder: (_) {
                          final pid = s.imageProviderId;
                          final provider = pid == null
                              ? null
                              : findProvider(pid);
                          final models = provider == null
                              ? const <ModelSpec>[]
                              : provider
                                    .modelsFor(Capability.chat)
                                    .where((m) => m.acceptsImage())
                                    .toList();
                          return DropdownButtonFormField<String>(
                            initialValue:
                                models.any((m) => m.id == s.imageModelId)
                                ? s.imageModelId
                                : (models.isEmpty ? null : models.first.id),
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '模型',
                              isDense: true,
                            ),
                            items: models
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m.id,
                                    child: Text(m.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) async {
                              if (v == null) return;
                              await s.setImageModel(v);
                              setSheet(() {});
                              if (mounted) setState(() {});
                            },
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 4),
                    if (!canSend)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Text(
                          overrideOn
                              ? '请选择一个支持图片输入的模型。'
                              : '当前对话模型不支持图片输入，请打开上面的开关挑选支持视觉的模型。',
                          style: TextStyle(
                            color: cs.error,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Text(
                          '将使用 $effectivePid · $effectiveMid',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: canSend
                                ? () async {
                                    Navigator.of(ctx).pop();
                                    await _pickAndSendImage(
                                      ImageSource.camera,
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('拍照'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: canSend
                                ? () async {
                                    Navigator.of(ctx).pop();
                                    await _pickAndSendImage(
                                      ImageSource.gallery,
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('从相册'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('Copied');
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
                  'VAD quick adjust',
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
                        'Conversation mode',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.continuousFullDuplex
                            ? 'Full-duplex keeps listening while replies can play.'
                            : 'Half-duplex pauses listening while the assistant replies.',
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
                  'Silence cutoff: ${s.vadPauseSeconds.toStringAsFixed(1)}s',
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
                  'Speech threshold: ${s.vadThresholdLevel.toStringAsFixed(1)}',
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
                  'Segments are cut after ${s.vadPauseSeconds.toStringAsFixed(1)}s of silence '
                  'below threshold, then auto-sent.',
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
                child: _PillButton(
                  icon: Icons.theater_comedy_outlined,
                  label: s.activeScene.name,
                  onTap: _openScenes,
                ),
              ),
              const SizedBox(width: 8),
              _IconPill(
                icon: Icons.image_outlined,
                onTap: _openImageSheet,
              ),
              const SizedBox(width: 8),
              _IconPill(icon: Icons.tune, onTap: _openConfigSheet),
            ],
          ),
          Divider(height: 18, color: cs.outlineVariant.withValues(alpha: 0.7)),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _TranslationRoutingToggle(
                  icon: Icons.translate,
                  label: '修正翻译',
                  languages: '${s.translationLangA} ↔ ${s.translationLangB}',
                  enabled: s.correctionEnabled,
                  onToggle: () async {
                    await s.setCorrectionEnabled(!s.correctionEnabled);
                    if (mounted) setState(() {});
                  },
                  onLanguagesTap: _openTranslationLanguageDialog,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RoutingToggle(
                  icon: Icons.graphic_eq,
                  label: audioDirectActive ? 'STT暂停' : 'STT',
                  tooltip: 'Speech-to-Text',
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
                  label: 'TTS',
                  tooltip: 'Text-to-Speech',
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
              title: const Text('Translation languages'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: s.translationLangA,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Language A',
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
                      labelText: 'Language B',
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
                              'Pick two different languages.',
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
                  child: const Text('Done'),
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
      title: '修正+翻译',
      subtitle: s.correctionEnabled
          ? 'Pick a language pair for corrected output'
          : 'Correction and translation are off',
      trailing: Switch(
        value: s.correctionEnabled,
        onChanged: (v) async {
          await s.setCorrectionEnabled(v);
          setM(() {});
          if (mounted) setState(() {});
        },
      ),
      child: Opacity(
        opacity: s.correctionEnabled ? 1 : 0.54,
        child: Column(
          children: [
            _sheetSwitch(
              title: 'Translate between languages',
              subtitle: 'Off keeps the correction-only mode.',
              value: s.translationEnabled,
              onChanged: !s.correctionEnabled || langsEqual
                  ? null
                  : (v) async {
                      await s.setTranslationEnabled(v);
                      setM(() {});
                      if (mounted) setState(() {});
                    },
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: s.translationLangA,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Language A',
                      isDense: true,
                    ),
                    items: kTranslationLanguages
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: !s.correctionEnabled
                        ? null
                        : (v) {
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
                      labelText: 'Language B',
                      isDense: true,
                    ),
                    items: kTranslationLanguages
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: !s.correctionEnabled
                        ? null
                        : (v) {
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
                      'Pick two different languages.',
                      style: TextStyle(color: cs.error, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
                                'Model routing',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Choose models for chat, speech, and playback.',
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
                      title: 'Speech-to-Text',
                      subtitle: audioDirectActive
                          ? 'Paused because Audio direct sends audio to Chat'
                          : 'Recognition provider for microphone input',
                      child: Opacity(
                        opacity: audioDirectActive ? 0.54 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (audioDirectActive) ...[
                              _sheetNotice(
                                icon: Icons.info_outline,
                                text:
                                    'Audio direct is on. STT is not used for voice turns, and this route is locked until Audio direct is off.',
                              ),
                              const SizedBox(height: 10),
                            ],
                            _ProviderModelPicker(
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
                      title: 'Chat',
                      subtitle: 'Assistant model and prompt handling',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ProviderModelPicker(
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
                            title: 'Include scene prompt',
                            subtitle:
                                'Attach the active scene to each chat turn.',
                            value: s.includeScenePrompt,
                            onChanged: (v) async {
                              await s.setIncludeScenePrompt(v);
                              setM(() {});
                              if (mounted) setState(() {});
                            },
                          ),
                          _sheetSwitch(
                            title: 'Audio direct',
                            subtitle: s.chatModelAcceptsAudio
                                ? 'Send recordings straight to chat and skip STT.'
                                : 'Current chat model has no audio input.',
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
                              title: 'Return original transcript',
                              subtitle:
                                  'Ask for JSON containing raw and final text.',
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
                      icon: Icons.volume_up_outlined,
                      title: 'Text-to-Speech',
                      subtitle: 'Voice model used for assistant replies',
                      child: _ProviderModelPicker(
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
      final label = t.fusedAudio ? 'Sending audio…' : 'Transcribing…';
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
          ? 'STT failed: ${_errorShort(t.lastError)}'
          : _sttErrorSummary(t.lastError);
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
          Text('Audio', style: TextStyle(color: cs.onPrimary, height: 1.35)),
        ],
      );
    } else if (t.imageInput) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          t.image!.bytes,
          width: 200,
          fit: BoxFit.cover,
          gaplessPlayback: true,
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
            t.state == TurnState.waitingLlm ? 'Queued…' : 'Thinking…',
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
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'Reply failed: ${_errorShort(t.lastError)}',
              style: TextStyle(color: cs.onErrorContainer, height: 1.35),
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
      final originalIsRich =
          original != null && original.trim().isNotEmpty;
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

  String _sttErrorSummary(Object? e) {
    if (e == null) return 'speech to text error';
    final s = e.toString();
    if (s.contains('20000003') || s.toLowerCase().contains('no valid speech')) {
      return 'no valid speech in audio body';
    }
    return 'speech to text error';
  }

  String _errorShort(Object? e) {
    if (e == null) return '';
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
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
                onSubmitted: (_) => _sendTypedText(),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
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
    final pendingSuffix = pending > 0 ? ' · $pending in flight' : '';
    if (mode == VoiceMode.pushToTalk) {
      final base = _chat.listening ? 'Release to send' : 'Hold to talk';
      return '$base$pendingSuffix';
    }
    // continuous mode
    if (s.continuousFullDuplex) {
      if (_chat.listening || _chat.autoRestarting) {
        final base = _chat.speakingNow
            ? 'Listening…'
            : 'Silent (auto-send on pause)';
        return '$base$pendingSuffix';
      }
      return 'Tap to start continuous listening$pendingSuffix';
    }
    // half-duplex inside continuous
    if (!_chat.continuousLoopActive) {
      return 'Tap to start half-duplex listening$pendingSuffix';
    }
    if (_chat.listening) {
      final base = _chat.speakingNow
          ? 'Listening…'
          : 'Silent (auto-send on pause)';
      return '$base$pendingSuffix';
    }
    if (_chat.ttsPlaying) return 'Speaking — mic paused$pendingSuffix';
    if (_chat.pipelineBusy) return 'Processing — mic paused$pendingSuffix';
    return 'Resuming…$pendingSuffix';
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('AI Chat'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear conversation',
            onPressed: () => unawaited(_chat.clearConversation()),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
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
