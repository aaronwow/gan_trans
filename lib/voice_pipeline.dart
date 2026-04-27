import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'chat_turn.dart';
import 'prompt_composer.dart';
import 'providers.dart';
import 'settings.dart';
import 'stt_service.dart';
import 'tts_service.dart';

enum PipelineStrategy {
  sttThenTranslateThenTts,
  audioDirectTranslateThenTts,
  textOnlyTranslateThenTts,
  imageOcrAndTranslate,
}

enum PipelineStepKind { stt, translate, tts }

class PipelineTrace {
  final PipelineStepKind step;
  final String providerName;
  final String modelId;

  const PipelineTrace({
    required this.step,
    required this.providerName,
    required this.modelId,
  });
}

class PipelineResult {
  final PipelineStrategy strategy;
  final String? rawTranscript;
  final String? normalizedTranscript;
  final String? translatedText;
  final String displayText;
  final String? ttsText;
  final List<PipelineTrace> providerTrace;

  const PipelineResult({
    required this.strategy,
    this.rawTranscript,
    this.normalizedTranscript,
    this.translatedText,
    required this.displayText,
    this.ttsText,
    this.providerTrace = const [],
  });
}

class PipelineError implements Exception {
  final PipelineStepKind step;
  final String? providerId;
  final String? modelId;
  final String userMessage;
  final String debugMessage;
  final bool retryable;

  const PipelineError({
    required this.step,
    required this.userMessage,
    required this.debugMessage,
    this.providerId,
    this.modelId,
    this.retryable = true,
  });

  @override
  String toString() => userMessage;
}

class PipelineContext {
  final AppSettings settings;
  final http.Client client;

  const PipelineContext({required this.settings, required this.client});
}

abstract class PipelineStep<I, O> {
  PipelineStepKind get kind;
  Future<O> run(I input, PipelineContext context);
}

class SttStepInput {
  final String filePath;
  final String format;

  const SttStepInput({required this.filePath, required this.format});
}

class SttPipelineStep implements PipelineStep<SttStepInput, PipelineResult> {
  final SttService service;

  const SttPipelineStep(this.service);

  @override
  PipelineStepKind get kind => PipelineStepKind.stt;

  @override
  Future<PipelineResult> run(
    SttStepInput input,
    PipelineContext context,
  ) async {
    final req = context.settings.buildSttRequest();
    if (req == null) {
      throw const PipelineError(
        step: PipelineStepKind.stt,
        userMessage: 'STT is off — pick a provider in Settings.',
        debugMessage: 'No STT request could be built from settings.',
        retryable: false,
      );
    }
    try {
      final text = await service.transcribe(
        filePath: input.filePath,
        format: input.format,
        request: req,
        client: context.client,
        timeout: Duration(seconds: context.settings.sttTimeoutSeconds),
      );
      final trimmed = text.trim();
      return PipelineResult(
        strategy: PipelineStrategy.sttThenTranslateThenTts,
        rawTranscript: text,
        normalizedTranscript: trimmed,
        displayText: trimmed,
        providerTrace: [
          PipelineTrace(
            step: PipelineStepKind.stt,
            providerName: 'stt',
            modelId: req.modelId,
          ),
        ],
      );
    } catch (e) {
      if (e is PipelineError) rethrow;
      throw PipelineError(
        step: PipelineStepKind.stt,
        userMessage: 'STT failed: $e',
        debugMessage: e.toString(),
        modelId: req.modelId,
      );
    }
  }
}

class TranslateTextInput {
  final String text;
  final List<String> recentContext;
  final PipelineStrategy strategy;

  const TranslateTextInput({
    required this.text,
    this.recentContext = const [],
    this.strategy = PipelineStrategy.sttThenTranslateThenTts,
  });
}

