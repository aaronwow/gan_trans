import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'chat_turn.dart';
import 'settings.dart';
import 'stt_service.dart';
import 'tts_queue.dart';
import 'tts_service.dart';
import 'voice_pipeline.dart';
import 'voice_recorder_controller.dart';

class ChatConversationController extends ChangeNotifier {
  final AppSettings settings;
  final SttService _stt;
  final TtsService _tts;
  late final VoicePipelineRunner _pipeline;
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
    _pipeline = VoicePipelineRunner(settings: settings, stt: _stt, tts: _tts);
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
    // Settings edits (provider/model/audio-direct) can clear a guard that was
    // blocking a previous resume attempt — retry now so half-duplex doesn't
    // wedge in "Resuming…" when voiceInputAvailable flips back to true.
    maybeResumeHalfDuplex();
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
      // If autoCut hit a recorded==null path (sub-min-record), the inner
      // maybeResumeHalfDuplex was blocked by autoRestarting=true. Retry now
      // that the flag is cleared so half-duplex doesn't stall.
      maybeResumeHalfDuplex();
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

  void _recordPipelineResult(ChatTurn t, PipelineResult result) {
    t.rawTranscript = result.rawTranscript;
    t.normalizedTranscript = result.normalizedTranscript;
    t.translatedText = result.translatedText;
    t.displayText = result.displayText;
    t.ttsText = result.ttsText;
    t.providerTrace = result.providerTrace
        .map((p) => '${p.step.name}:${p.providerName}/${p.modelId}')
        .toList();
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
      final result = await _pipeline.transcribeAudio(
        filePath: t.audioPath!,
        format: t.audioFormat,
        client: client,
      );
      _recordPipelineResult(t, result);
      final trimmed = result.normalizedTranscript ?? result.displayText.trim();
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

  Future<void> _runFusedChat(ChatTurn t) async {
    if (t.audioPath == null) return;
    t.cancelled = false;
    final netClient = http.Client();
    t.stopper = netClient;
    t.state = TurnState.sending;
    t.lastError = null;
    notifyListeners();
    try {
      final result = await _pipeline.translateAudioDirect(
        filePath: t.audioPath!,
        format: t.audioFormat,
        client: netClient,
      );
      final path = t.audioPath!;
      unawaited(File(path).delete().catchError((_) => File(path)));
      if (!_turnActive(t)) return;
      _recordPipelineResult(t, result);

      t.audioPath = null;
      t.userText = result.normalizedTranscript;
      t.assistantText = result.translatedText ?? result.displayText;
      t.state = TurnState.done;
      t.lastError = null;
      notifyListeners();
      onScrollToBottom?.call();
      if (settings.ttsAutoSpeak && settings.ttsProviderId != null) {
        queueSpeak(result.ttsText ?? result.displayText, turnId: t.id);
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
    t.cancelled = false;
    final netClient = http.Client();
    t.stopper = netClient;
    t.state = TurnState.sending;
    t.lastError = null;
    notifyListeners();
    try {
      final result = await _pipeline.translateText(
        text: t.userText ?? '',
        recentContext: _pipeline.recentContextBefore(t, turns),
        client: netClient,
        strategy: t.typedInput
            ? PipelineStrategy.textOnlyTranslateThenTts
            : PipelineStrategy.sttThenTranslateThenTts,
      );
      if (!_turnActive(t)) return;
      _recordPipelineResult(t, result);
      t.assistantText = result.translatedText ?? result.displayText;
      t.state = TurnState.done;
      t.lastError = null;
      notifyListeners();
      onScrollToBottom?.call();
      if (settings.ttsAutoSpeak && settings.ttsProviderId != null) {
        queueSpeak(result.ttsText ?? result.displayText, turnId: t.id);
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
      typedInput: true,
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
    if (turnId != null) {
      speakingTurnId = turnId;
      notifyListeners();
    }
    final client = http.Client();
    try {
      await _pipeline.speak(text: text, client: client);
    } catch (e) {
      speakingTurnId = null;
      notifyListeners();
      onMessage?.call('TTS error: $e');
    } finally {
      client.close();
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
