import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'main.dart';
import 'providers.dart';
import 'scenes_screen.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'stt_service.dart';
import 'tts_service.dart';

class ChatScreen extends StatefulWidget {
  final AppSettings settings;
  const ChatScreen({super.key, required this.settings});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum TurnState { transcribing, sttError, waitingLlm, sending, llmError, done }

class ChatTurn {
  final int id;
  String? audioPath; // non-null until STT succeeds (kept for sttError retry)
  final String audioFormat;
  String? userText;
  String? assistantText;
  TurnState state;
  Object? lastError;
  bool errorExpanded = false;
  http.Client? stopper; // closes to abort in-flight STT or LLM request
  bool cancelled = false; // set when user hits Cancel
  ChatTurn({required this.id, required this.audioPath, this.audioFormat = 'wav'})
      : state = TurnState.transcribing;
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin, RouteAware {
  final _scroll = ScrollController();
  final _turns = <ChatTurn>[];
  final _recorder = AudioRecorder();
  final _stt = SttService();
  final _tts = TtsService();

  // WAV is accepted by both OpenAI and Volcengine Flash.
  static const _recordFormat = 'wav';

  bool _listening = false;
  bool _autoRestarting = false;
  double _soundLevel = 0;
  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<bool>? _playingSub;
  String? _currentRecordingPath;
  DateTime? _recordStartedAt;
  int? _speakingTurnId;
  // True while the user has the continuous-mode loop "armed". In half-duplex
  // continuous, the mic auto-resumes after the pipeline goes idle as long as
  // this stays true. In full-duplex continuous it tracks the same intent but
  // restart is handled inline by _autoCut.
  bool _continuousLoopActive = false;
  // Number of TTS clips queued or in-flight (queued but not yet finished).
  // Used by half-duplex idle detection so the mic doesn't reopen between
  // "LLM done" and "audio playback started".
  int _ttsPending = 0;
  // Snapshot of _continuousLoopActive captured when another route covers us,
  // so we can restore the loop on return without resurrecting it after the
  // user explicitly stopped it.
  bool _resumeLoopOnReturn = false;

  // Continuous / VAD state.
  bool _speakingNow = false;
  DateTime? _firstSpeechAt;
  DateTime? _lastSpeechAt;
  bool _hadSpeech = false;

  int _nextTurnId = 0;
  Future<void> _llmChain = Future<void>.value();
  Future<void> _ttsChain = Future<void>.value();

  final _textInput = TextEditingController();

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    widget.settings.addListener(_onSettingsChanged);
    _playingSub = _tts.playingStream.listen((playing) {
      if (!playing && mounted && _speakingTurnId != null) {
        setState(() => _speakingTurnId = null);
      }
      if (!playing) _maybeResumeHalfDuplex();
    });
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
    final s = widget.settings;
    final isContinuous = s.voiceMode == VoiceMode.continuous;
    _resumeLoopOnReturn =
        isContinuous && (_continuousLoopActive || _listening);
    _continuousLoopActive = false;
    if (_listening) {
      unawaited(_cutAndProcess());
    }
    if (mounted) setState(() {});
  }

  @override
  void didPopNext() {
    if (!_resumeLoopOnReturn) return;
    _resumeLoopOnReturn = false;
    final s = widget.settings;
    if (s.voiceMode != VoiceMode.continuous) return;
    if (s.sttProvider == SttProvider.off) return;
    _continuousLoopActive = true;
    if (s.continuousFullDuplex) {
      if (!_pipelineBusy() && !_listening) {
        unawaited(_startListening());
      }
    } else {
      _maybeResumeHalfDuplex();
    }
    if (mounted) setState(() {});
  }

  // ---------- Half-duplex idle/resume ----------

  bool _pipelineBusy() {
    for (final t in _turns) {
      if (t.state == TurnState.transcribing ||
          t.state == TurnState.waitingLlm ||
          t.state == TurnState.sending) {
        return true;
      }
    }
    if (_tts.isPlaying) return true;
    if (_ttsPending > 0) return true;
    return false;
  }

  bool _isHalfDuplexContinuous() {
    final s = widget.settings;
    return s.voiceMode == VoiceMode.continuous && !s.continuousFullDuplex;
  }