class TextTranslateStep
    implements PipelineStep<TranslateTextInput, PipelineResult> {
  @override
  PipelineStepKind get kind => PipelineStepKind.translate;

  @override
  Future<PipelineResult> run(
    TranslateTextInput input,
    PipelineContext context,
  ) async {
    if (!context.settings.correctionEnabled) {
      final text = input.text.trim();
      return PipelineResult(
        strategy: input.strategy,
        rawTranscript:
            input.strategy == PipelineStrategy.textOnlyTranslateThenTts
            ? null
            : input.text,
        normalizedTranscript:
            input.strategy == PipelineStrategy.textOnlyTranslateThenTts
            ? null
            : text,
        translatedText: text,
        displayText: text,
        ttsText: text,
      );
    }
    final req = _requireChatRequest(context.settings);
    final sysPrompt = StringBuffer(context.settings.composedSystemPrompt());
    if (input.recentContext.isNotEmpty) {
      sysPrompt.write(
        '\n\n以下是之前的对话内容，仅作为翻译/修正的上下文参考，不要回复、重复或翻译它们，只处理本次用户最新输入：',
      );
      for (final r in input.recentContext) {
        sysPrompt.write('\n- $r');
      }
    }
    final chat = ChatClient(
      dialect: req.dialect,
      baseUrl: req.baseUrl,
      apiKey: req.apiKey,
      model: req.modelId,
      client: context.client,
      timeout: Duration(seconds: context.settings.llmTimeoutSeconds),
    );
    try {
      final reply = await chat.send([
        ChatMessage('system', sysPrompt.toString()),
        ChatMessage('user', input.text),
      ]);
      return PipelineResult(
        strategy: input.strategy,
        rawTranscript:
            input.strategy == PipelineStrategy.textOnlyTranslateThenTts
            ? null
            : input.text,
        normalizedTranscript:
            input.strategy == PipelineStrategy.textOnlyTranslateThenTts
            ? null
            : input.text.trim(),
        translatedText: reply,
        displayText: reply,
        ttsText: reply,
        providerTrace: [
          PipelineTrace(
            step: PipelineStepKind.translate,
            providerName: req.providerName,
            modelId: req.modelId,
          ),
        ],
      );
    } catch (e) {
      if (e is PipelineError) rethrow;
      throw PipelineError(
        step: PipelineStepKind.translate,
        providerId: req.providerName,
        modelId: req.modelId,
        userMessage: 'Translation failed: $e',
        debugMessage: e.toString(),
      );
    }
  }
}

class DirectAudioTranslateInput {
  final String filePath;
  final String format;

  const DirectAudioTranslateInput({
    required this.filePath,
    required this.format,
  });
}

class DirectAudioTranslateStep
    implements PipelineStep<DirectAudioTranslateInput, PipelineResult> {
  @override
  PipelineStepKind get kind => PipelineStepKind.translate;

  @override
  Future<PipelineResult> run(
    DirectAudioTranslateInput input,
    PipelineContext context,
  ) async {
    final req = _requireChatRequest(context.settings);
    try {
      final bytes = await File(input.filePath).readAsBytes();
      final chat = ChatClient(
        dialect: req.dialect,
        baseUrl: req.baseUrl,
        apiKey: req.apiKey,
        model: req.modelId,
        client: context.client,
        timeout: Duration(seconds: context.settings.llmTimeoutSeconds),
      );
      final reply = await chat.send([
        if (context.settings.composedSystemPrompt().isNotEmpty)
          ChatMessage('system', context.settings.composedSystemPrompt()),
        ChatMessage(
          'user',
          '',
          audio: ChatAudio(bytes: bytes, format: input.format),
        ),
      ]);

      String? transcript;
      var output = reply;
      if (context.settings.audioDirectIncludeTranscript) {
        final parsed = _parseFusedJson(reply);
        if (parsed != null) {
          transcript = parsed.$1;
          output = parsed.$2;
        }
      }
      return PipelineResult(
        strategy: PipelineStrategy.audioDirectTranslateThenTts,
        rawTranscript: transcript,
        normalizedTranscript: transcript?.trim(),
        translatedText: output,
        displayText: output,
        ttsText: output,
        providerTrace: [
          PipelineTrace(
            step: PipelineStepKind.translate,
            providerName: req.providerName,
            modelId: req.modelId,
          ),
        ],
      );
    } catch (e) {
      if (e is PipelineError) rethrow;
      throw PipelineError(
        step: PipelineStepKind.translate,
        providerId: req.providerName,
        modelId: req.modelId,
        userMessage: 'Audio translation failed: $e',
        debugMessage: e.toString(),
      );
    }
  }
}

