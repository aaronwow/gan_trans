import 'package:ai_chat/prompt_composer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text prompts frame input as STT output and include scene context', () {
    final prompt = PromptComposer.compose(
      const PromptOptions(
        intent: PromptIntent.textTranslateOrCorrect,
        translationEnabled: true,
        translationLangA: '中文',
        translationLangB: '英语',
        scenePrompt: '餐厅点餐',
        includeScenePrompt: true,
      ),
    );

    expect(prompt, contains('用户输入的文字是STT转换的结果'));
    expect(prompt, contains('餐厅点餐'));
    expect(prompt, contains('如果输入是中文，翻译成英语'));
  });

  test('direct audio JSON prompts omit STT framing and request transcript', () {
    final prompt = PromptComposer.compose(
      const PromptOptions(
        intent: PromptIntent.directAudioJsonTranscriptAndOutput,
        translationEnabled: false,
        translationLangA: '中文',
        translationLangB: '印尼语',
        scenePrompt: '',
        includeScenePrompt: false,
      ),
    );

    expect(prompt, isNot(contains('用户输入的文字是STT转换的结果')));
    expect(prompt, contains('"transcript"'));
    expect(prompt, contains('"output"'));
    expect(prompt, contains('不要包含任何时间戳'));
  });
}