  void _maybeResumeHalfDuplex() {
    if (!mounted) return;
    if (!_isHalfDuplexContinuous()) return;
    if (!_continuousLoopActive) return;
    if (_listening || _autoRestarting) return;
    if (widget.settings.sttProvider == SttProvider.off) return;
    if (_pipelineBusy()) return;
    unawaited(_startListening());
  }

  void _onSettingsChanged() {
    if (widget.settings.sttProvider == SttProvider.off && _listening) {
      unawaited(_cutAndProcess());
    }
    if (widget.settings.voiceMode != VoiceMode.continuous) {
      _continuousLoopActive = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    widget.settings.removeListener(_onSettingsChanged);
    _ampSub?.cancel();
    _playingSub?.cancel();
    _recorder.dispose();
    _pulse.dispose();
    _tts.dispose();
    _scroll.dispose();
    _textInput.dispose();
    super.dispose();
  }

  // ---------- Recording + STT ----------

  Future<void> _startListening() async {
    if (_listening) return;
    if (!await _recorder.hasPermission()) {
      _showSnack('Microphone permission denied.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.$_recordFormat';
    try {
      final aec = widget.settings.aecEnabled;
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          // System AEC: iOS uses VoiceProcessingIO; Android uses
          // AcousticEchoCanceler — only effective when paired with the
          // voiceCommunication audio source + modeInCommunication.
          echoCancel: aec,
          noiseSuppress: aec,
          autoGain: aec,
          androidConfig: AndroidRecordConfig(
            audioSource: aec
                ? AndroidAudioSource.voiceCommunication
                : AndroidAudioSource.defaultSource,
            audioManagerMode: aec
                ? AudioManagerMode.modeInCommunication
                : AudioManagerMode.modeNormal,
          ),
        ),
        path: path,
      );
    } catch (e) {
      _showSnack('Failed to start recording: $e');
      return;
    }
    _currentRecordingPath = path;
    _recordStartedAt = DateTime.now();
    _hadSpeech = false;
    _speakingNow = false;
    _firstSpeechAt = null;
    _lastSpeechAt = null;
    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 150))
        .listen(_onAmplitude);
    setState(() => _listening = true);
  }

  void _onAmplitude(Amplitude a) {
    // Amplitude.current is in dBFS (negative). Map ~[-60, 0] dB → [0, 10].
    final db = a.current.isFinite ? a.current : -60.0;
    final normalized = ((db + 60) / 60).clamp(0.0, 1.0);
    final level = normalized * 10;
    final s = widget.settings;
    final isContinuous = s.voiceMode == VoiceMode.continuous;
    final threshold = s.vadThresholdLevel;
    final above = level >= threshold;

    if (!mounted) return;
    setState(() {
      _soundLevel = level;
      _speakingNow = above;
    });

    if (!isContinuous || !_listening) return;

    final now = DateTime.now();
    if (above) {
      _hadSpeech = true;
      _firstSpeechAt ??= now;
      _lastSpeechAt = now;
      return;
    }
    // Silence: if we've had speech and silence exceeded pause threshold, auto-send.
    if (!_hadSpeech) return;
    final last = _lastSpeechAt ?? _recordStartedAt ?? now;
    final silentMs = now.difference(last).inMilliseconds;
    final pauseMs = (s.vadPauseSeconds * 1000).round();
    if (silentMs >= pauseMs) {
      _autoCut();
    }
  }

  Future<void> _autoCut() async {
    if (!_listening) return;
    _autoRestarting = true;
    try {
      await _cutAndProcess();
      // In full-duplex continuous mode the mic reopens immediately so the
      // user can keep talking. In half-duplex it stays closed until the
      // pipeline (STT/LLM/TTS) finishes — see _maybeResumeHalfDuplex.
      if (mounted &&
          widget.settings.voiceMode == VoiceMode.continuous &&
          widget.settings.continuousFullDuplex) {
        await _startListening();
      }
    } finally {
      if (mounted) {
        setState(() => _autoRestarting = false);
      } else {
        _autoRestarting = false;
      }
    }
  }

