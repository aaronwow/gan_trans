enum PromptIntent {
  textTranslateOrCorrect,
  directAudioTranslateOrCorrect,
  directAudioJsonTranscriptAndOutput,
}

class PromptOptions {
  final PromptIntent intent;
  final bool translationEnabled;
  final String translationLangA;
  final String translationLangB;
  final String scenePrompt;
  final bool includeScenePrompt;

  const PromptOptions({
    required this.intent,
    required this.translationEnabled,
    required this.translationLangA,
    required this.translationLangB,
    required this.scenePrompt,
    required this.includeScenePrompt,
  });
}

class PromptComposer {
  const PromptComposer._();

  static String compose(PromptOptions options) {
    final a = options.translationLangA.trim().isEmpty
        ? '中文'
        : options.translationLangA.trim();
    final b = options.translationLangB.trim().isEmpty
        ? '印尼语'
        : options.translationLangB.trim();
    final sceneText = options.scenePrompt.trim();
    final scene = (options.includeScenePrompt && sceneText.isNotEmpty)
        ? '$sceneText。'
        : '';
    final task = options.translationEnabled
        ? '如果输入是$a，翻译成$b；如果输入是$b，翻译成$a。'
        : '修正输入文字。';
    final outputRule = options.translationEnabled
        ? '只输出最终翻译后的内容，不要包含原文、解释、标签、引号、Markdown 或任何额外文字。'
        : '只输出修正后的文字，不要包含解释、标签、引号、Markdown 或任何额外文字。';

    switch (options.intent) {
      case PromptIntent.directAudioJsonTranscriptAndOutput:
        return '$scene$task严格按以下 JSON 输出，不要使用 Markdown 代码块，不要包含任何时间戳或时间码（例如 00:00、00:04）：'
            '{"transcript": "音频的原始转录文字", "output": "最终翻译后的内容或修正后的文字"}';
      case PromptIntent.directAudioTranslateOrCorrect:
        return '$scene$task$outputRule不要包含任何时间戳或时间码（例如 00:00、00:04）。';
      case PromptIntent.textTranslateOrCorrect:
        return '用户输入的文字是STT转换的结果，$scene$task$outputRule';
    }
  }
}
