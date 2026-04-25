import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'chat_turn.dart';
import 'providers.dart';
import 'settings.dart';
import 'stt_service.dart';
import 'tts_queue.dart';
import 'tts_service.dart';
import 'voice_recorder_controller.dart';

class ChatConversationController extends ChangeNotifier {
  final AppSettings settings;
  final SttService _stt;
  final TtsService _tts;
  late final VoiceRecorderController _recorder;
  final TtsQueue _ttsQueue = TtsQueue();

  final void Function(String message)? onMessage;
  final VoidCallback? onScrollToBottom;

  final turns = <ChatTurn>[];

  bool autoRestarting = false;
  int? speakingTurnId;
  bool continuousLoopActive = false;
  bool resumeLoopOnReturn = false;

  int _nextTurnId = 0;
  int _conversationGeneration = 0;
  Future<void> _llmChain = Future<void>.value();
  StreamSubscription<bool>? _playingSub;

  ChatConversationController({
    required this.settings,
    this.onMessage,
    this.onScrollToBottom,
    SttService? stt,
    TtsService? tts,
  }) : _stt = stt ?? SttService(),
       _tts = tts ?? TtsService() {
    _recorder = VoiceRecorderController(
      onChanged: notifyListeners,
      onAutoCut: () => unawaited(autoCut()),
      onError: (m) => onMessage?.call(m),
    );
    settings.addListener(_onSettingsChanged);
    _playingSub = _tts.playingStream.listen((playing) {
      if (!playing && speakingTurnId != null) {
        speakingTurnId = null;
        notifyListeners();
      }
      if (!playing) maybeResumeHalfDuplex();
    });
  }

  bool get listening => _recorder.listening;
  double get soundLevel => _recorder.soundLevel;
  bool get speakingNow => _recorder.speakingNow;
  bool get ttsPlaying => _tts.isPlaying;

  bool get pipelineBusy {
    for (final t in turns) {
      if (t.state == TurnState.transcribing ||
          t.state == TurnState.waitingLlm ||
          t.state == TurnState.sending) {
        return true;
      }
    }
    if (_tts.isPlaying) return true;
    if (_ttsQueue.hasPending) return true;
    return false;
  }

  bool get _isHalfDuplexContinuous {
    return settings.voiceMode == VoiceMode.continuous &&
        !settings.continuousFullDuplex;
  }

  void didPushNext() {
    final isContinuous = settings.voiceMode == VoiceMode.continuous;
    resumeLoopOnReturn = isContinuous && (continuousLoopActive || listening);
    continuousLoopActive = false;
    if (listening) unawaited(cutAndProcess());
    notifyListeners();
  }

  void didPopNext() {
    if (!resumeLoopOnReturn) return;
    resumeLoopOnReturn = false;
    if (settings.voiceMode != VoiceMode.continuous) return;
    if (!settings.voiceInputAvailable) return;
    continuousLoopActive = true;
    if (settings.continuousFullDuplex) {
      if (!pipelineBusy && !listening) unawaited(startListening());
    } else {
      maybeResumeHalfDuplex();
    }
    notifyListeners();
  }

  void maybeResumeHalfDuplex() {
    if (!_isHalfDuplexContinuous) return;
    if (!continuousLoopActive) return;
    if (listening || autoRestarting) return;
    if (!settings.voiceInputAvailable) return;
    if (pipelineBusy) return;
    unawaited(startListening());
  }

  void _onSettingsChanged() {
    if (!settings.voiceInputAvailable && listening) {
      unawaited(cutAndProcess());
    }
    if (settings.voiceMode != VoiceMode.continuous) {
      continuousLoopActive = false;
    }
    notifyListeners();
  }

  Future<void> startListening() async {
    await _recorder.start(
      echoCancellation: settings.aecEnabled,
      continuous: settings.voiceMode == VoiceMode.continuous,
      maxListenSeconds: settings.vadListenSeconds,
      vadThresholdLevel: settings.vadThresholdLevel,
      vadPauseSeconds: settings.vadPauseSeconds,
    );
  }

  Future<void> autoCut() async {
    if (!listening) return;
    autoRestarting = true;
    notifyListeners();
    try {
      await cutAndProcess();
      if (settings.voiceMode == VoiceMode.continuous &&
          settings.continuousFullDuplex) {
        await startListening();
      }
    } finally {
      autoRestarting = false;
      notifyListeners();
    }
  }