  Future<void> _cutAndProcess() async {
    if (!_listening) return;
    final path = await _recorder.stop();
    await _ampSub?.cancel();
    _ampSub = null;
    final startedAt = _recordStartedAt;
    final firstSpeech = _firstSpeechAt;
    final lastSpeech = _lastSpeechAt;
    final hadSpeech = _hadSpeech;
    final isContinuous =
        widget.settings.voiceMode == VoiceMode.continuous;
    _recordStartedAt = null;
    _firstSpeechAt = null;
    _lastSpeechAt = null;
    _hadSpeech = false;
    setState(() {
      _listening = false;
      _soundLevel = 0;
    });
    final recorded = path ?? _currentRecordingPath;
    _currentRecordingPath = null;
    if (recorded == null) {
      _maybeResumeHalfDuplex();
      return;
    }

    final Duration elapsed;
    if (isContinuous) {
      elapsed = (hadSpeech && firstSpeech != null && lastSpeech != null)
          ? lastSpeech.difference(firstSpeech)
          : Duration.zero;
    } else {
      elapsed = startedAt == null
          ? Duration.zero
          : DateTime.now().difference(startedAt);
    }
    final minMs = (widget.settings.minRecordSeconds * 1000).round();
    if (elapsed.inMilliseconds < minMs) {
      unawaited(File(recorded).delete().catchError((_) => File(recorded)));
      _maybeResumeHalfDuplex();
      return;
    }

    final turn = ChatTurn(
      id: _nextTurnId++,
      audioPath: recorded,
      audioFormat: _recordFormat,
    );
    setState(() => _turns.add(turn));
    _scrollToBottom();
    unawaited(_runStt(turn).then((ok) {
      if (ok) _scheduleLlm(turn);
    }));
  }

  // ---------- Per-turn pipeline ----------

  Future<bool> _runStt(ChatTurn t) async {
    if (t.audioPath == null) return false;
    if (!mounted) return false;
    t.cancelled = false;
    final client = http.Client();
    t.stopper = client;
    setState(() {
      t.state = TurnState.transcribing;
      t.lastError = null;
    });
    try {
      final text = await _stt.transcribe(
        filePath: t.audioPath!,
        format: t.audioFormat,
        config: widget.settings.sttConfig(),
        client: client,
        timeout: Duration(seconds: widget.settings.sttTimeoutSeconds),
      );
      final trimmed = text.trim();
      final path = t.audioPath!;
      unawaited(File(path).delete().catchError((_) => File(path)));
      if (!mounted) return false;
      setState(() {
        t.audioPath = null;
        t.userText = trimmed;
        t.state =
            trimmed.isEmpty ? TurnState.done : TurnState.waitingLlm;
      });
      _scrollToBottom();
      return trimmed.isNotEmpty;
    } catch (e) {
      debugPrint('[STT] turn ${t.id} failed: $e');
      if (!mounted) return false;
      if (t.cancelled) return false; // state already set by _cancelTurn
      setState(() {
        t.state = TurnState.sttError;
        t.lastError = e;
      });
      return false;
    } finally {
      t.stopper = null;
      client.close();
      _maybeResumeHalfDuplex();
    }
  }

  void _scheduleLlm(ChatTurn t) {
    final prev = _llmChain;
    _llmChain = () async {
      try {
        await prev;
      } catch (_) {}
      if (!mounted) return;
      if (t.state != TurnState.waitingLlm) return;
      await _runLlm(t);
    }();
  }

