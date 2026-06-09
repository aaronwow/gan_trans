enum PromptIntent {
  textTranslateOrCorrect,
  directAudioTranslateOrCorrect,
  directAudioJsonTranscriptAndOutput,
  imageOcrAndTranslate,
}

/// Stable separator the image OCR+translate intent emits between the extracted
/// source text and the translated/corrected output. Renderers split on this
/// to show the two blocks distinctly.
const String kImageOcrSeparator = '---译文---';

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
        ? '判断本次最新输入的主要语言：如果输入是$a，必须翻译成$b；如果输入是$b，必须翻译成$a。禁止把$a输入输出为$a，也禁止把$b输入输出为$b。'
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
      case PromptIntent.imageOcrAndTranslate:
        final imageTask = options.translationEnabled
            ? '判断原文的主要语言：如果原文是$a，必须翻译成$b；如果原文是$b，必须翻译成$a。禁止同语言输出。'
            : '修正原文文字（如有错别字或OCR噪声）。';
        return '$scene你将看到一张图片。请严格分两段输出：\n'
            '第一段：逐字提取图片中的全部文字，保留原始换行和段落结构，不要增删、不要解释、不要使用 Markdown。\n'
            '然后另起一行只输出分隔符：$kImageOcrSeparator\n'
            '第二段：$imageTask只输出最终结果，不要解释、不要重复原文、不要使用 Markdown。';
    }
  }
}
