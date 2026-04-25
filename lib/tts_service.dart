import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum TtsMode { off, openai, volcDoubao }

const kOpenAiTtsVoices = <String>[
  'alloy',
  'ash',
  'ballad',
  'coral',
  'echo',
  'fable',
  'nova',
  'onyx',
  'sage',
  'shimmer',
];

const kOpenAiTtsModels = <String>[
  'gpt-4o-mini-tts',
  'tts-1',
  'tts-1-hd',
];

const kDoubaoTtsResourceId = 'seed-tts-2.0';

/// Volcengine 豆包 TTS resource id options (mirrors auc-web).
const kDoubaoTtsResourceIds = <({String value, String label})>[
  (value: 'seed-tts-2.0', label: 'seed-tts-2.0 (模型 2.0 字符版)'),
  (value: 'seed-tts-1.0', label: 'seed-tts-1.0 (模型 1.0 字符版)'),
  (value: 'seed-tts-1.0-concurr', label: 'seed-tts-1.0-concurr (模型 1.0 并发版)'),
];
const kDoubaoTtsUrl =
    'https://openspeech.bytedance.com/api/v3/tts/unidirectional';

class DoubaoVoice {
  final String label;
  final String value;
  final String lang;
  final String group;
  const DoubaoVoice(this.label, this.value, this.lang, this.group);
}

/// Mirrors auc-web/frontend/src/components/constants.ts TTS_VOICES.
const kDoubaoVoices = <DoubaoVoice>[
  DoubaoVoice('Vivi 2.0 (女)', 'zh_female_vv_uranus_bigtts',
      '中文/日文/印尼语/西语', '通用 - 多语种'),
  DoubaoVoice('Tina老师 2.0 (女)', 'zh_female_yingyujiaoxue_uranus_bigtts',
      '中文/英式英语', '通用 - 多语种'),
  DoubaoVoice('Tim (Male)', 'en_male_tim_uranus_bigtts', '美式英语', 'English'),
  DoubaoVoice(
      'Dacey (Female)', 'en_female_dacey_uranus_bigtts', '美式英语', 'English'),
  DoubaoVoice(
      'Stokie (Female)', 'en_female_stokie_uranus_bigtts', '美式英语', 'English'),
  DoubaoVoice('小何 2.0 (女)', 'zh_female_xiaohe_uranus_bigtts', '中文', '中文女声'),
  DoubaoVoice('清新女声 2.0 (女)', 'zh_female_qingxinnvsheng_uranus_bigtts',
      '中文', '中文女声'),
  DoubaoVoice('知性灿灿 2.0 (女)', 'zh_female_cancan_uranus_bigtts', '中文', '中文女声'),
  DoubaoVoice('撒娇学妹 2.0 (女)', 'zh_female_sajiaoxuemei_uranus_bigtts',
      '中文', '中文女声'),
  DoubaoVoice('甜美小源 2.0 (女)', 'zh_female_tianmeixiaoyuan_uranus_bigtts',
      '中文', '中文女声'),
  DoubaoVoice('甜美桃子 2.0 (女)', 'zh_female_tianmeitaozi_uranus_bigtts',
      '中文', '中文女声'),
  DoubaoVoice('爽快思思 2.0 (女)', 'zh_female_shuangkuaisisi_uranus_bigtts',
      '中文', '中文女声'),
  DoubaoVoice('邻家女孩 2.0 (女)', 'zh_female_linjianvhai_uranus_bigtts',
      '中文', '中文女声'),
  DoubaoVoice('魅力女友 2.0 (女)', 'zh_female_meilinvyou_uranus_bigtts',
      '中文', '中文女声'),
  DoubaoVoice('暖阳女声 2.0 (女)', 'zh_female_kefunvsheng_uranus_bigtts',
      '中文', '中文女声 - 客服'),
  DoubaoVoice('流畅女声 2.0 (女)', 'zh_female_liuchangnv_uranus_bigtts',
      '中文', '中文女声'),
  DoubaoVoice('云舟 2.0 (男)', 'zh_male_m191_uranus_bigtts', '中文', '中文男声'),
  DoubaoVoice('小天 2.0 (男)', 'zh_male_taocheng_uranus_bigtts', '中文', '中文男声'),
  DoubaoVoice('刘飞 2.0 (男)', 'zh_male_liufei_uranus_bigtts', '中文', '中文男声'),
  DoubaoVoice('少年梓辛 2.0 (男)', 'zh_male_shaonianzixin_uranus_bigtts',
      '中文', '中文男声'),
  DoubaoVoice('儒雅逸辰 2.0 (男)', 'zh_male_ruyayichen_uranus_bigtts',
      '中文', '中文男声'),
  DoubaoVoice('大壹 2.0 (男)', 'zh_male_dayi_uranus_bigtts', '中文', '中文男声'),
  DoubaoVoice('佩奇猪 2.0 (女)', 'zh_female_peiqi_uranus_bigtts', '中文', '特色/配音'),
  DoubaoVoice(
      '猴哥 2.0 (男)', 'zh_male_sunwukong_uranus_bigtts', '中文', '特色/配音'),
  DoubaoVoice('黑猫咪仔 2.0 (女)', 'zh_female_mizai_uranus_bigtts', '中文', '特色/配音'),
  DoubaoVoice('鸡汤女 2.0 (女)', 'zh_female_jitangnv_uranus_bigtts', '中文', '特色/配音'),
  DoubaoVoice('儿童绘本 2.0 (女)', 'zh_female_xiaoxue_uranus_bigtts', '中文', '特色/配音'),
];