  Future<void> _runLlm(ChatTurn t) async {
    final s = widget.settings;
    final useTranslation = s.translationEnabled;
    final providerKind = useTranslation ? s.translationProvider : s.provider;
    final apiKey =
        useTranslation ? s.translationApiKey() : s.apiKeyForCurrentProvider();
    final model = useTranslation ? s.translationModel : s.model;
    if (apiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        t.state = TurnState.llmError;
        t.lastError = StateError(useTranslation
            ? 'Set the ${providerOf(providerKind).name} API key in Settings.'
            : 'Set the API key in Settings first.');
      });
      return;
    }
    if (!mounted) return;
    t.cancelled = false;
    final http.Client netClient = http.Client();
    t.stopper = netClient;
    setState(() {
      t.state = TurnState.sending;
      t.lastError = null;
    });
    try {
      final refs = <String>[];
      final n = s.historyContextCount;
      if (n > 0) {
        for (final other in _turns) {
          if (other.id == t.id) break;
          final a = other.assistantText?.trim();
          final u = other.userText?.trim();
          final pick = (a != null && a.isNotEmpty)
              ? a
              : (u != null && u.isNotEmpty ? u : null);
          if (pick != null) refs.add(pick);
        }
      }
      final recent = refs.length > n ? refs.sublist(refs.length - n) : refs;
      final sysPrompt = StringBuffer(s.composedSystemPrompt());
      if (recent.isNotEmpty) {
        sysPrompt.write(
            '\n\n以下是之前的对话内容，仅作为翻译/修正的上下文参考，不要回复、重复或翻译它们，只处理本次用户最新输入：');
        for (final r in recent) {
          sysPrompt.write('\n- $r');
        }
      }
      final userText = t.userText ?? '';
      final msgs = <ChatMessage>[
        ChatMessage('system', sysPrompt.toString()),
        ChatMessage('user', userText),
      ];
      final chat = ChatClient(
        provider: providerOf(providerKind),
        apiKey: apiKey,
        model: model,
        client: netClient,
        timeout: Duration(seconds: s.llmTimeoutSeconds),
      );
      final reply = await chat.send(msgs);
      if (!mounted) return;
      setState(() {
        t.assistantText = reply;
        t.state = TurnState.done;
        t.lastError = null;
      });
      _scrollToBottom();
      if (s.ttsAutoSpeak && s.ttsMode != TtsMode.off) {
        _queueSpeak(reply, turnId: t.id);
      }
    } catch (e) {
      debugPrint('[LLM] turn ${t.id} failed: $e');
      if (!mounted) return;
      if (t.cancelled) return;
      setState(() {
        t.state = TurnState.llmError;
        t.lastError = e;
      });
    } finally {
      t.stopper = null;
      netClient.close();
      _maybeResumeHalfDuplex();
    }
  }

  void _sendTypedText() {
    final text = _textInput.text.trim();
    if (text.isEmpty) return;
    _textInput.clear();
    final turn = ChatTurn(id: _nextTurnId++, audioPath: null);
    turn.userText = text;
    turn.state = TurnState.waitingLlm;
    setState(() => _turns.add(turn));
    _scrollToBottom();
    _scheduleLlm(turn);
  }

  void _cancelTurn(ChatTurn t) {
    if (t.state != TurnState.transcribing &&
        t.state != TurnState.waitingLlm &&
        t.state != TurnState.sending) {
      return;
    }
    t.cancelled = true;
    final stopper = t.stopper;
    t.stopper = null;
    stopper?.close();
    final nextState = t.state == TurnState.transcribing
        ? TurnState.sttError
        : TurnState.llmError;
    setState(() {
      t.state = nextState;
      t.lastError = 'Cancelled';
    });
  }

  Future<void> _retryTurn(ChatTurn t) async {
    if (t.state == TurnState.sttError) {
      final ok = await _runStt(t);
      if (ok) _scheduleLlm(t);
    } else if (t.state == TurnState.llmError) {
      if (!mounted) return;
      setState(() => t.state = TurnState.waitingLlm);
      await _runLlm(t);
    }
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

  void _queueSpeak(String text, {int? turnId}) {
    final prev = _ttsChain;
    _ttsPending++;
    _ttsChain = () async {
      try {
        await prev;
      } catch (_) {}
      try {
        if (!mounted) return;
        // Wait until any currently playing clip finishes before starting the next.
        await _tts.waitForIdle();
        if (!mounted) return;
        await _speakText(text, turnId: turnId);
        await _tts.waitForIdle();
      } finally {
        _ttsPending = (_ttsPending - 1).clamp(0, 1 << 30);
        _maybeResumeHalfDuplex();
      }
    }();
  }

  void _cancelTtsQueue() {
    _ttsChain = Future<void>.value();
    // Clipped chains never run their finally blocks, so reset the counter.
    _ttsPending = 0;
  }

  Future<void> _speakText(String text, {int? turnId}) async {
    final s = widget.settings;
    if (turnId != null) {
      setState(() => _speakingTurnId = turnId);
    }
    try {
      await _tts.speak(
        text: text,
        mode: s.ttsMode,
        openAiApiKey: s.openAiKey,
        openAiModel: s.ttsOpenAiModel,
        openAiVoice: s.ttsOpenAiVoice,
        volcAppKey: s.volcAppKey,
        volcAccessKey: s.volcAccessKey,
        volcResourceId: s.ttsVolcResourceId,
        volcSpeaker: s.ttsVolcSpeaker,
        volcSpeechRate: s.ttsVolcSpeechRate,
        timeout: Duration(seconds: s.ttsTimeoutSeconds),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _speakingTurnId = null);
        _showSnack('TTS error: $e');
      }
    }
  }

  Future<void> _stopSpeaking() async {
    _cancelTtsQueue();
    await _tts.stop();
    if (mounted) setState(() => _speakingTurnId = null);
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('Copied');
  }

  Future<void> _toggleVoiceMode() async {
    final s = widget.settings;
    if (_listening) await _cutAndProcess();
    _continuousLoopActive = false;
    await s.setVoiceMode(
      s.voiceMode == VoiceMode.continuous
          ? VoiceMode.pushToTalk
          : VoiceMode.continuous,
    );
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
                const Text('VAD quick adjust',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Text('Silence cutoff: ${s.vadPauseSeconds.toStringAsFixed(1)}s',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
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
                Text('Speech threshold: ${s.vadThresholdLevel.toStringAsFixed(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
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
          _IconPill(
            icon: Icons.tune,
            onTap: _openConfigSheet,
          ),
        ],
      ),
    );
  }

  void _openScenes() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScenesScreen(settings: widget.settings)),
    );
  }

  Future<void> _openConfigSheet() async {
    final s = widget.settings;
    final ctrl = TextEditingController(text: s.model);
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
              final provider = providerOf(s.provider);
              final langsEqual = s.translationLangA == s.translationLangB;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LLM',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<ProviderKind>(
                      segments: kProviders
                          .map((p) => ButtonSegment(
                              value: p.kind, label: Text(p.name)))
                          .toList(),
                      selected: {s.provider},
                      onSelectionChanged: (v) {
                        s.setProvider(v.first);
                        final suggested =
                            providerOf(v.first).suggestedModels.first;
                        s.setModel(suggested);
                        ctrl.text = suggested;
                        setM(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        hintText: 'Model id',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: s.setModel,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final m in provider.suggestedModels)
                          ActionChip(
                            label: Text(m),
                            onPressed: () {
                              ctrl.text = m;
                              s.setModel(m);
                              setM(() {});
                            },
                          ),
                      ],
                    ),
                    const Divider(height: 28),
                    const Text('Speech-to-Text',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<SttProvider>(
                      segments: const [
                        ButtonSegment(
                            value: SttProvider.off, label: Text('Off')),
                        ButtonSegment(
                            value: SttProvider.openai, label: Text('OpenAI')),
                        ButtonSegment(
                            value: SttProvider.volcFlash, label: Text('豆包')),
                      ],
                      selected: {s.sttProvider},
                      onSelectionChanged: (v) {
                        s.setSttProvider(v.first);
                        setM(() {});
                      },
                    ),
                    const Divider(height: 28),
                    const Text('Text-to-Speech',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<TtsMode>(
                      segments: const [
                        ButtonSegment(value: TtsMode.off, label: Text('Off')),
                        ButtonSegment(
                            value: TtsMode.openai, label: Text('OpenAI')),
                        ButtonSegment(
                            value: TtsMode.volcDoubao, label: Text('豆包')),
                      ],
                      selected: {s.ttsMode},
                      onSelectionChanged: (v) {
                        s.setTtsMode(v.first);
                        setM(() {});
                      },
                    ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        const Text('修正+翻译',
                            style: TextStyle(fontWeight: FontWeight.bold)),
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
                                .map((l) => DropdownMenuItem(
                                    value: l, child: Text(l)))
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
                                .map((l) => DropdownMenuItem(
                                    value: l, child: Text(l)))
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
                        child: Text('Pick two different languages.',
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 12)),
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

  // ---------- Messages ----------

  List<Widget> _turnWidgets(ChatTurn t) {
    final widgets = <Widget>[_userBubble(t)];
    final showAssistant = t.userText != null && t.userText!.isNotEmpty &&
        t.state != TurnState.sttError;
    if (showAssistant) widgets.add(_assistantBubble(t));
    return widgets;
  }

  Widget _userBubble(ChatTurn t) {
    final cs = Theme.of(context).colorScheme;
    final text = t.userText;
    final isError = t.state == TurnState.sttError;
    final isPending = t.state == TurnState.transcribing;
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
              valueColor: AlwaysStoppedAnimation(cs.onPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Text('Transcribing…',
              style: TextStyle(color: cs.onPrimary, height: 1.35)),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _cancelTurn(t),
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
              onTap: () =>
                  setState(() => t.errorExpanded = !t.errorExpanded),
              child: Text(
                errText,
                style: TextStyle(color: cs.onErrorContainer, height: 1.35),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _retryTurn(t),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.refresh,
                  size: 18, color: cs.onErrorContainer),
            ),
          ),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    final ttsEnabled = widget.settings.ttsMode != TtsMode.off;
    final isSpeakingThis = _speakingTurnId == t.id;
    final isError = t.state == TurnState.llmError;
    final isPending = t.state == TurnState.waitingLlm ||
        t.state == TurnState.sending;
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
            onTap: () => _cancelTurn(t),
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
            onTap: () => _retryTurn(t),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.refresh,
                  size: 18, color: cs.onErrorContainer),
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
                  ? _stopSpeaking
                  : () {
                      _cancelTtsQueue();
                      _speakText(text, turnId: t.id);
                    },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  isSpeakingThis
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                  size: 20,
                  color: isSpeakingThis
                      ? cs.primary
                      : cs.onSurfaceVariant,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    if (s.contains('20000003') ||
        s.toLowerCase().contains('no valid speech')) {
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
    if (s.sttProvider == SttProvider.off) return _textInputBar();
    final isContinuous = s.voiceMode == VoiceMode.continuous;
    final isHalfDuplex = isContinuous && !s.continuousFullDuplex;
    final status = _statusLabel(s.voiceMode);

    final modeButton = _ModeToggleButton(
      mode: s.voiceMode,
      onTap: _toggleVoiceMode,
    );
    final mic = Expanded(
      child: _MicBar(
        listening: _listening ||
            (isContinuous && s.continuousFullDuplex && _autoRestarting) ||
            (isHalfDuplex && _continuousLoopActive),
        enabled: true,
        continuous: isContinuous,
        level: _soundLevel,
        pulse: _pulse,
        showGear: isContinuous,
        onGearTap: _openVadQuickAdjust,
        onPressStart: isContinuous ? null : _startListening,
        onPressEnd: isContinuous ? null : _cutAndProcess,
        onTap: isContinuous
            ? () {
                if (isHalfDuplex) {
                  if (_continuousLoopActive) {
                    _continuousLoopActive = false;
                    if (_listening) _cutAndProcess();
                    setState(() {});
                  } else {
                    _continuousLoopActive = true;
                    if (!_pipelineBusy() && !_listening) _startListening();
                    setState(() {});
                  }
                } else {
                  if (_listening) {
                    _continuousLoopActive = false;
                    _cutAndProcess();
                  } else {
                    _continuousLoopActive = true;
                    _startListening();
                  }
                }
              }
            : null,
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
            if (isContinuous && (_listening || _autoRestarting))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _LevelMeter(
                  level: _soundLevel,
                  threshold: s.vadThresholdLevel,
                  speaking: _speakingNow,
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
                      horizontal: 14, vertical: 12),
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
    final pending = _turns.where((t) =>
        t.state == TurnState.transcribing ||
        t.state == TurnState.waitingLlm ||
        t.state == TurnState.sending).length;
    final pendingSuffix = pending > 0 ? ' · $pending in flight' : '';
    if (mode == VoiceMode.pushToTalk) {
      final base = _listening ? 'Release to send' : 'Hold to talk';
      return '$base$pendingSuffix';
    }
    // continuous mode
    if (s.continuousFullDuplex) {
      if (_listening || _autoRestarting) {
        final base =
            _speakingNow ? 'Listening…' : 'Silent (auto-send on pause)';
        return '$base$pendingSuffix';
      }
      return 'Tap to start continuous listening$pendingSuffix';
    }
    // half-duplex inside continuous
    if (!_continuousLoopActive) {
      return 'Tap to start half-duplex listening$pendingSuffix';
    }
    if (_listening) {
      final base =
          _speakingNow ? 'Listening…' : 'Silent (auto-send on pause)';
      return '$base$pendingSuffix';
    }
    if (_tts.isPlaying) return 'Speaking — mic paused$pendingSuffix';
    if (_pipelineBusy()) return 'Processing — mic paused$pendingSuffix';
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
            onPressed: () => setState(() {
              _turns.clear();
              _llmChain = Future<void>.value();
            }),
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
            child: _turns.isEmpty
                ? _EmptyState(sceneName: widget.settings.activeScene.name)
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final t in _turns) ..._turnWidgets(t),
                    ],
                  ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }
}

