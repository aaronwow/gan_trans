import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'catalog.dart';
import 'chat_conversation_controller.dart';
import 'chat_turn.dart';
import 'main.dart';
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
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PillButton(
              icon: Icons.theater_comedy_outlined,
              label: s.activeScene.name,
              onTap: _openScenes,
            ),
          ),
          const SizedBox(width: 8),
          _IconPill(icon: Icons.tune, onTap: _openConfigSheet),
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
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setM) {
              final langsEqual = s.translationLangA == s.translationLangB;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sheetSection(
                      'Chat',
                      Column(
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
                            },
                            onModel: (id) async {
                              await s.setChatModel(id);
                              setM(() {});
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Include scene prompt'),
                            value: s.includeScenePrompt,
                            onChanged: (v) async {
                              await s.setIncludeScenePrompt(v);
                              setM(() {});
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Audio direct (skip STT)'),
                            subtitle: s.chatModelAcceptsAudio
                                ? null
                                : const Text(
                                    'Current chat model has no audio input.',
                                    style: TextStyle(fontSize: 11),
                                  ),
                            value: s.audioDirectChat && s.chatModelAcceptsAudio,
                            onChanged: s.chatModelAcceptsAudio
                                ? (v) async {
                                    await s.setAudioDirectChat(v);
                                    setM(() {});
                                  }
                                : null,
                          ),
                          if (s.audioDirectActive)
                            Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text(
                                  'Return original transcript (JSON)',
                                ),
                                value: s.audioDirectIncludeTranscript,
                                onChanged: (v) async {
                                  await s.setAudioDirectIncludeTranscript(v);
                                  setM(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 28),
                    _sheetSection(
                      'Speech-to-Text',
                      _ProviderModelPicker(
                        cap: Capability.stt,
                        providerId: s.sttProviderId,
                        modelId: s.sttModelId,
                        allowOff: true,
                        onProvider: (id) async {
                          await s.setSttProvider(id);
                          setM(() {});
                        },
                        onModel: (id) async {
                          await s.setSttModel(id);
                          setM(() {});
                        },
                      ),
                    ),
                    const Divider(height: 28),
                    _sheetSection(
                      'Text-to-Speech',
                      _ProviderModelPicker(
                        cap: Capability.tts,
                        providerId: s.ttsProviderId,
                        modelId: s.ttsModelId,
                        allowOff: true,
                        onProvider: (id) async {
                          await s.setTtsProvider(id);
                          setM(() {});
                        },
                        onModel: (id) async {
                          await s.setTtsModel(id);
                          setM(() {});
                        },
                      ),
                    ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        const Text(
                          '修正+翻译',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Switch(
                          value: s.translationEnabled,
                          onChanged: langsEqual
                              ? null
                              : (v) {
                                  s.setTranslationEnabled(v);
                                  setM(() {});
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: s.translationLangA,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Language A',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: kTranslationLanguages
                                .map(
                                  (l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(l),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              s.setTranslationLangA(v);
                              setM(() {});
                            },
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.swap_horiz, size: 20),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: s.translationLangB,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Language B',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: kTranslationLanguages
                                .map(
                                  (l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(l),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              s.setTranslationLangB(v);
                              setM(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    if (langsEqual)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Pick two different languages.',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _sheetSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  // ---------- Messages ----------

  List<Widget> _turnWidgets(ChatTurn t) {
    final widgets = <Widget>[_userBubble(t)];
    final hasUserText = t.userText != null && t.userText!.isNotEmpty;
    final showAssistant =
        (hasUserText || t.fusedAudio) && t.state != TurnState.sttError;
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
        onTap: isContinuous ? _chat.toggleContinuousListening : null,
      ),
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
            if (isContinuous)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _DuplexFilter(
                  fullDuplex: s.continuousFullDuplex,
                  onChanged: (v) async {
                    await s.setContinuousFullDuplex(v);
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                status,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
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