class TtsService {
  final AudioPlayer _player = AudioPlayer();

  final _playingController = StreamController<bool>.broadcast();
  Stream<bool> get playingStream => _playingController.stream;
  bool _playing = false;
  bool get isPlaying => _playing;

  TtsService() {
    _player.onPlayerStateChanged.listen((st) {
      if (st == PlayerState.playing) {
        _setPlaying(true);
      } else if (st == PlayerState.stopped ||
          st == PlayerState.completed ||
          st == PlayerState.paused) {
        _setPlaying(false);
      }
    });
  }

  void _setPlaying(bool v) {
    if (_playing == v) return;
    _playing = v;
    _playingController.add(v);
  }

  Future<void> stop() async {
    await _player.stop();
    _setPlaying(false);
  }

  /// Resolves as soon as the player is idle. If nothing is playing,
  /// returns immediately; otherwise waits for the next transition to false.
  Future<void> waitForIdle() async {
    if (!_playing) return;
    await _playingController.stream.firstWhere((p) => !p);
  }

  Future<void> speak({
    required String text,
    required TtsMode mode,
    required String openAiApiKey,
    required String openAiModel,
    required String openAiVoice,
    String volcAppKey = '',
    String volcAccessKey = '',
    String volcResourceId = kDoubaoTtsResourceId,
    String volcSpeaker = 'zh_female_vv_uranus_bigtts',
    int volcSpeechRate = 0,
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (mode == TtsMode.off || text.trim().isEmpty) return;
    await stop();
    final c = client ?? http.Client();
    final owned = client == null;
    try {
      switch (mode) {
        case TtsMode.off:
          return;
        case TtsMode.openai:
          await _speakOpenAi(text, openAiApiKey, openAiModel, openAiVoice, c, timeout);
          return;
        case TtsMode.volcDoubao:
          await _speakDoubao(
            text: text,
            appKey: volcAppKey,
            accessKey: volcAccessKey,
            resourceId:
                volcResourceId.isEmpty ? kDoubaoTtsResourceId : volcResourceId,
            speaker: volcSpeaker,
            speechRate: volcSpeechRate,
            client: c,
            timeout: timeout,
          );
          return;
      }
    } finally {
      if (owned) c.close();
    }
  }

  Future<void> _speakOpenAi(String text, String apiKey, String model,
      String voice, http.Client client, Duration timeout) async {
    if (apiKey.isEmpty) {
      throw Exception('OpenAI API key is empty — set it in Settings.');
    }
    final resp = await client.post(
      Uri.parse('https://api.openai.com/v1/audio/speech'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body:
          '{"model":"$model","voice":"$voice","input":${_jsonString(text)},"response_format":"mp3"}',
    ).timeout(timeout);
    if (resp.statusCode >= 400) {
      throw Exception('OpenAI TTS ${resp.statusCode}: ${resp.body}');
    }
    await _player.play(
      BytesSource(Uint8List.fromList(resp.bodyBytes), mimeType: 'audio/mpeg'),
    );
  }

  Future<void> _speakDoubao({
    required String text,
    required String appKey,
    required String accessKey,
    required String resourceId,
    required String speaker,
    required int speechRate,
    required http.Client client,
    required Duration timeout,
  }) async {
    if (appKey.isEmpty || accessKey.isEmpty) {
      throw Exception(
          'Volcengine AppKey/AccessKey missing — set them in Settings.');
    }
    final payload = <String, dynamic>{
      'user': {'uid': appKey},
      'req_params': {
        'text': text,
        'speaker': speaker,
        'audio_params': {
          'format': 'mp3',
          'sample_rate': 24000,
          'speech_rate': speechRate,
        },
        'additions': '{"disable_markdown_filter":true}',
      },
    };
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    final body = jsonEncode(payload);
    debugPrint(
        '[TTS → Doubao] POST $kDoubaoTtsUrl speaker=$speaker rate=$speechRate');
    final resp = await client.post(
      Uri.parse(kDoubaoTtsUrl),
      headers: {
        'Content-Type': 'application/json',
        'Connection': 'keep-alive',
        'X-Api-App-Id': appKey,
        'X-Api-Access-Key': accessKey,
        'X-Api-Resource-Id': resourceId,
        'X-Api-Request-Id': requestId,
      },
      body: body,
    ).timeout(timeout);
    if (resp.statusCode >= 400) {
      throw Exception('Doubao TTS ${resp.statusCode}: ${resp.body}');
    }
    final chunks = <int>[];
    for (final line in LineSplitter.split(resp.body)) {
      if (line.trim().isEmpty) continue;
      final Map<String, dynamic> obj;
      try {
        obj = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final code = obj['code'] as int? ?? 0;
      if (code == 20000000) break;
      if (code != 0) {
        throw Exception(
            'Doubao TTS error code=$code ${obj['message'] ?? ''}');
      }
      final data = obj['data'] as String?;
      if (data != null && data.isNotEmpty) {
        chunks.addAll(base64.decode(data));
      }
    }
    if (chunks.isEmpty) {
      throw Exception('Doubao TTS: no audio data returned');
    }
    await _player.play(
      BytesSource(Uint8List.fromList(chunks), mimeType: 'audio/mpeg'),
    );
  }

  String _jsonString(String s) {
    final escaped = s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '"$escaped"';
  }

  void dispose() {
    _playingController.close();
    _player.dispose();
  }
}
