import 'dart:convert';

class Scene {
  final String id;
  String name;
  String prompt;

  Scene({required this.id, required this.name, required this.prompt});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'prompt': prompt};

  factory Scene.fromJson(Map<String, dynamic> j) =>
      Scene(id: j['id'], name: j['name'], prompt: j['prompt']);
}

const kDefaultSceneId = 'default';

// Default scenes mirror auc-web/frontend/src/components/utils.ts → defaultPipelineSettings().scenarios.
List<Scene> defaultScenes() => [
      Scene(
        id: kDefaultSceneId,
        name: '旅游',
        prompt: '结合旅游场景的语境，修正文字',
      ),
      Scene(
        id: 'general',
        name: '通用',
        prompt: '修正文字中的错别字和语法问题',
      ),
    ];

String encodeScenes(List<Scene> scenes) =>
    jsonEncode(scenes.map((s) => s.toJson()).toList());

List<Scene> decodeScenes(String raw) {
  final list = jsonDecode(raw) as List;
  return list.map((e) => Scene.fromJson(e as Map<String, dynamic>)).toList();
}
