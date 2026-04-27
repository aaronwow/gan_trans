import 'package:http/http.dart' as http;

import 'providers.dart';

enum TurnState { transcribing, sttError, waitingLlm, sending, llmError, done }

class ChatTurn {
  final int id;
  final int generation;
  String? audioPath; // non-null until STT succeeds (kept for sttError retry)
  final String audioFormat;
  String? userText;
  String? assistantText;
  String? rawTranscript;
  String? normalizedTranscript;
  String? translatedText;
  String? displayText;
  String? ttsText;
  List<String> providerTrace = [];
  TurnState state;
  Object? lastError;
  bool errorExpanded = false;
  http.Client? stopper; // closes to abort in-flight STT or LLM request
  bool cancelled = false; // set when user hits Cancel

  /// True when this turn was sent in audio-direct mode: the recording was
  /// fed straight to the chat model (no STT step). Drives bubble rendering.
  final bool fusedAudio;
  final bool typedInput;

  /// Optional image attachment for this turn (image OCR + translate flow).
  /// Kept on the turn so it can be shown in the user bubble and re-sent on
  /// retry without re-prompting the picker.
  final ChatImage? image;
  bool get imageInput => image != null;

  ChatTurn({
    required this.id,
    required this.generation,
    required this.audioPath,
    this.audioFormat = 'wav',
    this.fusedAudio = false,
    this.typedInput = false,
    this.image,
  }) : state = fusedAudio || typedInput || image != null
           ? TurnState.sending
           : TurnState.transcribing;
}