class ImageTranslateInput {
  final ChatImage image;

  const ImageTranslateInput({required this.image});
}

class ImageTranslateStep
    implements PipelineStep<ImageTranslateInput, PipelineResult> {
  @override
  PipelineStepKind get kind => PipelineStepKind.translate;

  @override
  Future<PipelineResult> run(
    ImageTranslateInput input,
    PipelineContext context,
  ) async {
    final s = context.settings;
    final req = s.buildImageChatRequest();
    if (req == null) {
      throw const PipelineError(
        step: PipelineStepKind.translate,
        userMessage: 'Pick a Chat provider in Settings.',
        debugMessage: 'No image chat request could be built from settings.',
        retryable: false,
      );
    }
    if (req.apiKey.isEmpty) {
      throw PipelineError(
        step: PipelineStepKind.translate,
        providerId: req.providerName,
        modelId: req.modelId,
        userMessage: 'Set the ${req.providerName} API key in Settings.',
        debugMessage: 'Missing API key for ${req.providerName}.',
        retryable: false,
      );
    }
    final sysPrompt = PromptComposer.compose(
      PromptOptions(
        intent: PromptIntent.imageOcrAndTranslate,
        translationEnabled: s.translationEnabled || s.correctionEnabled,
        translationLangA: s.translationLangA,
        translationLangB: s.translationLangB,
        scenePrompt: s.activeScene.prompt,
        includeScenePrompt: s.includeScenePrompt,
      ),
    );
    final chat = ChatClient(
      dialect: req.dialect,
      baseUrl: req.baseUrl,
      apiKey: req.apiKey,
      model: req.modelId,
      client: context.client,
      timeout: Duration(seconds: s.llmTimeoutSeconds),
    );
    try {
      final reply = await chat.send([
        ChatMessage('system', sysPrompt),
        ChatMessage('user', '', image: input.image),
      ]);
      final parts = _splitImageOcrReply(reply);
      final original = parts.$1;
      final output = parts.$2;
      return PipelineResult(
        strategy: PipelineStrategy.imageOcrAndTranslate,
        rawTranscript: original,
        normalizedTranscript: original?.trim(),
        translatedText: output,
        displayText: output,
        ttsText: output,
        providerTrace: [
          PipelineTrace(
            step: PipelineStepKind.translate,
            providerName: req.providerName,
            modelId: req.modelId,
          ),
        ],
      );
    } catch (e) {
      if (e is PipelineError) rethrow;
      throw PipelineError(
        step: PipelineStepKind.translate,
        providerId: req.providerName,
        modelId: req.modelId,
        userMessage: 'Image translation failed: $e',
        debugMessage: e.toString(),
      );
    }
  }
}

/// Splits the model reply on [kImageOcrSeparator]. Returns (original, output).
/// If the separator isn't found, the whole reply is returned as the output and
/// the original is null — the UI then just shows the raw reply.
(String?, String) _splitImageOcrReply(String reply) {
  final idx = reply.indexOf(kImageOcrSeparator);
  if (idx < 0) return (null, reply.trim());
  final before = reply.substring(0, idx).trim();
  final after = reply.substring(idx + kImageOcrSeparator.length).trim();
  return (before.isEmpty ? null : before, after);
}

class TtsPipelineStep implements PipelineStep<String, void> {
  final TtsService service;

  const TtsPipelineStep(this.service);

  @override
  PipelineStepKind get kind => PipelineStepKind.tts;