  Future<void> cutAndProcess() async {
    if (!listening) return;
    final recorded = await _recorder.stop(
      continuous: settings.voiceMode == VoiceMode.continuous,
      minRecordSeconds: settings.minRecordSeconds,
    );
    if (recorded == null) {
      maybeResumeHalfDuplex();
      return;
    }

    final fused = settings.audioDirectActive;
    final turn = ChatTurn(
      id: _nextTurnId++,
      generation: _conversationGeneration,
      audioPath: recorded.path,
      audioFormat: recorded.format,
      fusedAudio: fused,
    );
    turns.add(turn);
    notifyListeners();
    onScrollToBottom?.call();

    if (fused) {
      unawaited(_runFusedChat(turn));
    } else {
      unawaited(
        _runStt(turn).then((ok) {
          if (ok) _scheduleLlm(turn);
        }),
      );
    }
  }

  bool _turnActive(ChatTurn t) {
    return !t.cancelled &&
        t.generation == _conversationGeneration &&
        turns.contains(t);
  }

  Future<bool> _runStt(ChatTurn t) async {
    if (t.audioPath == null) return false;
    t.cancelled = false;
    final client = http.Client();
    t.stopper = client;
    t.state = TurnState.transcribing;
    t.lastError = null;
    notifyListeners();
    try {
      final sttReq = settings.buildSttRequest();
      if (sttReq == null) {
        throw StateError('STT is off — pick a provider in Settings.');
      }
      final text = await _stt.transcribe(
        filePath: t.audioPath!,
        format: t.audioFormat,
        request: sttReq,
        client: client,
        timeout: Duration(seconds: settings.sttTimeoutSeconds),
      );
      final trimmed = text.trim();
      final path = t.audioPath!;
      unawaited(File(path).delete().catchError((_) => File(path)));
      if (!_turnActive(t)) return false;
      t.audioPath = null;
      t.userText = trimmed;
      t.state = trimmed.isEmpty ? TurnState.done : TurnState.waitingLlm;
      notifyListeners();
      onScrollToBottom?.call();
      return trimmed.isNotEmpty;
    } catch (e) {
      debugPrint('[STT] turn ${t.id} failed: $e');
      if (t.cancelled) return false;
      t.state = TurnState.sttError;
      t.lastError = e;
      notifyListeners();
      return false;
    } finally {
      t.stopper = null;
      client.close();
      if (_turnActive(t)) maybeResumeHalfDuplex();
    }
  }

  void _scheduleLlm(ChatTurn t) {
    final prev = _llmChain;
    _llmChain = () async {
      try {
        await prev;
      } catch (_) {}
      if (!_turnActive(t)) return;
      if (t.state != TurnState.waitingLlm) return;
      await _runLlm(t);
    }();
  }

  (String, String)? _parseFusedJson(String reply) {
    var s = reply.trim();
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', multiLine: true);
    final fm = fence.firstMatch(s);
    if (fm != null) s = fm.group(1)!.trim();
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final blob = s.substring(start, end + 1);
    try {
      final obj = jsonDecode(blob);
      if (obj is! Map) return null;
      final transcript =
          (obj['transcript'] ??
                  obj['original'] ??
                  obj['input'] ??
                  obj['source'] ??
                  '')
              .toString()
              .trim();
      final output =
          (obj['output'] ??
                  obj['translation'] ??
                  obj['result'] ??
                  obj['text'] ??
                  '')
              .toString()
              .trim();
      if (output.isEmpty && transcript.isEmpty) return null;
      return (transcript, output.isEmpty ? transcript : output);
    } catch (_) {
      return null;
    }
  }

