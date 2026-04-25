import 'package:http/http.dart' as http;

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

  ChatTurn({
    required this.id,
    required this.generation,
    required this.audioPath,
    this.audioFormat = 'wav',
    this.fusedAudio = false,
    this.typedInput = false,
  }) : state = fusedAudio || typedInput
           ? TurnState.sending
           : TurnState.transcribing;
}