  @override
  Future<void> run(String input, PipelineContext context) async {
    final req = context.settings.buildTtsRequest();
    if (req == null) return;
    try {
      await service.speak(
        text: input,
        request: req,
        timeout: Duration(seconds: context.settings.ttsTimeoutSeconds),
      );
    } catch (e) {
      throw PipelineError(
        step: PipelineStepKind.tts,
        modelId: req.modelId,
        userMessage: 'TTS error: $e',
        debugMessage: e.toString(),
      );
    }
  }
}

abstract class SttSession {
  Future<void Function(List<int> chunk)?> prepare();
  Future<String> finish(File audioFile);
  Future<void> cancel();
}

class VoicePipelineRunner {
  final AppSettings settings;
  final SttPipelineStep sttStep;
  final TextTranslateStep textTranslateStep;
  final DirectAudioTranslateStep directAudioTranslateStep;
  final ImageTranslateStep imageTranslateStep;
  final TtsPipelineStep ttsStep;

  VoicePipelineRunner({
    required this.settings,
    required SttService stt,
    required TtsService tts,
  }) : sttStep = SttPipelineStep(stt),
       textTranslateStep = TextTranslateStep(),
       directAudioTranslateStep = DirectAudioTranslateStep(),
       imageTranslateStep = ImageTranslateStep(),
       ttsStep = TtsPipelineStep(tts);

  Future<PipelineResult> transcribeAudio({
    required String filePath,
    required String format,
    required http.Client client,
  }) {
    return sttStep.run(
      SttStepInput(filePath: filePath, format: format),
      PipelineContext(settings: settings, client: client),
    );
  }

  Future<PipelineResult> translateText({
    required String text,
    required List<String> recentContext,
    required http.Client client,
    PipelineStrategy strategy = PipelineStrategy.sttThenTranslateThenTts,
  }) {
    return textTranslateStep.run(
      TranslateTextInput(
        text: text,
        recentContext: recentContext,
        strategy: strategy,
      ),
      PipelineContext(settings: settings, client: client),
    );
  }

  Future<PipelineResult> translateAudioDirect({
    required String filePath,
    required String format,
    required http.Client client,
  }) {
    return directAudioTranslateStep.run(
      DirectAudioTranslateInput(filePath: filePath, format: format),
      PipelineContext(settings: settings, client: client),
    );
  }

  Future<PipelineResult> translateImage({
    required ChatImage image,
    required http.Client client,
  }) {
    return imageTranslateStep.run(
      ImageTranslateInput(image: image),
      PipelineContext(settings: settings, client: client),
    );
  }

  Future<void> speak({required String text, required http.Client client}) {
    return ttsStep.run(
      text,
      PipelineContext(settings: settings, client: client),
    );
  }

  List<String> recentContextBefore(ChatTurn turn, List<ChatTurn> turns) {
    final n = settings.historyContextCount;
    if (n <= 0) return const [];
    final refs = <String>[];
    for (final other in turns) {
      if (other.id == turn.id) break;
      final a = other.assistantText?.trim();
      final u = other.userText?.trim();
      final pick = (a != null && a.isNotEmpty)
          ? a
          : (u != null && u.isNotEmpty ? u : null);
      if (pick != null) refs.add(pick);
    }
    return refs.length > n ? refs.sublist(refs.length - n) : refs;
  }
}

ChatRequest _requireChatRequest(AppSettings settings) {
  final req = settings.buildChatRequest();
  if (req == null) {
    throw const PipelineError(
      step: PipelineStepKind.translate,
      userMessage: 'Pick a Chat provider in Settings.',
      debugMessage: 'No chat request could be built from settings.',
      retryable: false,
    );
  }
  if (req.apiKey.isEmpty) {
    throw PipelineError(
      step: PipelineStepKind.translate,
      providerId: req.providerName,
      modelId: req.modelId,
      userMessage: 'Set the ${req.providerName} API key in Settings.',
      debugMessage: 'Missing API key for ${req.providerName}.',
      retryable: false,
    );
  }
  return req;
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