  Future<void> _runFusedChat(ChatTurn t) async {
    final req = settings.buildChatRequest();
    if (req == null) {
      t.state = TurnState.llmError;
      t.lastError = StateError('Pick a Chat provider in Settings.');
      notifyListeners();
      return;
    }
    if (req.apiKey.isEmpty) {
      t.state = TurnState.llmError;
      t.lastError = StateError(
        'Set the ${req.providerName} API key in Settings.',
      );
      notifyListeners();
      return;
    }
    if (t.audioPath == null) return;
    t.cancelled = false;
    final netClient = http.Client();
    t.stopper = netClient;
    t.state = TurnState.sending;
    t.lastError = null;
    notifyListeners();
    try {
      final bytes = await File(t.audioPath!).readAsBytes();
      final sysPrompt = settings.composedSystemPrompt();
      final msgs = <ChatMessage>[
        if (sysPrompt.isNotEmpty) ChatMessage('system', sysPrompt),
        ChatMessage(
          'user',
          '',
          audio: ChatAudio(bytes: bytes, format: t.audioFormat),
        ),
      ];
      final chat = ChatClient(
        dialect: req.dialect,
        baseUrl: req.baseUrl,
        apiKey: req.apiKey,
        model: req.modelId,
        client: netClient,
        timeout: Duration(seconds: settings.llmTimeoutSeconds),
      );
      final reply = await chat.send(msgs);
      final path = t.audioPath!;
      unawaited(File(path).delete().catchError((_) => File(path)));
      if (!_turnActive(t)) return;

      String? transcript;
      String output = reply;
      if (settings.audioDirectIncludeTranscript) {
        final parsed = _parseFusedJson(reply);
        if (parsed != null) {
          transcript = parsed.$1;
          output = parsed.$2;
        } else {
          debugPrint('[FusedChat] turn ${t.id} JSON parse failed: $reply');
        }
      }

      t.audioPath = null;
      t.userText = transcript;
      t.assistantText = output;
      t.state = TurnState.done;
      t.lastError = null;
      notifyListeners();
      onScrollToBottom?.call();
      if (settings.ttsAutoSpeak && settings.ttsProviderId != null) {
        queueSpeak(output, turnId: t.id);
      }
    } catch (e) {
      debugPrint('[FusedChat] turn ${t.id} failed: $e');
      if (t.cancelled) return;
      t.state = TurnState.llmError;
      t.lastError = e;
      notifyListeners();
    } finally {
      t.stopper = null;
      netClient.close();
      if (_turnActive(t)) maybeResumeHalfDuplex();
    }
  }