// ---------------- Widgets ----------------

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PillButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: cs.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconPill({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _ModeToggleButton extends StatelessWidget {
  final VoiceMode mode;
  final VoidCallback onTap;
  const _ModeToggleButton({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isContinuous = mode == VoiceMode.continuous;
    return Tooltip(
      message: isContinuous
          ? 'Continuous mode — tap to switch to push-to-talk'
          : 'Push-to-talk — tap to switch to continuous',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Icon(
            isContinuous ? Icons.all_inclusive : Icons.touch_app_outlined,
            color: cs.onSurfaceVariant,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Segmented filter shown only in continuous mode — picks half- vs full-duplex.
class _DuplexFilter extends StatelessWidget {
  final bool fullDuplex;
  final ValueChanged<bool> onChanged;
  const _DuplexFilter({required this.fullDuplex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
          value: false,
          icon: Icon(Icons.compare_arrows, size: 16),
          label: Text('Half-duplex'),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(Icons.swap_horiz, size: 16),
          label: Text('Full-duplex'),
        ),
      ],
      selected: {fullDuplex},
      showSelectedIcon: false,
      onSelectionChanged: (set) => onChanged(set.first),
    );
  }
}

class _MicBar extends StatelessWidget {
  final bool listening;
  final bool enabled;
  final bool continuous;
  final double level;
  final AnimationController pulse;
  final bool showGear;
  final VoidCallback? onGearTap;
  final VoidCallback? onPressStart;
  final VoidCallback? onPressEnd;
  final VoidCallback? onTap;
  const _MicBar({
    required this.listening,
    required this.enabled,
    required this.continuous,
    required this.level,
    required this.pulse,
    required this.showGear,
    this.onGearTap,
    this.onPressStart,
    this.onPressEnd,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = listening ? Colors.redAccent : cs.primary;
    final disabled = !enabled;
    final label = listening
        ? (continuous ? 'Listening — tap to stop' : 'Release to send')
        : (continuous ? 'Tap to start' : 'Hold to talk');
    final icon = listening ? Icons.graphic_eq : Icons.mic;

    Widget bar = AnimatedBuilder(
      animation: pulse,
      builder: (_, _) {
        final glow = listening ? (0.25 + pulse.value * 0.25) : 0.18;
        return Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: disabled
                  ? [Colors.grey.shade400, Colors.grey.shade500]
                  : [base, base.withValues(alpha: 0.78)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: base.withValues(alpha: glow),
                blurRadius: listening ? 22 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showGear) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onGearTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.tune,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );

    return GestureDetector(
      onTapDown: disabled || continuous
          ? null
          : (_) => onPressStart?.call(),
      onTapUp: disabled || continuous
          ? null
          : (_) => onPressEnd?.call(),
      onTapCancel: disabled || continuous ? null : () => onPressEnd?.call(),
      onTap: disabled || !continuous ? null : onTap,
      child: bar,
    );
  }
}

class _LevelMeter extends StatelessWidget {
  final double level; // 0..10
  final double threshold; // 0..10
  final bool speaking;
  const _LevelMeter({
    required this.level,
    required this.threshold,
    required this.speaking,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        final barW = (level / 10).clamp(0.0, 1.0) * w;
        final tX = (threshold / 10).clamp(0.0, 1.0) * w;
        return SizedBox(
          height: 10,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              Container(
                width: barW,
                decoration: BoxDecoration(
                  color: speaking ? cs.primary : cs.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              Positioned(
                left: tX - 1,
                top: -2,
                bottom: -2,
                child: Container(width: 2, color: cs.error),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String sceneName;
  const _EmptyState({required this.sceneName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none, size: 64, color: cs.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              'Scene: $sceneName',
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Hold the mic to talk, release to send.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
