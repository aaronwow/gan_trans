import 'package:ai_chat/catalog.dart';
import 'package:ai_chat/relay_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relay catalog maps public models into a single provider', () {
    final provider = relayProviderFromJson('https://relay.example.com/v1', {
      'providers': [
        {'id': 'openai', 'name': 'OpenAI'},
        {'id': 'volcengine', 'name': 'Doubao'},
      ],
      'models': [
        {
          'public_id': 'openai:gpt-4o-mini',
          'provider_id': 'openai',
          'display_name': 'GPT-4o mini',
          'capabilities': ['chat'],
          'input_modalities': ['text', 'image'],
          'supports_direct_audio_translate': false,
        },
        {
          'public_id': 'volcengine:seed-tts-2.0',
          'provider_id': 'volcengine',
          'display_name': 'seed-tts-2.0',
          'capabilities': ['tts'],
          'input_modalities': ['text'],
          'voices': [
            {'id': 'zh_female_vv_uranus_bigtts', 'label': 'VV'},
          ],
        },
      ],
    });

    expect(provider.id, kRelayProviderId);
    expect(provider.baseUrl, 'https://relay.example.com/v1');
    expect(provider.dialects[Capability.chat], ApiDialect.openaiChat);
    expect(provider.dialects[Capability.stt], ApiDialect.openaiTranscribe);
    expect(provider.dialects[Capability.tts], ApiDialect.openaiSpeech);
    expect(provider.models, hasLength(2));

    final chat = provider.findModel('openai:gpt-4o-mini')!;
    expect(chat.supports(Capability.chat), isTrue);
    expect(chat.acceptsImage(), isTrue);
    expect(chat.label, 'OpenAI · GPT-4o mini');

    final tts = provider.findModel('volcengine:seed-tts-2.0')!;
    expect(tts.supports(Capability.tts), isTrue);
    expect(tts.voices.single.id, 'zh_female_vv_uranus_bigtts');
  });

  test('relay model list maps OpenAI-compatible data as chat models', () {
    final provider = relayProviderFromJson('https://relay.example.com/v1', {
      'object': 'list',
      'data': [
        {'id': 'llama-3.3-70b', 'object': 'model', 'owned_by': 'local'},
      ],
    });

    expect(provider.models, hasLength(1));
    final model = provider.findModel('llama-3.3-70b')!;
    expect(model.supports(Capability.chat), isTrue);
    expect(model.supports(Capability.stt), isFalse);
    expect(model.supports(Capability.tts), isFalse);
    expect(model.label, 'local · llama-3.3-70b');
  });

  test('relay base URL normalization appends v1 only for bare origins', () {
    expect(normalizeRelayBaseUrl(''), '');
    expect(
      normalizeRelayBaseUrl('relay.example.com'),
      'https://relay.example.com/v1',
    );
    expect(
      normalizeRelayBaseUrl('https://relay.example.com/v1/'),
      'https://relay.example.com/v1',
    );
    expect(
      normalizeRelayBaseUrl('https://relay.example.com/v1/models'),
      'https://relay.example.com/v1',
    );
    expect(
      normalizeRelayBaseUrl('https://example.com/custom'),
      'https://example.com/custom',
    );
  });
}