  Future<void> _runLlm(ChatTurn t) async {
    final req = settings.buildChatRequest();
    if (req == null) {
      t.state = TurnState.llmError;
      t.lastError = StateError('Pick a Chat provider in Settings.');
      notifyListeners();
      return;
    }
    if (req.apiKey.isEmpty) {
      t.state = TurnState.llmError;
      t.lastError = StateError(
        'Set the ${req.providerName} API key in Settings.',
      );
      notifyListeners();
      return;
    }
    t.cancelled = false;
    final netClient = http.Client();
    t.stopper = netClient;
    t.state = TurnState.sending;
    t.lastError = null;
    notifyListeners();
    try {
      final refs = <String>[];
      final n = settings.historyContextCount;
      if (n > 0) {
        for (final other in turns) {
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
      final sysPrompt = StringBuffer(settings.composedSystemPrompt());
      if (recent.isNotEmpty) {
        sysPrompt.write(
          '\n\n以下是之前的对话内容，仅作为翻译/修正的上下文参考，不要回复、重复或翻译它们，只处理本次用户最新输入：',
        );
        for (final r in recent) {
          sysPrompt.write('\n- $r');
        }
      }
      final msgs = <ChatMessage>[
        ChatMessage('system', sysPrompt.toString()),
        ChatMessage('user', t.userText ?? ''),
      ];
      final chat = ChatClient(
        dialect: req.dialect,
        baseUrl: req.baseUrl,
        apiKey: req.apiKey,
        model: req.modelId,
        client: netClient,
        timeout: Duration(seconds: settings.llmTimeoutSeconds),
      );
      final reply = await chat.send(msgs);
      if (!_turnActive(t)) return;
      t.assistantText = reply;
      t.state = TurnState.done;
      t.lastError = null;
      notifyListeners();
      onScrollToBottom?.call();
      if (settings.ttsAutoSpeak && settings.ttsProviderId != null) {
        queueSpeak(reply, turnId: t.id);
      }
    } catch (e) {
      debugPrint('[LLM] turn ${t.id} failed: $e');
      if (t.cancelled) return;
      t.state = TurnState.llmError;
      t.lastError = e;
      notifyListeners();
    } finally {
      t.stopper = null;
      netClient.close();
      if (_turnActive(t)) maybeResumeHalfDuplex();
    }
  }

  void sendTypedText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final turn = ChatTurn(
      id: _nextTurnId++,
      generation: _conversationGeneration,
      audioPath: null,
    );
    turn.userText = trimmed;
    turn.state = TurnState.waitingLlm;
    turns.add(turn);
    notifyListeners();
    onScrollToBottom?.call();
    _scheduleLlm(turn);
  }

  void cancelTurn(ChatTurn t) {
    if (t.state != TurnState.transcribing &&
        t.state != TurnState.waitingLlm &&
        t.state != TurnState.sending) {
      return;
    }
    t.cancelled = true;
    final stopper = t.stopper;
    t.stopper = null;
    stopper?.close();
    t.state = t.state == TurnState.transcribing
        ? TurnState.sttError
        : TurnState.llmError;
    t.lastError = 'Cancelled';
    notifyListeners();
  }

  Future<void> retryTurn(ChatTurn t) async {
    if (t.fusedAudio && t.audioPath != null) {
      await _runFusedChat(t);
      return;
    }
    if (t.state == TurnState.sttError) {
      final ok = await _runStt(t);
      if (ok) _scheduleLlm(t);
    } else if (t.state == TurnState.llmError) {
      t.state = TurnState.waitingLlm;
      notifyListeners();
      await _runLlm(t);
    }
  }

  void queueSpeak(String text, {int? turnId}) {
    _ttsQueue.enqueue(() async {
      await _tts.waitForIdle();
      await speakText(text, turnId: turnId);
      await _tts.waitForIdle();
    }, onIdle: maybeResumeHalfDuplex);
    notifyListeners();
  }

  void cancelTtsQueue() {
    _ttsQueue.cancel();
    notifyListeners();
  }

  Future<void> speakText(String text, {int? turnId}) async {
    final req = settings.buildTtsRequest();
    if (req == null) return;
    if (turnId != null) {
      speakingTurnId = turnId;
      notifyListeners();
    }
    try {
      await _tts.speak(
        text: text,
        request: req,
        timeout: Duration(seconds: settings.ttsTimeoutSeconds),
      );
    } catch (e) {
      speakingTurnId = null;
      notifyListeners();
      onMessage?.call('TTS error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    cancelTtsQueue();
    await _tts.stop();
    speakingTurnId = null;
    notifyListeners();
  }

  Future<void> clearConversation() async {
    _conversationGeneration++;
    continuousLoopActive = false;
    resumeLoopOnReturn = false;
    cancelTtsQueue();
    await _tts.stop();
    await _recorder.cancelAndDelete();

    for (final t in turns) {
      t.cancelled = true;
      t.stopper?.close();
      t.stopper = null;
      final path = t.audioPath;
      if (path != null) {
        unawaited(File(path).delete().catchError((_) => File(path)));
      }
    }

    turns.clear();
    _llmChain = Future<void>.value();
    autoRestarting = false;
    speakingTurnId = null;
    notifyListeners();
  }

  Future<void> toggleVoiceMode() async {
    if (listening) await cutAndProcess();
    continuousLoopActive = false;
    await settings.setVoiceMode(
      settings.voiceMode == VoiceMode.continuous
          ? VoiceMode.pushToTalk
          : VoiceMode.continuous,
    );
  }

  void toggleContinuousListening() {
    final isHalfDuplex =
        settings.voiceMode == VoiceMode.continuous &&
        !settings.continuousFullDuplex;
    if (isHalfDuplex) {
      if (continuousLoopActive) {
        continuousLoopActive = false;
        if (listening) unawaited(cutAndProcess());
      } else {
        continuousLoopActive = true;
        if (!pipelineBusy && !listening) unawaited(startListening());
      }
      notifyListeners();
      return;
    }

    if (listening) {
      continuousLoopActive = false;
      unawaited(cutAndProcess());
    } else {
      continuousLoopActive = true;
      unawaited(startListening());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    unawaited(_playingSub?.cancel());
    unawaited(_recorder.dispose());
    _tts.dispose();
    super.dispose();
  }
}
