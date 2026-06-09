import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog.dart';

const kRelayProviderId = 'relay';
const kRelayBaseUrlExample = 'https://relay.example.com/v1/models';

String normalizeRelayBaseUrl(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return '';
  if (!value.contains('://')) value = 'https://$value';
  value = value.replaceAll(RegExp(r'/+$'), '');
  var uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return '';
  if (uri.path.endsWith('/models')) {
    final trimmedPath = uri.path.substring(0, uri.path.length - 7);
    value = uri
        .replace(path: trimmedPath.isEmpty ? '' : trimmedPath)
        .toString();
    uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return '';
  }
  if (uri.path.isEmpty) return '$value/v1';
  return value;
}

Uri relayCatalogUri(String baseUrl) {
  final normalized = normalizeRelayBaseUrl(baseUrl);
  if (normalized.isEmpty) {
    throw ArgumentError.value(baseUrl, 'baseUrl', 'Relay Base URL is required');
  }
  if (normalized.endsWith('/models')) return Uri.parse(normalized);
  return Uri.parse('$normalized/models');
}

Future<String> fetchRelayCatalogJson(
  String baseUrl, {
  String apiKey = '',
  http.Client? client,
}) async {
  final normalized = normalizeRelayBaseUrl(baseUrl);
  if (normalized.isEmpty) {
    throw ArgumentError.value(baseUrl, 'baseUrl', 'Relay Base URL is required');
  }
  final c = client ?? http.Client();
  final owned = client == null;
  try {
    final headers = <String, String>{};
    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    final resp = await c.get(relayCatalogUri(normalized), headers: headers);
    final body = utf8.decode(resp.bodyBytes);
    if (resp.statusCode >= 400) {
      throw Exception('Relay catalog ${resp.statusCode}: $body');
    }
    // Validate before caching.
    relayProviderFromJson(normalized, jsonDecode(body));
    return body;
  } finally {
    if (owned) c.close();
  }
}

ProviderSpec relayProviderFromJson(String baseUrl, Object? decoded) {
  final normalizedBaseUrl = normalizeRelayBaseUrl(baseUrl);
  if (normalizedBaseUrl.isEmpty) {
    throw ArgumentError.value(baseUrl, 'baseUrl', 'Relay Base URL is required');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Relay catalog root must be an object');
  }
  final providersById = <String, String>{};
  final providers = decoded['providers'];
  if (providers is List) {
    for (final item in providers.whereType<Map>()) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      providersById[id] = item['name']?.toString() ?? id;
    }
  }
  final rawModels = decoded['models'];
  final rawOpenAIModels = decoded['data'];
  final modelItems = rawModels is List
      ? rawModels
      : rawOpenAIModels is List
      ? rawOpenAIModels
      : null;
  if (modelItems == null) {
    throw const FormatException('Relay model list must be models[] or data[]');
  }
  final models = <ModelSpec>[];
  for (final item in modelItems.whereType<Map>()) {
    final publicId =
        item['public_id']?.toString() ?? item['id']?.toString() ?? '';
    if (publicId.isEmpty) continue;
    final caps = _capabilities(item['capabilities']);
    final safeCaps = caps.isEmpty ? {Capability.chat} : caps;
    final providerId =
        item['provider_id']?.toString() ?? item['owned_by']?.toString() ?? '';
    final providerName = providersById[providerId] ?? providerId;
    final displayName =
        item['display_name']?.toString() ?? item['name']?.toString();
    final label = [
      if (providerName.isNotEmpty) providerName,
      displayName == null || displayName.isEmpty ? publicId : displayName,
    ].join(' · ');
    models.add(
      ModelSpec(
        id: publicId,
        label: label,
        caps: safeCaps,
        inputs: _modalities(
          item['input_modalities'] ??
              (item['architecture'] is Map
                  ? (item['architecture'] as Map)['input_modalities']
                  : null),
        ),
        voices: _voices(item['voices'] ?? item['supported_voices']),
        sttTransport: _sttTransport(item['stt_transport']),
        supportsDirectAudioTranslate:
            item['supports_direct_audio_translate'] == true,
      ),
    );
  }
  models.sort((a, b) => a.label.compareTo(b.label));
  return ProviderSpec(
    id: kRelayProviderId,
    name: 'AI Chat Relay',
    baseUrl: normalizedBaseUrl,
    dialects: const {
      Capability.chat: ApiDialect.openaiChat,
      Capability.stt: ApiDialect.openaiTranscribe,
      Capability.tts: ApiDialect.openaiSpeech,
    },
    credentials: const [CredentialField.apiKey],
    models: models,
  );
}

Set<Capability> _capabilities(Object? raw) {
  final out = <Capability>{};
  if (raw is! List) return out;
  for (final item in raw) {
    switch (item.toString()) {
      case 'chat':
        out.add(Capability.chat);
        break;
      case 'stt':
        out.add(Capability.stt);
        break;
      case 'tts':
        out.add(Capability.tts);
        break;
    }
  }
  return out;
}

Set<Modality> _modalities(Object? raw) {
  final out = <Modality>{Modality.text};
  if (raw is! List) return out;
  for (final item in raw) {
    switch (item.toString()) {
      case 'audio':
        out.add(Modality.audio);
        break;
      case 'image':
        out.add(Modality.image);
        break;
      case 'text':
        out.add(Modality.text);
        break;
    }
  }
  return out;
}

SttTransport? _sttTransport(Object? raw) {
  switch (raw?.toString()) {
    case 'batchUpload':
      return SttTransport.batchUpload;
    case 'asyncJob':
      return SttTransport.asyncJob;
    case 'realtime':
      return SttTransport.realtime;
  }
  return null;
}

List<TtsVoice> _voices(Object? raw) {
  if (raw is! List) return const [];
  final out = <TtsVoice>[];
  for (final item in raw) {
    if (item is! Map) {
      final id = item.toString();
      if (id.isNotEmpty && id != 'null') out.add(TtsVoice(id, id));
      continue;
    }
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    out.add(
      TtsVoice(
        id,
        item['label']?.toString() ?? id,
        lang: item['lang']?.toString(),
        group: item['group']?.toString(),
      ),
    );
  }
  return out;
}
